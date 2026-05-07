import Foundation
import CircuitStudioCore
import LayoutCore

@MainActor
public final class HeadlessRoundTripService {
    public struct Configuration {
        public let projectRoot: URL
        public let runID: String
        public let title: String
        public let testbench: Testbench
        public let postLayoutCommand: AnalysisCommand
        public let pexIR: PEXParasiticIR
        public let externalSignoffCommands: [ExternalSignoffCommand]
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
            externalSignoffCommands: [ExternalSignoffCommand] = [],
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
            self.externalSignoffCommands = externalSignoffCommands
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

        public init(kind: String, path: String) {
            self.kind = kind
            self.path = path
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
            throw StudioError.invalidDesign("Headless round trip requires at least one extracted net.")
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

        let preLayoutResult = try await SimulationService().runSPICE(
            source: baseNetlist,
            fileName: "\(configuration.runID)-pre.cir"
        )
        stages.append(Stage(
            name: "pre-layout-simulation",
            status: preLayoutResult.status == .completed ? .passed : .failed,
            message: preLayoutResult.status.rawValue
        ))
        guard preLayoutResult.status == .completed else {
            throw StudioError.simulationFailure("Pre-layout simulation did not complete.")
        }

        let layoutOutput = try AutoLayoutService().generate(
            from: schematic,
            catalog: configuration.catalog
        )
        stages.append(Stage(
            name: "auto-layout",
            status: layoutOutput.unroutedNets.isEmpty ? .passed : .failed,
            message: layoutOutput.unroutedNets.isEmpty ? nil : "Unrouted nets: \(layoutOutput.unroutedNets.joined(separator: ", "))"
        ))
        guard layoutOutput.unroutedNets.isEmpty else {
            throw StudioError.invalidDesign("Auto layout left unrouted nets.")
        }

        let externalSignoff = try runExternalSignoffIfNeeded(
            configuration: configuration,
            runDirectory: runDirectory
        )
        if let externalSignoff {
            artifacts.append(contentsOf: externalSignoff.reports.map {
                Artifact(kind: "external-signoff-log", path: $0.logPath)
            })
            artifacts.append(Artifact(
                kind: "external-signoff-review",
                path: ExternalSignoffReviewStore()
                    .reviewURL(projectRoot: configuration.projectRoot)
                    .path(percentEncoded: false)
            ))
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
            throw StudioError.invalidDesign("Pre-PEX verification gate failed.")
        }

        let postLayoutService = PostLayoutSimulationService()
        let postLayoutNetlist = postLayoutService.buildPostLayoutNetlist(
            baseNetlist: baseNetlist,
            parasitics: configuration.pexIR
        )
        let postLayoutNetlistURL = runDirectory.appending(path: "post-layout.cir")
        try write(postLayoutNetlist, to: postLayoutNetlistURL)
        artifacts.append(Artifact(kind: "post-layout-netlist", path: postLayoutNetlistURL.path(percentEncoded: false)))
        stages.append(Stage(
            name: "pex-injection",
            status: configuration.pexIR.elements.isEmpty ? .failed : .passed,
            message: "\(configuration.pexIR.elements.count) parasitic elements"
        ))
        guard !configuration.pexIR.elements.isEmpty else {
            throw StudioError.invalidDesign("Headless round trip requires non-empty PEX IR.")
        }

        let postLayoutResult = try await postLayoutService.runPostLayoutAnalysis(
            baseNetlist: baseNetlist,
            parasitics: configuration.pexIR,
            command: configuration.postLayoutCommand
        )
        stages.append(Stage(
            name: "post-layout-simulation",
            status: postLayoutResult.status == .completed ? .passed : .failed,
            message: postLayoutResult.status.rawValue
        ))
        guard postLayoutResult.status == .completed else {
            throw StudioError.simulationFailure("Post-layout simulation did not complete.")
        }

        let manifest = Manifest(
            runID: configuration.runID,
            title: configuration.title,
            createdAt: configuration.createdAt,
            isRoundTripComplete: true,
            isReadyForPEX: verification.isReadyForPEX,
            stages: stages,
            artifacts: artifacts
        )
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeJSON(manifest, to: manifestURL)

        return Result(
            manifest: manifest,
            manifestURL: manifestURL,
            verification: verification,
            preLayoutResult: preLayoutResult,
            postLayoutResult: postLayoutResult,
            externalSignoff: externalSignoff
        )
    }

    private func runExternalSignoffIfNeeded(
        configuration: Configuration,
        runDirectory: URL
    ) throws -> ExternalSignoffReview? {
        guard !configuration.externalSignoffCommands.isEmpty else {
            return nil
        }

        let store = ExternalSignoffReviewStore()
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
