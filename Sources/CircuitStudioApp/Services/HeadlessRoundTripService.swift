import Foundation
import CircuiteFoundation
import CircuitStudioCore
import CircuitPhysicalDesign
import CoreSpiceWaveform
import LayoutCore
import LayoutTech
import LayoutEngine
import DesignFlowKernel

@MainActor
public final class HeadlessRoundTripService {
    private static let orderedStageNames = [
        "input-artifact-capture",
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

    private let layoutEngineCatalog: any LayoutEngineCataloging
    private let runLedger: any XcircuiteRunLedgerStoring

    public init(
        layoutEngineCatalog: any LayoutEngineCataloging = CircuitPhysicalDesignDefaults.layoutEngineCatalog(),
        runLedger: any XcircuiteRunLedgerStoring = XcircuitePackageStore()
    ) {
        self.layoutEngineCatalog = layoutEngineCatalog
        self.runLedger = runLedger
    }

    public func run(
        schematic: SchematicDocument,
        configuration: Configuration
    ) async throws -> Result {
        try Self.validateRunID(configuration.runID)
        try validateComparisonLimits(configuration.postLayoutComparisonLimits)

        let projectService = ProjectService()
        if !projectService.isProject(configuration.projectRoot) {
            try projectService.createProject(at: configuration.projectRoot)
        }

        let runDirectory = try runLedger.createRunDirectory(
            for: configuration.runID,
            descriptor: XcircuiteRunDescriptor(
                actor: configuration.actor,
                intent: configuration.title,
                createdAt: configuration.createdAt
            ),
            inProjectAt: configuration.projectRoot
        )
        _ = try runLedger.transitionRun(
            runID: configuration.runID,
            transition: XcircuiteRunTransition(status: .running),
            inProjectAt: configuration.projectRoot
        )

        do {
            return try await executeRun(
                schematic: schematic,
                configuration: configuration,
                runDirectory: runDirectory
            )
        } catch {
            do {
                try markRunFailedIfNeeded(
                    configuration: configuration,
                    runDirectory: runDirectory,
                    error: error
                )
            } catch let lifecycleError {
                throw StudioError.projectSaveFailed(
                    "Headless flow failed with '\(error.localizedDescription)' and the canonical run lifecycle could not be finalized: \(lifecycleError.localizedDescription)"
                )
            }
            throw error
        }
    }

    private func executeRun(
        schematic: SchematicDocument,
        configuration: Configuration,
        runDirectory: URL
    ) async throws -> Result {
        var stages: [Stage] = []
        var artifacts: [Artifact] = []
        let inputArtifactCaptureStartedAt = Date()
        do {
            let capturedArtifacts = try captureInputArtifacts(
                paths: configuration.designArtifactPaths,
                kind: "design-spec",
                runDirectory: runDirectory,
                subdirectory: "design"
            )
            artifacts.append(contentsOf: capturedArtifacts)
            stages.append(Stage(
                name: "input-artifact-capture",
                status: .passed,
                message: "\(capturedArtifacts.count) artifacts",
                durationSeconds: duration(since: inputArtifactCaptureStartedAt)
            ))
        } catch {
            stages.append(Stage(
                name: "input-artifact-capture",
                status: .failed,
                message: error.localizedDescription,
                durationSeconds: duration(since: inputArtifactCaptureStartedAt)
            ))
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }

        let netExtractionStartedAt = Date()
        let nets = NetExtractor().extract(from: schematic)
        stages.append(Stage(
            name: "net-extraction",
            status: nets.isEmpty ? .failed : .passed,
            message: "\(nets.count) nets",
            durationSeconds: duration(since: netExtractionStartedAt)
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

        let netlistGenerationStartedAt = Date()
        let baseNetlist = try NetlistGenerator().generate(
            from: schematic,
            title: configuration.title,
            testbench: configuration.testbench,
            processConfiguration: configuration.processConfiguration
        )
        let preLayoutNetlistURL = runDirectory.appending(path: "pre-layout.cir")
        try write(baseNetlist, to: preLayoutNetlistURL)
        artifacts.append(try artifact(kind: "pre-layout-netlist", url: preLayoutNetlistURL, runDirectory: runDirectory))
        stages.append(Stage(
            name: "netlist-generation",
            status: .passed,
            durationSeconds: duration(since: netlistGenerationStartedAt)
        ))

        let preLayoutResult: SimulationResult
        let preLayoutSimulationStartedAt = Date()
        do {
            preLayoutResult = try await SimulationService().runSPICE(
                source: baseNetlist,
                fileName: "\(configuration.runID)-pre.cir",
                processConfiguration: configuration.processConfiguration
            )
        } catch {
            stages.append(Stage(
                name: "pre-layout-simulation",
                status: .failed,
                message: error.localizedDescription,
                durationSeconds: duration(since: preLayoutSimulationStartedAt)
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
            message: preLayoutResult.status.rawValue,
            durationSeconds: duration(since: preLayoutSimulationStartedAt)
        ))
        do {
            try await persistSimulationArtifacts(
                preLayoutResult,
                prefix: "pre-layout",
                runDirectory: runDirectory,
                artifacts: &artifacts
            )
        } catch {
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }
        guard preLayoutResult.status == .completed else {
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: StudioError.simulationFailure("Pre-layout simulation did not complete.")
            )
        }

        let layoutOutput: CircuitLayoutSynthesisOutput
        let layoutSynthesisStartedAt = Date()
        do {
            layoutOutput = try CircuitLayoutSynthesizer(
                layoutEngineCatalog: layoutEngineCatalog
            ).generate(
                from: schematic,
                catalog: configuration.catalog,
                tech: configuration.layoutTech,
                placementStrategy: .optimized
            )
        } catch {
            stages.append(Stage(
                name: "auto-layout",
                status: .failed,
                message: error.localizedDescription,
                durationSeconds: duration(since: layoutSynthesisStartedAt)
            ))
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }
        let layoutSynthesisIssues = layoutSynthesisStageIssues(layoutOutput)
        stages.append(Stage(
            name: "auto-layout",
            status: layoutSynthesisIssues.isEmpty ? .passed : .failed,
            message: layoutSynthesisIssues.isEmpty ? nil : layoutSynthesisIssues.joined(separator: "; "),
            durationSeconds: duration(since: layoutSynthesisStartedAt)
        ))
        do {
            try persistLayoutSynthesisArtifacts(
                layoutOutput,
                runDirectory: runDirectory,
                artifacts: &artifacts
            )
        } catch {
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }
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
        let externalSignoffStartedAt = Date()
        do {
            externalSignoff = try await runExternalSignoffIfNeeded(
                configuration: configuration,
                runDirectory: runDirectory
            )
        } catch {
            stages.append(Stage(
                name: "external-signoff",
                status: .failed,
                message: error.localizedDescription,
                durationSeconds: duration(since: externalSignoffStartedAt)
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
                let reviewURL = ExternalSignoffReviewStore()
                    .reviewURL(forProjectAt: configuration.projectRoot)
                artifacts.append(contentsOf: try captureInputArtifacts(
                    paths: [reviewURL.path(percentEncoded: false)],
                    kind: "external-signoff-review",
                    runDirectory: runDirectory,
                    subdirectory: "signoff"
                ))
                stages.append(Stage(
                    name: "external-signoff",
                    status: externalSignoff.isReadyForPEX ? .passed : .failed,
                    message: externalSignoff.isReadyForPEX ? nil : "external signoff not ready",
                    durationSeconds: duration(since: externalSignoffStartedAt)
                ))
            } catch {
                stages.append(Stage(
                    name: "external-signoff",
                    status: .failed,
                    message: error.localizedDescription,
                    durationSeconds: duration(since: externalSignoffStartedAt)
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

        let prePEXVerificationStartedAt = Date()
        let verification = PhysicalVerificationService().runPrePEXVerification(
            schematic: schematic,
            layout: layoutOutput.document,
            tech: layoutOutput.tech,
            designUnit: layoutOutput.designUnit,
            catalog: configuration.catalog,
            externalSignoff: externalSignoff
        )
        reconcileLayoutSynthesisStage(stages: &stages, verification: verification)
        do {
            try persistPrePEXVerificationArtifact(
                verification,
                runDirectory: runDirectory,
                artifacts: &artifacts
            )
        } catch {
            stages.append(Stage(
                name: "pre-pex-verification",
                status: .failed,
                message: error.localizedDescription,
                durationSeconds: duration(since: prePEXVerificationStartedAt)
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
            name: "pre-pex-verification",
            status: verification.isReadyForPEX ? .passed : .failed,
            message: verification.isReadyForPEX ? nil : prePEXFailureMessage(verification),
            durationSeconds: duration(since: prePEXVerificationStartedAt)
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
        let pexInjectionStartedAt = Date()
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
            artifacts.append(try artifact(kind: "post-layout-netlist", url: postLayoutNetlistURL, runDirectory: runDirectory))
            stages.append(Stage(
                name: "pex-injection",
                status: configuration.pexIR.elements.isEmpty ? .failed : .passed,
                message: "\(configuration.pexIR.elements.count) parasitic elements",
                durationSeconds: duration(since: pexInjectionStartedAt)
            ))
        } catch {
            stages.append(Stage(
                name: "pex-injection",
                status: .failed,
                message: error.localizedDescription,
                durationSeconds: duration(since: pexInjectionStartedAt)
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
        let postLayoutSimulationStartedAt = Date()
        do {
            postLayoutResult = try await postLayoutService.runPostLayoutAnalysis(
                baseNetlist: baseNetlist,
                parasitics: configuration.pexIR,
                command: configuration.postLayoutCommand,
                processConfiguration: configuration.processConfiguration
            )
        } catch {
            stages.append(Stage(
                name: "post-layout-simulation",
                status: .failed,
                message: error.localizedDescription,
                durationSeconds: duration(since: postLayoutSimulationStartedAt)
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
            message: postLayoutResult.status.rawValue,
            durationSeconds: duration(since: postLayoutSimulationStartedAt)
        ))

        // Optional independent-oracle cross-check: run the SAME post-layout deck in
        // ngspice and record how far CoreSpice diverges. Opt-in (oracleProbes) and
        // only when ngspice is reachable — evidence when available, no silent
        // fallback when it is not.
        if let probes = configuration.oracleProbes, !probes.isEmpty,
           PostLayoutOracleService.ngspiceAvailable() {
            let oracleStartedAt = Date()
            do {
                let agreement = try await PostLayoutOracleService().crossCheck(
                    deck: postLayoutNetlist,
                    command: configuration.postLayoutCommand,
                    probes: probes
                )
                stages.append(Stage(
                    name: "post-layout-oracle",
                    status: agreement.consistent ? .passed : .failed,
                    message: String(
                        format: "CoreSpice vs ngspice max ΔV = %.4f V (tol %.3f)",
                        agreement.maxDivergenceV, agreement.toleranceV
                    ),
                    durationSeconds: duration(since: oracleStartedAt)
                ))
            } catch {
                stages.append(Stage(
                    name: "post-layout-oracle",
                    status: .failed,
                    message: "oracle cross-check error: \(error.localizedDescription)",
                    durationSeconds: duration(since: oracleStartedAt)
                ))
            }
        }
        do {
            try await persistSimulationArtifacts(
                postLayoutResult,
                prefix: "post-layout",
                runDirectory: runDirectory,
                artifacts: &artifacts
            )
        } catch {
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verification.isReadyForPEX,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }
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

        let postLayoutComparisonStartedAt = Date()
        let comparisonReport = PostLayoutComparisonService().compare(
            preLayoutResult: preLayoutResult,
            postLayoutResult: postLayoutResult,
            limits: configuration.postLayoutComparisonLimits
        )
        let comparisonReportURL = runDirectory.appending(path: "post-layout-comparison.json")
        do {
            try writeJSON(comparisonReport, to: comparisonReportURL)
            artifacts.append(try artifact(
                kind: "post-layout-comparison",
                url: comparisonReportURL,
                runDirectory: runDirectory
            ))
        } catch {
            stages.append(Stage(
                name: "post-layout-comparison",
                status: .failed,
                message: error.localizedDescription,
                durationSeconds: duration(since: postLayoutComparisonStartedAt)
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
        let comparisonLimitsWereConfigured = configuration.postLayoutComparisonLimits != nil
        stages.append(Stage(
            name: "post-layout-comparison",
            status: comparisonReport.gateViolations.isEmpty ? .passed : .failed,
            message: comparisonStageMessage(
                report: comparisonReport,
                limitsWereConfigured: comparisonLimitsWereConfigured
            ),
            durationSeconds: duration(since: postLayoutComparisonStartedAt)
        ))
        guard comparisonReport.gateViolations.isEmpty else {
            try failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verification.isReadyForPEX,
                stages: &stages,
                artifacts: artifacts,
                error: StudioError.simulationFailure("Post-layout comparison exceeded configured limits.")
            )
        }

        let manifestURL = try writeManifest(
            configuration: configuration,
            runDirectory: runDirectory,
            isRoundTripComplete: true,
            isReadyForPEX: verification.isReadyForPEX,
            stages: stages,
            artifacts: artifacts
        )
        let manifest = try readManifest(from: manifestURL)
        try finalizeCanonicalRun(
            status: .succeeded,
            domainManifestURL: manifestURL,
            artifacts: artifacts,
            configuration: configuration
        )

        return Result(
            manifest: manifest,
            manifestURL: manifestURL,
            verification: verification,
            preLayoutResult: preLayoutResult,
            postLayoutResult: postLayoutResult,
            externalSignoff: externalSignoff
        )
    }

    private func validateComparisonLimits(_ limits: PostLayoutComparisonLimits?) throws {
        guard let limits else {
            return
        }
        let diagnostics = limits.validationDiagnostics()
        guard diagnostics.isEmpty else {
            throw StudioError.invalidDesign(diagnostics.joined(separator: "; "))
        }
    }

    public nonisolated static func validateRunID(_ runID: String) throws {
        let allowedScalars = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
        )
        let isValid = !runID.isEmpty
            && runID != "."
            && runID != ".."
            && runID.unicodeScalars.allSatisfy { allowedScalars.contains($0) }
        guard isValid else {
            throw StudioError.invalidDesign(
                "Invalid run ID: use only letters, numbers, '.', '_', or '-', and do not use '.' or '..'."
            )
        }
    }

    private func duration(since startedAt: Date) -> Double {
        max(0, Date().timeIntervalSince(startedAt))
    }

    private func comparisonStageMessage(
        report: PostLayoutComparisonReport,
        limitsWereConfigured: Bool
    ) -> String {
        if !report.gateViolations.isEmpty {
            return report.gateViolations.joined(separator: "; ")
        }
        return limitsWereConfigured ? report.gateStatus : report.status
    }

    private func bottleneckSummary(for stages: [Stage]) -> BottleneckSummary {
        let measuredStages = stages.compactMap { stage -> (Stage, Double)? in
            guard let duration = stage.durationSeconds else {
                return nil
            }
            return (stage, duration)
        }
        let totalDuration = measuredStages.reduce(0.0) { $0 + $1.1 }
        let longestStage = measuredStages.max { lhs, rhs in
            lhs.1 < rhs.1
        }
        let failedStage = stages.first { $0.status == .failed }
        return BottleneckSummary(
            totalMeasuredDurationSeconds: totalDuration,
            longestStageName: longestStage?.0.name,
            longestStageDurationSeconds: longestStage?.1,
            failedStageName: failedStage?.name,
            recommendations: bottleneckRecommendations(
                failedStageName: failedStage?.name,
                longestStageName: longestStage?.0.name
            )
        )
    }

    private func bottleneckRecommendations(
        failedStageName: String?,
        longestStageName: String?
    ) -> [String] {
        var recommendations: [String] = []
        if let failedStageName {
            recommendations.append(recommendation(for: failedStageName, reason: "failed"))
        }
        if let longestStageName, longestStageName != failedStageName {
            recommendations.append(recommendation(for: longestStageName, reason: "longest"))
        }
        return recommendations
    }

    private func recommendation(for stageName: String, reason: String) -> String {
        switch stageName {
        case "input-artifact-capture":
            return "\(reason): inspect configured design, signoff, and PEX artifact paths before the flow starts."
        case "net-extraction":
            return "\(reason): inspect schematic wires, labels, pins, and floating or missing nets."
        case "netlist-generation":
            return "\(reason): inspect schematic connectivity, device metadata, and SPICE generation coverage."
        case "pre-layout-simulation":
            return "\(reason): inspect generated SPICE, model includes, solver diagnostics, and analysis setup."
        case "auto-layout":
            return "\(reason): improve layout generation, routing constraints, and DRC-clean geometry coverage."
        case "external-signoff":
            return "\(reason): inspect external DRC/LVS logs, tool setup, approval state, and captured signoff artifacts."
        case "pre-pex-verification":
            return "\(reason): inspect DRC/LVS diagnostics, DesignUnit mappings, ports, labels, and physical connectivity."
        case "pex-injection":
            return "\(reason): inspect PEX IR completeness, captured PEX artifacts, units, and parasitic element validity."
        case "post-layout-simulation":
            return "\(reason): inspect extracted netlist, PEX element scale, solver diagnostics, and analysis command."
        case "post-layout-comparison":
            return "\(reason): inspect comparison sweep alignment, applied limits, and post-layout delta attribution."
        default:
            return "\(reason): inspect \(stageName) artifacts and diagnostics."
        }
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
        let manifestURL = try writeManifest(
            configuration: configuration,
            runDirectory: runDirectory,
            isRoundTripComplete: false,
            isReadyForPEX: isReadyForPEX,
            stages: stages,
            artifacts: artifacts
        )
        try finalizeCanonicalRun(
            status: .failed,
            domainManifestURL: manifestURL,
            artifacts: artifacts,
            configuration: configuration
        )
        throw error
    }

    private func markRunFailedIfNeeded(
        configuration: Configuration,
        runDirectory: URL,
        error: Error
    ) throws {
        let manifest = try runLedger.loadRunManifest(
            runID: configuration.runID,
            inProjectAt: configuration.projectRoot
        )
        guard manifest.status == .running else {
            return
        }
        let failureURL = runDirectory.appending(path: "headless-error.json")
        try writeJSON(
            UncaughtFailure(
                runID: configuration.runID,
                reason: error.localizedDescription,
                errorType: String(describing: type(of: error)),
                recordedAt: Date()
            ),
            to: failureURL
        )
        let hasher = XcircuiteHasher()
        let legacyFailureReference = XcircuiteFileReference(
            artifactID: "headless-error",
            path: "\(XcircuitePackage.directoryName)/runs/\(configuration.runID)/headless-error.json",
            kind: .report,
            format: .json,
            sha256: try hasher.sha256(fileAt: failureURL),
            byteCount: try hasher.byteCount(fileAt: failureURL),
            producedByRunID: configuration.runID
        )
        let failureReference = try foundationArtifactReference(from: legacyFailureReference)
        let integrity = LocalArtifactVerifier().verify(
            failureReference,
            relativeTo: configuration.projectRoot
        )
        guard integrity.isVerified else {
            throw StudioError.projectSaveFailed(
                "Headless failure artifact integrity failed: \(integrityMessage(integrity))"
            )
        }
        _ = try runLedger.transitionRun(
            runID: configuration.runID,
            transition: XcircuiteRunTransition(
                status: .failed,
                artifacts: [try FoundationArtifactTypeProjection.legacyReference(failureReference)]
            ),
            inProjectAt: configuration.projectRoot
        )
    }

    private struct UncaughtFailure: Sendable, Encodable {
        let schemaVersion = 1
        let runID: String
        let reason: String
        let errorType: String
        let recordedAt: Date
    }

    private func finalizeCanonicalRun(
        status: XcircuiteRunStatus,
        domainManifestURL: URL,
        artifacts: [Artifact],
        configuration: Configuration
    ) throws {
        let references = try canonicalArtifactReferences(
            domainManifestURL: domainManifestURL,
            artifacts: artifacts,
            configuration: configuration
        )
        _ = try runLedger.transitionRun(
            runID: configuration.runID,
            transition: XcircuiteRunTransition(status: status, artifacts: references),
            inProjectAt: configuration.projectRoot
        )
    }

    private func canonicalArtifactReferences(
        domainManifestURL: URL,
        artifacts: [Artifact],
        configuration: Configuration
    ) throws -> [XcircuiteFileReference] {
        let runPrefix = "\(XcircuitePackage.directoryName)/runs/\(configuration.runID)"
        var legacyReferences = artifacts.map { artifact in
            XcircuiteFileReference(
                artifactID: canonicalArtifactID(for: artifact),
                path: "\(runPrefix)/\(artifact.path)",
                kind: canonicalFileKind(for: artifact.kind),
                format: canonicalFileFormat(for: artifact.path),
                sha256: artifact.sha256,
                byteCount: artifact.byteCount,
                producedByRunID: configuration.runID
            )
        }
        let hasher = XcircuiteHasher()
        legacyReferences.append(XcircuiteFileReference(
            artifactID: "round-trip-manifest",
            path: "\(runPrefix)/round-trip-manifest.json",
            kind: .report,
            format: .json,
            sha256: try hasher.sha256(fileAt: domainManifestURL),
            byteCount: try hasher.byteCount(fileAt: domainManifestURL),
            producedByRunID: configuration.runID
        ))

        let references = try legacyReferences.map(foundationArtifactReference(from:))
        for reference in references {
            let integrity = LocalArtifactVerifier().verify(
                reference,
                relativeTo: configuration.projectRoot
            )
            guard integrity.isVerified else {
                throw StudioError.projectSaveFailed(
                    "Canonical run artifact integrity failed for \(reference.locator.location.value): \(integrityMessage(integrity))"
                )
            }
        }
        return try references.map(FoundationArtifactTypeProjection.legacyReference)
    }

    private func integrityMessage(_ integrity: ArtifactIntegrity) -> String {
        integrity.issues.map { issue in
            var message = issue.code.rawValue
            if let detail = issue.detail {
                message += ": \(detail)"
            }
            return message
        }.joined(separator: "; ")
    }

    private func foundationArtifactReference(
        from legacyReference: XcircuiteFileReference
    ) throws -> CircuiteFoundation.ArtifactReference {
        guard let reference = FoundationArtifactTypeProjection.reference(legacyReference) else {
            throw StudioError.projectSaveFailed(
                "Unable to project legacy artifact into Foundation: \(legacyReference.path)"
            )
        }
        return reference
    }

    private func canonicalArtifactID(for artifact: Artifact) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitizedKind = String(artifact.kind.unicodeScalars.map {
            allowed.contains($0) ? Character(String($0)) : "-"
        })
        let kind = sanitizedKind.isEmpty ? "headless-artifact" : sanitizedKind
        let pathDigest = XcircuiteHasher()
            .sha256(data: Data(artifact.path.utf8))
            .prefix(12)
        return "\(kind)-\(pathDigest)"
    }

    private func canonicalFileKind(for kind: String) -> XcircuiteFileKind {
        if kind.contains("netlist") {
            return .netlist
        }
        if kind.contains("waveform") {
            return .waveform
        }
        if kind.contains("pex") || kind.contains("parasitic") {
            return .parasitic
        }
        if kind.contains("layout") || kind == "design-unit" {
            return .layout
        }
        if kind.contains("report")
            || kind.contains("verification")
            || kind.contains("signoff")
            || kind.contains("comparison") {
            return .report
        }
        return .other
    }

    private func canonicalFileFormat(for path: String) -> XcircuiteFileFormat {
        switch URL(filePath: path).pathExtension.lowercased() {
        case "cir", "sp", "spice", "net": return .spice
        case "gds", "gdsii": return .gdsii
        case "oas", "oasis": return .oasis
        case "lef": return .lef
        case "def": return .def
        case "spef": return .spef
        case "json": return .json
        case "raw": return .raw
        case "csv": return .csv
        case "txt", "log", "rpt", "md": return .text
        default: return .unknown
        }
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

    private func layoutSynthesisStageIssues(_ output: CircuitLayoutSynthesisOutput) -> [String] {
        var issues: [String] = []
        if !output.unroutedNets.isEmpty {
            issues.append("Unrouted nets: \(output.unroutedNets.joined(separator: ", "))")
        }
        // Same violation scope as the pre-PEX DRC verdict: annotation-based
        // connectivity opens are judged by extraction-based LVS instead.
        let violations = PhysicalVerificationService.physicalRuleViolations(in: output.drcResult)
        if !violations.isEmpty {
            issues.append("DRC violations: \(violations.count)")
        }
        return issues
    }

    private func reconcileLayoutSynthesisStage(
        stages: inout [Stage],
        verification: PhysicalVerificationReport
    ) {
        guard let index = stages.lastIndex(where: { $0.name == "auto-layout" }) else {
            return
        }
        let stage = stages[index]
        guard stage.status == .passed else {
            return
        }
        guard !verification.drc.passed || !verification.lvs.passed else {
            return
        }

        var issues: [String] = []
        if !verification.drc.passed {
            issues.append("DRC violations: \(verification.drc.violationCount)")
        }
        if !verification.lvs.passed {
            let missingInstances = verification.lvs.missingLayoutInstances.count
            let missingNets = verification.lvs.missingLayoutNets.count
            issues.append("LVS mismatches: \(missingInstances) missing instances, \(missingNets) missing nets")
        }
        stages[index] = Stage(
            name: stage.name,
            status: .failed,
            message: "Generated layout failed physical verification: \(issues.joined(separator: "; "))",
            durationSeconds: stage.durationSeconds
        )
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
            artifacts: artifacts,
            bottleneckSummary: bottleneckSummary(for: stages)
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
    ) async throws -> ExternalSignoffReview? {
        let store = ExternalSignoffReviewStore()
        if var review = configuration.externalSignoffReview {
            try store.save(review, forProjectAt: configuration.projectRoot)
            if let approvedBy = configuration.approvedBy,
               let approvedAt = configuration.approvedAt {
                review = review.approving(
                    by: approvedBy,
                    at: approvedAt,
                    approvalKind: configuration.approvalKind ?? .human,
                    waiverIDs: configuration.waiverIDs
                )
                try store.save(review, forProjectAt: configuration.projectRoot)
            }
            return review
        }

        guard !configuration.externalSignoffCommands.isEmpty else {
            return nil
        }

        let artifactDirectory = runDirectory.appending(path: "external-signoff")
        let adapter = try SignoffAdapterFactory().commandAdapter()
        var review = try await adapter.run(request: SignoffAdapterRequest(
            commands: configuration.externalSignoffCommands,
            artifactDirectory: artifactDirectory
        ))
        try store.save(review, forProjectAt: configuration.projectRoot)

        if let approvedBy = configuration.approvedBy,
           let approvedAt = configuration.approvedAt {
            review = try store.approve(
                forProjectAt: configuration.projectRoot,
                approvedBy: approvedBy,
                approvedAt: approvedAt,
                approvalKind: configuration.approvalKind ?? .human,
                waiverIDs: configuration.waiverIDs
            )
        }

        return review
    }

    private func persistSimulationArtifacts(
        _ result: SimulationResult,
        prefix: String,
        runDirectory: URL,
        artifacts: inout [Artifact]
    ) async throws {
        let summaryURL = runDirectory.appending(path: "\(prefix)-simulation.json")
        try writeJSON(SimulationArtifactSummary(result: result), to: summaryURL)
        artifacts.append(try artifact(kind: "\(prefix)-simulation-report", url: summaryURL, runDirectory: runDirectory))

        guard let waveform = result.waveform else {
            return
        }
        let waveformURL = runDirectory.appending(path: "\(prefix)-waveform.csv")
        try await WaveformService().export(waveform: waveform, to: waveformURL)
        artifacts.append(try artifact(kind: "\(prefix)-waveform", url: waveformURL, runDirectory: runDirectory))
    }

    private func persistLayoutSynthesisArtifacts(
        _ output: CircuitLayoutSynthesisOutput,
        runDirectory: URL,
        artifacts: inout [Artifact]
    ) throws {
        let layoutURL = runDirectory.appending(path: "layout-document.json")
        let designUnitURL = runDirectory.appending(path: "design-unit.json")
        try writeJSON(output.document, to: layoutURL)
        try writeJSON(output.designUnit, to: designUnitURL)
        artifacts.append(try artifact(kind: "layout-document", url: layoutURL, runDirectory: runDirectory))
        artifacts.append(try artifact(kind: "design-unit", url: designUnitURL, runDirectory: runDirectory))
    }

    private func persistPrePEXVerificationArtifact(
        _ report: PhysicalVerificationReport,
        runDirectory: URL,
        artifacts: inout [Artifact]
    ) throws {
        let reportURL = runDirectory.appending(path: "physical-verification.json")
        try writeJSON(DesignFlowVerificationReport(report: report), to: reportURL)
        artifacts.append(try artifact(kind: "physical-verification-report", url: reportURL, runDirectory: runDirectory))
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
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: sourcePath, isDirectory: &isDirectory) else {
                throw StudioError.projectLoadFailed("Input artifact not found: \(sourcePath)")
            }
            guard !isDirectory.boolValue else {
                throw StudioError.projectLoadFailed("Input artifact must be a regular file: \(sourcePath)")
            }

            if isArtifactAlreadyInsideRunDirectory(sourceURL: sourceURL, runDirectory: runDirectory) {
                return try artifact(kind: kind, url: sourceURL, runDirectory: runDirectory)
            }

            let resolvedSourceURL = sourceURL.resolvingSymlinksInPath()
            let resolvedSourcePath = resolvedSourceURL.path(percentEncoded: false)
            var resolvedIsDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: resolvedSourcePath, isDirectory: &resolvedIsDirectory) else {
                throw StudioError.projectLoadFailed("Input artifact not found: \(sourcePath)")
            }
            guard !resolvedIsDirectory.boolValue else {
                throw StudioError.projectLoadFailed("Input artifact must be a regular file: \(sourcePath)")
            }
            let destinationURL = uniqueCaptureURL(
                for: sourceURL,
                in: captureDirectory,
                usedNames: &usedNames
            )
            do {
                try FileManager.default.copyItem(at: resolvedSourceURL, to: destinationURL)
            } catch {
                throw StudioError.projectSaveFailed(
                    "Failed to capture input artifact \(sourcePath): \(error.localizedDescription)"
                )
            }

            return try artifact(
                kind: kind,
                url: destinationURL,
                runDirectory: runDirectory,
                sourcePath: sourcePath
            )
        }
    }

    private func artifact(
        kind: String,
        url: URL,
        runDirectory: URL,
        sourcePath: String? = nil
    ) throws -> Artifact {
        let digest = try RoundTripArtifactDigest.compute(url: url)
        return Artifact(
            kind: kind,
            path: try RoundTripArtifactResolver(
                runDirectory: runDirectory
            ).relativePath(for: url),
            sourcePath: sourcePath,
            sha256: digest.sha256,
            byteCount: digest.byteCount
        )
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

    private func isArtifactAlreadyInsideRunDirectory(sourceURL: URL, runDirectory: URL) -> Bool {
        do {
            _ = try RoundTripArtifactResolver(
                runDirectory: runDirectory
            ).relativePath(for: sourceURL)
            return true
        } catch {
            return false
        }
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

    private struct SimulationArtifactSummary: Sendable, Encodable {
        let id: UUID
        let experimentID: UUID
        let status: RunStatus
        let startedAt: Date
        let finishedAt: Date?
        let waveform: WaveformSummary?
        let logMessages: [String]

        init(result: SimulationResult) {
            self.id = result.id
            self.experimentID = result.experimentID
            self.status = result.status
            self.startedAt = result.startedAt
            self.finishedAt = result.finishedAt
            self.waveform = result.waveform.map(WaveformSummary.init)
            self.logMessages = result.logMessages
        }
    }

    private struct WaveformSummary: Sendable, Encodable {
        let metadata: SimulationMetadata
        let sweepVariable: VariableDescriptor
        let pointCount: Int
        let variableCount: Int
        let isComplex: Bool
        let variables: [VariableDescriptor]

        init(waveform: WaveformData) {
            self.metadata = waveform.metadata
            self.sweepVariable = waveform.sweepVariable
            self.pointCount = waveform.pointCount
            self.variableCount = waveform.variableCount
            self.isComplex = waveform.isComplex
            self.variables = waveform.variables
        }
    }
}
