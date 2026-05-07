import Foundation
import CircuitStudioCore
import LayoutCore

@MainActor
public final class HeadlessRoundTripService {
    private static let orderedStageNames = [
        "net-extraction",
        "netlist-generation",
        "pre-layout-simulation",
        "auto-layout",
        "external-signoff",
        "pre-pex-verification",
        "pex-injection",
        "post-layout-simulation",
        "post-layout-comparison",
    ]

    public struct Configuration {
        public let projectRoot: URL
        public let runID: String
        public let title: String
        public let testbench: Testbench
        public let postLayoutCommand: AnalysisCommand
        public let pexIR: PEXParasiticIR
        public let pexArtifactPaths: [String]
        public let externalSignoffCommands: [ExternalSignoffCommand]
        public let externalSignoffReview: ExternalSignoffReview?
        public let approvedBy: String?
        public let approvedAt: Date?
        public let waiverIDs: [String]
        public let createdAt: Date
        public let catalog: DeviceCatalog
        public let continueAfterFailedPrePEXGate: Bool

        public init(
            projectRoot: URL,
            runID: String = UUID().uuidString,
            title: String,
            testbench: Testbench,
            postLayoutCommand: AnalysisCommand,
            pexIR: PEXParasiticIR,
            pexArtifactPaths: [String] = [],
            externalSignoffCommands: [ExternalSignoffCommand] = [],
            externalSignoffReview: ExternalSignoffReview? = nil,
            approvedBy: String? = nil,
            approvedAt: Date? = nil,
            waiverIDs: [String] = [],
            createdAt: Date = Date(),
            catalog: DeviceCatalog = .standard(),
            continueAfterFailedPrePEXGate: Bool = false
        ) {
            self.projectRoot = projectRoot
            self.runID = runID
            self.title = title
            self.testbench = testbench
            self.postLayoutCommand = postLayoutCommand
            self.pexIR = pexIR
            self.pexArtifactPaths = pexArtifactPaths
            self.externalSignoffCommands = externalSignoffCommands
            self.externalSignoffReview = externalSignoffReview
            self.approvedBy = approvedBy
            self.approvedAt = approvedAt
            self.waiverIDs = waiverIDs
            self.createdAt = createdAt
            self.catalog = catalog
            self.continueAfterFailedPrePEXGate = continueAfterFailedPrePEXGate
        }
    }

    public struct Result {
        public let manifest: Manifest
        public let manifestURL: URL
        public let verification: PhysicalVerificationReport
        public let preLayoutResult: SimulationResult
        public let postLayoutResult: SimulationResult
        public let externalSignoff: ExternalSignoffReview?

        public init(
            manifest: Manifest,
            manifestURL: URL,
            verification: PhysicalVerificationReport,
            preLayoutResult: SimulationResult,
            postLayoutResult: SimulationResult,
            externalSignoff: ExternalSignoffReview?
        ) {
            self.manifest = manifest
            self.manifestURL = manifestURL
            self.verification = verification
            self.preLayoutResult = preLayoutResult
            self.postLayoutResult = postLayoutResult
            self.externalSignoff = externalSignoff
        }
    }

    public struct Manifest: Sendable, Hashable, Codable {
        public let runID: String
        public let title: String
        public let createdAt: Date
        public let isRoundTripComplete: Bool
        public let isReadyForPEX: Bool
        public let stages: [Stage]
        public let artifacts: [Artifact]

        public init(
            runID: String,
            title: String,
            createdAt: Date,
            isRoundTripComplete: Bool,
            isReadyForPEX: Bool,
            stages: [Stage],
            artifacts: [Artifact]
        ) {
            self.runID = runID
            self.title = title
            self.createdAt = createdAt
            self.isRoundTripComplete = isRoundTripComplete
            self.isReadyForPEX = isReadyForPEX
            self.stages = stages
            self.artifacts = artifacts
        }
    }

    public struct Stage: Sendable, Hashable, Codable {
        public enum Status: String, Sendable, Hashable, Codable {
            case passed
            case failed
            case skipped
        }

        public let name: String
        public let status: Status
        public let message: String?

        public init(name: String, status: Status, message: String? = nil) {
            self.name = name
            self.status = status
            self.message = message
        }
    }

    public struct Artifact: Sendable, Hashable, Codable {
        public let kind: String
        public let path: String
        public let sourcePath: String?

        public init(kind: String, path: String, sourcePath: String? = nil) {
            self.kind = kind
            self.path = path
            self.sourcePath = sourcePath
        }
    }

    public init() {}

    public func run(
        schematic: SchematicDocument,
        configuration: Configuration
    ) async throws -> Result {
        let projectService = ProjectService()
        if !projectService.isProject(configuration.projectRoot) {
            try projectService.createProject(at: configuration.projectRoot)
        }

        let runDirectory = configuration.projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: configuration.runID)
        try createDirectory(runDirectory)

        var stages: [Stage] = []
        var artifacts: [Artifact] = []

        let nets = NetExtractor().extract(from: schematic)
        stages.append(Stage(
            name: "net-extraction",
            status: nets.isEmpty ? .failed : .passed,
            message: "\(nets.count) nets"
        ))
        guard !nets.isEmpty else {
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: StudioError.invalidDesign("Headless round trip requires at least one extracted net.")
            )
        }

        let baseNetlist = NetlistGenerator().generate(
            from: schematic,
            title: configuration.title,
            testbench: configuration.testbench
        )
        let preLayoutNetlistURL = runDirectory.appending(path: "pre-layout.cir")
        try write(baseNetlist, to: preLayoutNetlistURL)
        artifacts.append(Artifact(kind: "pre-layout-netlist", path: preLayoutNetlistURL.path(percentEncoded: false)))
        stages.append(Stage(name: "netlist-generation", status: .passed))

        let preLayoutResult: SimulationResult
        do {
            preLayoutResult = try await SimulationService().runSPICE(
                source: baseNetlist,
                fileName: "\(configuration.runID)-pre.cir"
            )
        } catch {
            stages.append(Stage(
                name: "pre-layout-simulation",
                status: .failed,
                message: error.localizedDescription
            ))
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }
        stages.append(Stage(
            name: "pre-layout-simulation",
            status: preLayoutResult.status == .completed ? .passed : .failed,
            message: preLayoutResult.status.rawValue
        ))
        guard preLayoutResult.status == .completed else {
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: StudioError.simulationFailure("Pre-layout simulation did not complete.")
            )
        }

        let layoutOutput: AutoLayoutOutput
        do {
            layoutOutput = try AutoLayoutService().generate(
                from: schematic,
                catalog: configuration.catalog
            )
        } catch {
            stages.append(Stage(
                name: "auto-layout",
                status: .failed,
                message: error.localizedDescription
            ))
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }
        stages.append(Stage(
            name: "auto-layout",
            status: layoutOutput.unroutedNets.isEmpty ? .passed : .failed,
            message: layoutOutput.unroutedNets.isEmpty ? nil : "Unrouted nets: \(layoutOutput.unroutedNets.joined(separator: ", "))"
        ))
        guard layoutOutput.unroutedNets.isEmpty else {
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: StudioError.invalidDesign("Auto layout left unrouted nets.")
            )
        }

        let externalSignoff: ExternalSignoffReview?
        do {
            externalSignoff = try runExternalSignoffIfNeeded(
                configuration: configuration,
                runDirectory: runDirectory
            )
        } catch {
            stages.append(Stage(
                name: "external-signoff",
                status: .failed,
                message: error.localizedDescription
            ))
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }
        if let externalSignoff {
            do {
                artifacts.append(contentsOf: try captureInputArtifacts(
                    paths: externalSignoff.reports.map(\.logPath),
                    kind: "external-signoff-log",
                    runDirectory: runDirectory,
                    subdirectory: "signoff"
                ))
                artifacts.append(Artifact(
                    kind: "external-signoff-review",
                    path: ExternalSignoffReviewStore()
                        .reviewURL(projectRoot: configuration.projectRoot)
                        .path(percentEncoded: false)
                ))
                stages.append(Stage(
                    name: "external-signoff",
                    status: externalSignoff.isReadyForPEX ? .passed : .failed,
                    message: externalSignoff.isReadyForPEX ? nil : "external signoff not ready"
                ))
            } catch {
                stages.append(Stage(
                    name: "external-signoff",
                    status: .failed,
                    message: error.localizedDescription
                ))
                try failRun(
                    configuration: configuration,
                    runDirectory: runDirectory,
                    stages: &stages,
                    artifacts: artifacts,
                    error: error
                )
            }
        }

        let verification = PhysicalVerificationService().runPrePEXVerification(
            schematic: schematic,
            layout: layoutOutput.document,
            tech: layoutOutput.tech,
            designUnit: layoutOutput.designUnit,
            catalog: configuration.catalog,
            externalSignoff: externalSignoff
        )
        stages.append(Stage(
            name: "pre-pex-verification",
            status: verification.isReadyForPEX ? .passed : .failed,
            message: verification.isReadyForPEX ? nil : prePEXFailureMessage(verification)
        ))
        if !verification.isReadyForPEX && !configuration.continueAfterFailedPrePEXGate {
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verification.isReadyForPEX,
                stages: &stages,
                artifacts: artifacts,
                error: StudioError.invalidDesign("Pre-PEX verification gate failed.")
            )
        }

        let postLayoutService = PostLayoutSimulationService()
        let postLayoutNetlist = postLayoutService.buildPostLayoutNetlist(
            baseNetlist: baseNetlist,
            parasitics: configuration.pexIR
        )
        let postLayoutNetlistURL = runDirectory.appending(path: "post-layout.cir")
        do {
            try write(postLayoutNetlist, to: postLayoutNetlistURL)
            artifacts.append(contentsOf: try captureInputArtifacts(
                paths: configuration.pexArtifactPaths,
                kind: "pex-artifact",
                runDirectory: runDirectory,
                subdirectory: "pex"
            ))
            artifacts.append(Artifact(kind: "post-layout-netlist", path: postLayoutNetlistURL.path(percentEncoded: false)))
            stages.append(Stage(
                name: "pex-injection",
                status: configuration.pexIR.elements.isEmpty ? .failed : .passed,
                message: "\(configuration.pexIR.elements.count) parasitic elements"
            ))
        } catch {
            stages.append(Stage(
                name: "pex-injection",
                status: .failed,
                message: error.localizedDescription
            ))
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verification.isReadyForPEX,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }
        guard !configuration.pexIR.elements.isEmpty else {
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verification.isReadyForPEX,
                stages: &stages,
                artifacts: artifacts,
                error: StudioError.invalidDesign("Headless round trip requires non-empty PEX IR.")
            )
        }

        let postLayoutResult: SimulationResult
        do {
            postLayoutResult = try await postLayoutService.runPostLayoutAnalysis(
                baseNetlist: baseNetlist,
                parasitics: configuration.pexIR,
                command: configuration.postLayoutCommand
            )
        } catch {
            stages.append(Stage(
                name: "post-layout-simulation",
                status: .failed,
                message: error.localizedDescription
            ))
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verification.isReadyForPEX,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }
        stages.append(Stage(
            name: "post-layout-simulation",
            status: postLayoutResult.status == .completed ? .passed : .failed,
            message: postLayoutResult.status.rawValue
        ))
        guard postLayoutResult.status == .completed else {
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verification.isReadyForPEX,
                stages: &stages,
                artifacts: artifacts,
                error: StudioError.simulationFailure("Post-layout simulation did not complete.")
            )
        }

        let comparisonReport = PostLayoutComparisonService().compare(
            preLayoutResult: preLayoutResult,
            postLayoutResult: postLayoutResult
        )
        let comparisonReportURL = runDirectory.appending(path: "post-layout-comparison.json")
        do {
            try writeJSON(comparisonReport, to: comparisonReportURL)
            artifacts.append(Artifact(
                kind: "post-layout-comparison",
                path: comparisonReportURL.path(percentEncoded: false)
            ))
        } catch {
            stages.append(Stage(
                name: "post-layout-comparison",
                status: .failed,
                message: error.localizedDescription
            ))
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verification.isReadyForPEX,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }
        stages.append(Stage(
            name: "post-layout-comparison",
            status: .passed,
            message: comparisonReport.status
        ))

        let manifestURL = try writeManifest(
            configuration: configuration,
            runDirectory: runDirectory,
            isRoundTripComplete: true,
            isReadyForPEX: verification.isReadyForPEX,
            stages: stages,
            artifacts: artifacts
        )
        let manifest = try readManifest(from: manifestURL)

        return Result(
            manifest: manifest,
            manifestURL: manifestURL,
            verification: verification,
            preLayoutResult: preLayoutResult,
            postLayoutResult: postLayoutResult,
            externalSignoff: externalSignoff
        )
    }

    private func failRun(
        configuration: Configuration,
        runDirectory: URL,
        isReadyForPEX: Bool = false,
        stages: inout [Stage],
        artifacts: [Artifact],
        error: Error
    ) throws -> Never {
        stages.append(contentsOf: skippedStages(after: stages))
        _ = try writeManifest(
            configuration: configuration,
            runDirectory: runDirectory,
            isRoundTripComplete: false,
            isReadyForPEX: isReadyForPEX,
            stages: stages,
            artifacts: artifacts
        )
        throw error
    }

    private func skippedStages(after stages: [Stage]) -> [Stage] {
        let existingNames = Set(stages.map(\.name))
        guard let lastIndex = Self.orderedStageNames.lastIndex(where: existingNames.contains) else {
            return []
        }
        return Self.orderedStageNames[(lastIndex + 1)...].compactMap { name in
            existingNames.contains(name) ? nil : Stage(name: name, status: .skipped)
        }
    }

    private func writeManifest(
        configuration: Configuration,
        runDirectory: URL,
        isRoundTripComplete: Bool,
        isReadyForPEX: Bool,
        stages: [Stage],
        artifacts: [Artifact]
    ) throws -> URL {
        let manifest = Manifest(
            runID: configuration.runID,
            title: configuration.title,
            createdAt: configuration.createdAt,
            isRoundTripComplete: isRoundTripComplete,
            isReadyForPEX: isReadyForPEX,
            stages: stages,
            artifacts: artifacts
        )
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeJSON(manifest, to: manifestURL)
        return manifestURL
    }

    private func readManifest(from url: URL) throws -> Manifest {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Manifest.self, from: data)
        } catch {
            throw StudioError.projectLoadFailed("Failed to read headless flow manifest: \(error.localizedDescription)")
        }
    }

    private func runExternalSignoffIfNeeded(
        configuration: Configuration,
        runDirectory: URL
    ) throws -> ExternalSignoffReview? {
        let store = ExternalSignoffReviewStore()
        if var review = configuration.externalSignoffReview {
            try store.save(review, projectRoot: configuration.projectRoot)
            if let approvedBy = configuration.approvedBy,
               let approvedAt = configuration.approvedAt {
                review = review.approving(
                    by: approvedBy,
                    at: approvedAt,
                    waiverIDs: configuration.waiverIDs
                )
                try store.save(review, projectRoot: configuration.projectRoot)
            }
            return review
        }

        guard !configuration.externalSignoffCommands.isEmpty else {
            return nil
        }

        let artifactDirectory = runDirectory.appending(path: "external-signoff")
        var review = try ExternalSignoffCommandService().run(
            commands: configuration.externalSignoffCommands,
            artifactDirectory: artifactDirectory
        )
        try store.save(review, projectRoot: configuration.projectRoot)

        if let approvedBy = configuration.approvedBy,
           let approvedAt = configuration.approvedAt {
            review = try store.approve(
                projectRoot: configuration.projectRoot,
                approvedBy: approvedBy,
                approvedAt: approvedAt,
                waiverIDs: configuration.waiverIDs
            )
        }

        return review
    }

    private func captureInputArtifacts(
        paths: [String],
        kind: String,
        runDirectory: URL,
        subdirectory: String
    ) throws -> [Artifact] {
        guard !paths.isEmpty else {
            return []
        }

        let captureDirectory = runDirectory
            .appending(path: "input-artifacts")
            .appending(path: subdirectory)
        try createDirectory(captureDirectory)

        var usedNames = Set<String>()
        return try paths.map { path in
            let sourceURL = URL(filePath: path)
            let sourcePath = sourceURL.path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: sourcePath) else {
                throw StudioError.projectLoadFailed("Input artifact not found: \(sourcePath)")
            }

            if sourcePath.hasPrefix(runDirectory.path(percentEncoded: false)) {
                return Artifact(kind: kind, path: sourcePath)
            }

            let destinationURL = uniqueCaptureURL(
                for: sourceURL,
                in: captureDirectory,
                usedNames: &usedNames
            )
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                throw StudioError.projectSaveFailed(
                    "Failed to capture input artifact \(sourcePath): \(error.localizedDescription)"
                )
            }

            return Artifact(
                kind: kind,
                path: destinationURL.path(percentEncoded: false),
                sourcePath: sourcePath
            )
        }
    }

    private func uniqueCaptureURL(
        for sourceURL: URL,
        in directory: URL,
        usedNames: inout Set<String>
    ) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let pathExtension = sourceURL.pathExtension
        var candidateName = sourceURL.lastPathComponent
        var index = 1
        while usedNames.contains(candidateName)
            || FileManager.default.fileExists(atPath: directory.appending(path: candidateName).path(percentEncoded: false)) {
            let suffix = "-\(index)"
            candidateName = pathExtension.isEmpty
                ? "\(baseName)\(suffix)"
                : "\(baseName)\(suffix).\(pathExtension)"
            index += 1
        }
        usedNames.insert(candidateName)
        return directory.appending(path: candidateName)
    }

    private func prePEXFailureMessage(_ verification: PhysicalVerificationReport) -> String {
        var parts: [String] = []
        if !verification.drc.passed {
            parts.append("DRC violations: \(verification.drc.violationCount)")
        }
        if !verification.lvs.passed {
            parts.append("LVS failed")
        }
        if let externalSignoff = verification.externalSignoff, !externalSignoff.isReadyForPEX {
            parts.append("external signoff not ready")
        }
        return parts.isEmpty ? "DRC/LVS/signoff gate failed" : parts.joined(separator: "; ")
    }

    private func createDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw StudioError.projectSaveFailed("Failed to create headless flow directory: \(error.localizedDescription)")
        }
    }

    private func write(_ contents: String, to url: URL) throws {
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw StudioError.projectSaveFailed("Failed to write \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw StudioError.projectSaveFailed("Failed to encode headless flow manifest: \(error.localizedDescription)")
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw StudioError.projectSaveFailed("Failed to write headless flow manifest: \(error.localizedDescription)")
        }
    }
}
