import CircuitSignoff
import Foundation
import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFileSystem
import CircuiteFoundationFoundation
import CircuitStudioCore
import CircuitPhysicalDesign
import CoreSpiceWaveform
import LayoutCore
import LayoutTech
import LayoutEngine
import DesignFlowKernel
import Xcircuite

@MainActor
public final class HeadlessRoundTripService {
    private static let orderedStageNames = [
        "input-artifact-capture",
        "net-extraction",
        "netlist-generation",
        "pre-layout-simulation",
        "auto-layout",
        "layout-trust",
        "external-signoff",
        "pre-pex-verification",
        "pex-injection",
        "post-layout-simulation",
        "post-layout-oracle",
        "post-layout-comparison",
    ]

    private let layoutEngineCatalog: any LayoutEngineCataloging
    private let workspaceStoreFactory: @Sendable (URL) throws -> XcircuiteWorkspaceStore
    private let signoffCommandRunner: any SignoffCommandRunning
    private let postLayoutOracle: any PostLayoutOracleChecking
    private let layoutTrustEvaluator: any LayoutTrustEvaluating
    private let layoutTrustArtifactWriter: any LayoutTrustArtifactWriting

    public init(
        layoutEngineCatalog: any LayoutEngineCataloging = CircuitPhysicalDesignDefaults.layoutEngineCatalog(),
        signoffCommandRunner: any SignoffCommandRunning = ExternalSignoffCommandRunner(),
        postLayoutOracle: any PostLayoutOracleChecking = PostLayoutOracleService(),
        layoutTrustEvaluator: any LayoutTrustEvaluating = LayoutTrustEvaluationService(),
        layoutTrustArtifactWriter: any LayoutTrustArtifactWriting = LayoutTrustArtifactWriter(),
        workspaceStoreFactory: @escaping @Sendable (URL) throws -> XcircuiteWorkspaceStore = {
            try XcircuiteWorkspaceStore(projectRoot: $0)
        }
    ) {
        self.layoutEngineCatalog = layoutEngineCatalog
        self.signoffCommandRunner = signoffCommandRunner
        self.postLayoutOracle = postLayoutOracle
        self.layoutTrustEvaluator = layoutTrustEvaluator
        self.layoutTrustArtifactWriter = layoutTrustArtifactWriter
        self.workspaceStoreFactory = workspaceStoreFactory
    }

    public func run(
        schematic: SchematicDocument,
        configuration: Configuration
    ) async throws -> Result {
        try Self.validateRunID(configuration.runID)
        try validateComparisonLimits(configuration.postLayoutComparisonLimits)

        let projectService = ProjectService()
        if !projectService.isProject(configuration.projectRoot) {
            try await projectService.createProject(at: configuration.projectRoot)
        }

        let ledgerStore = try workspaceStoreFactory(configuration.projectRoot)
        try await ledgerStore.ensureWorkspace()
        let runDirectory = try await ledgerStore.url(
            for: ".xcircuite/runs/\(configuration.runID)"
        )
        let initialManifest = try FlowRunManifest(
            runID: configuration.runID,
            status: .created,
            actor: configuration.actor,
            intent: configuration.title,
            createdAt: configuration.createdAt,
            updatedAt: configuration.createdAt
        )
        let initialLedger = FlowRunLedger(
            runID: configuration.runID,
            runManifest: initialManifest,
            stages: []
        )
        let coordinator = FlowRunLedgerCoordinator(persistence: ledgerStore)
        _ = try await coordinator.create(initialLedger)
        _ = try await coordinator.transition(
            runID: configuration.runID,
            to: .running,
            at: configuration.createdAt
        )

        do {
            return try await executeRun(
                schematic: schematic,
                configuration: configuration,
                runDirectory: runDirectory
            )
        } catch {
            do {
                try await markRunFailedIfNeeded(
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
        do {
            return try await executeRunSteps(
                schematic: schematic,
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: &artifacts
            )
        } catch {
            let store = try workspaceStoreFactory(configuration.projectRoot)
            let ledger = try await store.loadRunLedger(runID: configuration.runID)
            guard ledger.runManifest.status == .running else {
                throw error
            }
            if !stages.contains(where: { $0.status == .failed }) {
                stages.append(Stage(
                    name: "headless-run",
                    status: .failed,
                    message: error.localizedDescription
                ))
            }
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }
    }

    private func executeRunSteps(
        schematic: SchematicDocument,
        configuration: Configuration,
        runDirectory: URL,
        stages: inout [Stage],
        artifacts: inout [Artifact]
    ) async throws -> Result {
        if let probes = configuration.oracleProbes, probes.isEmpty {
            let error = PostLayoutOracleService.OracleError.noProbes
            let failureURL = runDirectory.appending(
                path: "headless-configuration-error.json"
            )
            try writeJSON(
                UncaughtFailure(
                    runID: configuration.runID,
                    reason: error.localizedDescription,
                    errorType: String(describing: type(of: error)),
                    recordedAt: configuration.createdAt
                ),
                to: failureURL
            )
            artifacts.append(try artifact(
                kind: "configuration-error-report",
                url: failureURL,
                runDirectory: runDirectory
            ))
            stages.append(contentsOf: Self.orderedStageNames
                .prefix { $0 != "post-layout-oracle" }
                .map { name in
                    Stage(
                        name: name,
                        status: .skipped,
                        message: "not executed because oracle probe configuration is invalid"
                    )
                })
            stages.append(Stage(
                name: "post-layout-oracle",
                status: .failed,
                message: error.localizedDescription
            ))
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }
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
            try await failRun(
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
            try await failRun(
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
            try await failRun(
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
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }
        guard preLayoutResult.status == .completed else {
            try await failRun(
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
            try await failRun(
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
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }
        guard layoutOutput.unroutedNets.isEmpty else {
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: StudioError.invalidDesign("Auto layout left unrouted nets.")
            )
        }

        let layoutTrustStartedAt = Date()
        let layoutTrustReport: LayoutTrustReport
        do {
            layoutTrustReport = try layoutTrustEvaluator.evaluate(
                document: layoutOutput.document,
                tech: layoutOutput.tech,
                policy: LayoutOwnershipPolicy()
            )
            let published = try layoutTrustArtifactWriter.write(
                document: layoutOutput.document,
                report: layoutTrustReport,
                to: runDirectory.appending(path: "layout-trust")
            )
            artifacts.append(contentsOf: try layoutTrustArtifacts(
                published,
                runDirectory: runDirectory
            ))
            stages.append(Stage(
                name: "layout-trust",
                status: layoutTrustReport.passed ? .passed : .failed,
                message: layoutTrustReport.passed ? nil : layoutTrustReport.summary,
                durationSeconds: duration(since: layoutTrustStartedAt)
            ))
        } catch {
            stages.append(Stage(
                name: "layout-trust",
                status: .failed,
                message: error.localizedDescription,
                durationSeconds: duration(since: layoutTrustStartedAt)
            ))
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }
        guard layoutTrustReport.passed else {
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: StudioError.invalidDesign(layoutTrustReport.summary)
            )
        }

        let externalSignoffExecution: (
            review: ExternalSignoffReview,
            supportingTools: [ProducerIdentity],
            results: [ExternalSignoffCommandResult],
            evidenceURL: URL?,
            artifactRole: ArtifactRole
        )?
        let externalSignoffStartedAt = Date()
        do {
            externalSignoffExecution = try await runExternalSignoffIfNeeded(
                configuration: configuration,
                runDirectory: runDirectory
            )
        } catch let error as ExternalSignoffBatchError {
            let completedTools = error.completedResults.map(\.provenance.producer)
            let failedTools = error.failedProducer.map { [$0] } ?? []
            do {
                artifacts.append(contentsOf: try captureExternalSignoffExecutionArtifacts(
                    reports: error.completedResults.map(\.report),
                    results: error.completedResults,
                    evidenceURL: error.evidenceURL,
                    role: .output,
                    runDirectory: runDirectory
                ))
            } catch {
                stages.append(Stage(
                    name: "external-signoff",
                    status: .failed,
                    message: error.localizedDescription,
                    durationSeconds: duration(since: externalSignoffStartedAt)
                ))
                try await failRun(
                    configuration: configuration,
                    runDirectory: runDirectory,
                    stages: &stages,
                    artifacts: artifacts,
                    externallyExecutedTools: completedTools + failedTools,
                    error: error
                )
            }
            stages.append(Stage(
                name: "external-signoff",
                status: .failed,
                message: error.localizedDescription,
                durationSeconds: duration(since: externalSignoffStartedAt)
            ))
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                externallyExecutedTools: completedTools + failedTools,
                error: error
            )
        } catch {
            stages.append(Stage(
                name: "external-signoff",
                status: .failed,
                message: error.localizedDescription,
                durationSeconds: duration(since: externalSignoffStartedAt)
            ))
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                stages: &stages,
                artifacts: artifacts,
                error: error
            )
        }
        let externalSignoff = externalSignoffExecution?.review
        let externalSignoffSupportingTools = externalSignoffExecution?.supportingTools ?? []
        if let externalSignoff {
            do {
                artifacts.append(contentsOf: try captureExternalSignoffExecutionArtifacts(
                    reports: externalSignoff.reports,
                    results: externalSignoffExecution?.results ?? [],
                    evidenceURL: externalSignoffExecution?.evidenceURL,
                    role: externalSignoffExecution?.artifactRole ?? .output,
                    runDirectory: runDirectory
                ))
                let reviewURL = ExternalSignoffReviewStore()
                    .reviewURL(forProjectAt: configuration.projectRoot)
                let reviewArtifacts = if externalSignoffExecution?.artifactRole == .input {
                    try captureInputArtifacts(
                        paths: [reviewURL.path(percentEncoded: false)],
                        kind: "external-signoff-review",
                        runDirectory: runDirectory,
                        subdirectory: "signoff"
                    )
                } else {
                    try captureGeneratedArtifacts(
                        paths: [reviewURL.path(percentEncoded: false)],
                        kind: "external-signoff-review",
                        runDirectory: runDirectory,
                        subdirectory: "signoff"
                    )
                }
                artifacts.append(contentsOf: reviewArtifacts)
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
                try await failRun(
                    configuration: configuration,
                    runDirectory: runDirectory,
                    stages: &stages,
                    artifacts: artifacts,
                    externallyExecutedTools: externalSignoffSupportingTools,
                    error: error
                )
            }
        } else {
            stages.append(Stage(
                name: "external-signoff",
                status: .failed,
                message: "retained external DRC/LVS signoff evidence is required",
                durationSeconds: duration(since: externalSignoffStartedAt)
            ))
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
        let verificationReport = DesignFlowVerificationReport(
            report: verification,
            layoutTrust: layoutTrustReport
        )
        reconcileLayoutSynthesisStage(stages: &stages, verification: verification)
        do {
            try persistPrePEXVerificationArtifact(
                verificationReport,
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
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verificationReport.readyForPEX,
                stages: &stages,
                artifacts: artifacts,
                externallyExecutedTools: externalSignoffSupportingTools,
                error: error
            )
        }
        stages.append(Stage(
            name: "pre-pex-verification",
            status: verificationReport.readyForPEX ? .passed : .failed,
            message: verificationReport.readyForPEX ? nil : prePEXFailureMessage(verification),
            durationSeconds: duration(since: prePEXVerificationStartedAt)
        ))
        if !verificationReport.readyForPEX {
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verificationReport.readyForPEX,
                stages: &stages,
                artifacts: artifacts,
                externallyExecutedTools: externalSignoffSupportingTools,
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
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verificationReport.readyForPEX,
                stages: &stages,
                artifacts: artifacts,
                externallyExecutedTools: externalSignoffSupportingTools,
                error: error
            )
        }
        guard !configuration.pexIR.elements.isEmpty else {
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verificationReport.readyForPEX,
                stages: &stages,
                artifacts: artifacts,
                externallyExecutedTools: externalSignoffSupportingTools,
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
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verificationReport.readyForPEX,
                stages: &stages,
                artifacts: artifacts,
                externallyExecutedTools: externalSignoffSupportingTools,
                error: error
            )
        }
        stages.append(Stage(
            name: "post-layout-simulation",
            status: postLayoutResult.status == .completed ? .passed : .failed,
            message: postLayoutResult.status.rawValue,
            durationSeconds: duration(since: postLayoutSimulationStartedAt)
        ))
        do {
            try await persistSimulationArtifacts(
                postLayoutResult,
                prefix: "post-layout",
                runDirectory: runDirectory,
                artifacts: &artifacts
            )
        } catch {
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verificationReport.readyForPEX,
                stages: &stages,
                artifacts: artifacts,
                externallyExecutedTools: externalSignoffSupportingTools,
                error: error
            )
        }
        guard postLayoutResult.status == .completed else {
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verificationReport.readyForPEX,
                stages: &stages,
                artifacts: artifacts,
                externallyExecutedTools: externalSignoffSupportingTools,
                error: StudioError.simulationFailure("Post-layout simulation did not complete.")
            )
        }

        // An explicitly requested independent-oracle cross-check is a required gate.
        // Omitting oracleProbes keeps the normal local flow independent of ngspice.
        if let probes = configuration.oracleProbes {
            let oracleStartedAt = Date()
            guard postLayoutOracle.isAvailable else {
                let error = StudioError.simulationFailure(
                    "The requested post-layout oracle is unavailable."
                )
                stages.append(Stage(
                    name: "post-layout-oracle",
                    status: .failed,
                    message: error.localizedDescription,
                    durationSeconds: duration(since: oracleStartedAt)
                ))
                try await failRun(
                    configuration: configuration,
                    runDirectory: runDirectory,
                    isReadyForPEX: verificationReport.readyForPEX,
                    stages: &stages,
                    artifacts: artifacts,
                    externallyExecutedTools: externalSignoffSupportingTools,
                    error: error
                )
            }
            let agreement: PostLayoutOracleAgreement
            do {
                agreement = try await postLayoutOracle.crossCheck(
                    deck: postLayoutNetlist,
                    command: configuration.postLayoutCommand,
                    probes: probes,
                    toleranceV: 0.1
                )
                let agreementURL = runDirectory.appending(
                    path: "post-layout-oracle-agreement.json"
                )
                try writeJSON(agreement, to: agreementURL)
                artifacts.append(try artifact(
                    kind: "post-layout-oracle-report",
                    url: agreementURL,
                    runDirectory: runDirectory
                ))
            } catch {
                stages.append(Stage(
                    name: "post-layout-oracle",
                    status: .failed,
                    message: "oracle cross-check error: \(error.localizedDescription)",
                    durationSeconds: duration(since: oracleStartedAt)
                ))
                try await failRun(
                    configuration: configuration,
                    runDirectory: runDirectory,
                    isReadyForPEX: verificationReport.readyForPEX,
                    stages: &stages,
                    artifacts: artifacts,
                    externallyExecutedTools: externalSignoffSupportingTools,
                    error: error
                )
            }
            let oracleMessage = String(
                format: "CoreSpice vs ngspice max ΔV = %.4f V (tol %.3f)",
                agreement.maxDivergenceV,
                agreement.toleranceV
            )
            stages.append(Stage(
                name: "post-layout-oracle",
                status: agreement.isConsistent ? .passed : .failed,
                message: oracleMessage,
                durationSeconds: duration(since: oracleStartedAt)
            ))
            guard agreement.isConsistent else {
                try await failRun(
                    configuration: configuration,
                    runDirectory: runDirectory,
                    isReadyForPEX: verificationReport.readyForPEX,
                    stages: &stages,
                    artifacts: artifacts,
                    externallyExecutedTools: externalSignoffSupportingTools,
                    error: StudioError.simulationFailure(oracleMessage)
                )
            }
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
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verificationReport.readyForPEX,
                stages: &stages,
                artifacts: artifacts,
                externallyExecutedTools: externalSignoffSupportingTools,
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
            try await failRun(
                configuration: configuration,
                runDirectory: runDirectory,
                isReadyForPEX: verificationReport.readyForPEX,
                stages: &stages,
                artifacts: artifacts,
                externallyExecutedTools: externalSignoffSupportingTools,
                error: StudioError.simulationFailure("Post-layout comparison exceeded configured limits.")
            )
        }

        let isRoundTripComplete = stages.allSatisfy { $0.status == .passed }
        let canonicalRunStatus: FlowRunStatus = if stages.contains(where: { $0.status == .failed }) {
            .failed
        } else if isRoundTripComplete {
            .succeeded
        } else {
            .partial
        }
        let manifestURL = try writeManifest(
            configuration: configuration,
            runDirectory: runDirectory,
            isRoundTripComplete: isRoundTripComplete,
            isReadyForPEX: verificationReport.readyForPEX,
            stages: stages,
            artifacts: artifacts
        )
        let manifest = try readManifest(from: manifestURL)
        try await finalizeCanonicalRun(
            status: canonicalRunStatus,
            domainManifestURL: manifestURL,
            stages: stages,
            artifacts: artifacts,
            configuration: configuration,
            externallyExecutedTools: externalSignoffSupportingTools
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
        report: CircuitStudioCore.PostLayoutComparisonReport,
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
        case "post-layout-oracle":
            return "\(reason): inspect independent-oracle availability, probe coverage, tolerance, and retained agreement evidence."
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
        externallyExecutedTools: [ProducerIdentity] = [],
        error: Error
    ) async throws -> Never {
        stages.append(contentsOf: skippedStages(after: stages))
        let manifestURL = try writeManifest(
            configuration: configuration,
            runDirectory: runDirectory,
            isRoundTripComplete: false,
            isReadyForPEX: isReadyForPEX,
            stages: stages,
            artifacts: artifacts
        )
        try await finalizeCanonicalRun(
            status: .failed,
            domainManifestURL: manifestURL,
            stages: stages,
            artifacts: artifacts,
            configuration: configuration,
            externallyExecutedTools: externallyExecutedTools
        )
        throw error
    }

    private func markRunFailedIfNeeded(
        configuration: Configuration,
        runDirectory: URL,
        error: Error
    ) async throws {
        let ledgerStore = try workspaceStoreFactory(configuration.projectRoot)
        let coordinator = FlowRunLedgerCoordinator(persistence: ledgerStore)
        let ledger = try await coordinator.load(
            runID: configuration.runID
        )
        guard ledger.runManifest.status == .running else {
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
        let failureBinding = try artifactBinding(
            logicalID: "headless-error",
            path: "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(configuration.runID)/headless-error.json",
            kind: .report,
            format: .json,
            projectRoot: configuration.projectRoot
        )
        let integrity = LocalArtifactVerifier().verify(
            failureBinding.reference,
            at: try artifactLocator(for: failureBinding),
            relativeTo: configuration.projectRoot
        )
        guard integrity.isVerified else {
            throw StudioError.projectSaveFailed(
                "Headless failure artifact integrity failed: \(integrityMessage(integrity))"
            )
        }
        let diagnostic = FlowDiagnostic(
            severity: .error,
            code: "HEADLESS_RUN_FAILED",
            message: error.localizedDescription
        )
        let failureStage = FlowStageResult(
            stageID: "headless-run",
            status: .failed,
            diagnostics: [diagnostic],
            gates: [
                FlowGateResult(
                    gateID: "headless-run",
                    status: .failed,
                    diagnostics: [diagnostic]
                ),
            ],
            artifacts: [failureBinding]
        )
        let producer = try await CircuitStudioExecutionEnvironment.producerIdentity(
            kind: .engine,
            identifier: "circuit-studio-headless"
        )
        let recordedAt = Date()
        let provenance = try ExecutionProvenance(
            producer: producer,
            inputs: ledger.artifacts.filter { $0.role == .input }.map(\.reference),
            invocation: try .inProcess(entryPoint: "HeadlessRoundTripService.run"),
            environment: try await CircuitStudioExecutionEnvironment.current(),
            startedAt: configuration.createdAt,
            completedAt: recordedAt
        )
        let artifacts = ledger.artifacts + [failureBinding]
        let finalStages = ledger.stages + [failureStage]
        var existingToolchainStages: [String: FlowToolchainStageRecord] = [:]
        for record in ledger.toolchain?.stages ?? [] {
            guard existingToolchainStages.updateValue(record, forKey: record.stageID) == nil else {
                throw StudioError.projectLoadFailed(
                    "Canonical run toolchain contains duplicate stage ID '\(record.stageID)'."
                )
            }
        }
        let toolchain = FlowToolchainManifest(
            runID: configuration.runID,
            profile: ledger.toolchain?.profile,
            stages: finalStages.map { stage in
                existingToolchainStages[stage.stageID] ?? FlowToolchainStageRecord(
                    stageID: stage.stageID,
                    executorToolID: canonicalExecutorToolID(forStage: stage.stageID)
                )
            }
        )
        _ = try await coordinator.finalize(
            runID: configuration.runID,
            status: .failed,
            stages: finalStages,
            toolchain: toolchain,
            evidence: try EvidenceManifest.contentAddressed(
                provenance: provenance,
                artifacts: artifacts.map(\.reference),
                digester: SHA256ContentDigester()
            ),
            artifacts: artifacts,
            at: recordedAt
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
        status: FlowRunStatus,
        domainManifestURL: URL,
        stages: [Stage],
        artifacts: [Artifact],
        configuration: Configuration,
        externallyExecutedTools: [ProducerIdentity] = []
    ) async throws {
        let bindings = try canonicalArtifactBindings(
            domainManifestURL: domainManifestURL,
            artifacts: artifacts,
            configuration: configuration
        )
        let stageResults = stages.map {
            canonicalStageResult(
                $0,
                domainArtifacts: artifacts,
                canonicalBindings: bindings
            )
        }
        let toolchain = canonicalToolchainManifest(
            runID: configuration.runID,
            stages: stages
        )
        let producer = try await CircuitStudioExecutionEnvironment.producerIdentity(
            kind: .engine,
            identifier: "circuit-studio-headless"
        )
        let provenance = try ExecutionProvenance(
            producer: producer,
            supportingTools: try await canonicalSupportingTools(
                externallyExecutedTools: externallyExecutedTools
            ),
            inputs: bindings.filter { $0.role == .input }.map(\.reference),
            invocation: try .inProcess(entryPoint: "HeadlessRoundTripService.run"),
            environment: try await CircuitStudioExecutionEnvironment.current(),
            startedAt: configuration.createdAt,
            completedAt: Date()
        )
        let ledgerStore = try workspaceStoreFactory(configuration.projectRoot)
        _ = try await FlowRunLedgerCoordinator(persistence: ledgerStore).finalize(
            runID: configuration.runID,
            status: status,
            stages: stageResults,
            toolchain: toolchain,
            evidence: try EvidenceManifest.contentAddressed(
                provenance: provenance,
                artifacts: bindings.map(\.reference),
                digester: SHA256ContentDigester()
            ),
            artifacts: bindings
        )
    }

    private func canonicalStageResult(
        _ stage: Stage,
        domainArtifacts: [Artifact],
        canonicalBindings: [FlowArtifactBinding]
    ) -> FlowStageResult {
        let artifactIDs = Set(domainArtifacts.compactMap { artifact in
            canonicalArtifactKinds(forStage: stage.name).contains(artifact.kind)
                ? canonicalArtifactID(for: artifact)
                : nil
        })
        let stageArtifacts = canonicalBindings.filter { artifactIDs.contains($0.logicalID) }
        switch stage.status {
        case .passed:
            return FlowStageResult(
                stageID: stage.name,
                status: .succeeded,
                artifacts: stageArtifacts
            )
        case .skipped:
            return FlowStageResult(
                stageID: stage.name,
                status: .skipped,
                artifacts: stageArtifacts
            )
        case .failed:
            let diagnostic = FlowDiagnostic(
                severity: .error,
                code: "HEADLESS_STAGE_FAILED",
                message: stage.message ?? "The headless stage failed."
            )
            return FlowStageResult(
                stageID: stage.name,
                status: .failed,
                diagnostics: [diagnostic],
                gates: [
                    FlowGateResult(
                        gateID: "headless-stage",
                        status: .failed,
                        diagnostics: [diagnostic]
                    ),
                ],
                artifacts: stageArtifacts
            )
        }
    }

    private func canonicalArtifactKinds(forStage stageName: String) -> Set<String> {
        switch stageName {
        case "input-artifact-capture": ["design-spec"]
        case "netlist-generation": ["pre-layout-netlist"]
        case "pre-layout-simulation": ["pre-layout-simulation-report", "pre-layout-waveform"]
        case "auto-layout": ["layout-document", "design-unit"]
        case "layout-trust": [
            "layout-trust-canonical-layout",
            "layout-ownership-map",
            "net-aware-layout-report",
            "layout-trust-report",
            "layout-trust-artifact-manifest",
        ]
        case "external-signoff": [
            "external-signoff-log",
            "external-signoff-review",
            "external-signoff-executable",
            "external-signoff-execution-evidence",
        ]
        case "pre-pex-verification": ["physical-verification-report"]
        case "pex-injection": ["pex-artifact", "post-layout-netlist"]
        case "post-layout-simulation": ["post-layout-simulation-report", "post-layout-waveform"]
        case "post-layout-oracle": ["post-layout-oracle-report", "configuration-error-report"]
        case "post-layout-comparison": ["post-layout-comparison"]
        default: []
        }
    }

    private func canonicalToolchainManifest(
        runID: String,
        stages: [Stage]
    ) -> FlowToolchainManifest {
        FlowToolchainManifest(
            runID: runID,
            stages: stages.map { stage in
                FlowToolchainStageRecord(
                    stageID: stage.name,
                    executorToolID: canonicalExecutorToolID(forStage: stage.name)
                )
            }
        )
    }

    private func canonicalExecutorToolID(forStage stageName: String) -> String {
        switch stageName {
        case "input-artifact-capture": "circuit-studio-artifact-capture"
        case "net-extraction": "circuit-studio-net-extractor"
        case "netlist-generation": "circuit-studio-netlist-generator"
        case "pre-layout-simulation", "post-layout-simulation": "corespice"
        case "auto-layout", "layout-trust": "semiconductor-layout"
        case "external-signoff": "circuit-signoff"
        case "pre-pex-verification": "circuit-studio-local-preflight"
        case "pex-injection": "circuit-studio-pex-injection"
        case "post-layout-oracle": "circuit-studio-post-layout-oracle"
        case "post-layout-comparison": "circuit-studio-post-layout-comparison"
        default: "circuit-studio-headless"
        }
    }

    private func canonicalSupportingTools(
        externallyExecutedTools: [ProducerIdentity]
    ) async throws -> [ProducerIdentity] {
        var identities: [String: ProducerIdentity] = [:]
        for identifier in ["corespice", "semiconductor-layout", "circuit-signoff"] {
            identities[identifier] = try await CircuitStudioExecutionEnvironment.producerIdentity(
                kind: .library,
                identifier: identifier
            )
        }
        for measured in externallyExecutedTools {
            if let existing = identities[measured.identifier], existing != measured {
                throw StudioError.invalidDesign(
                    "External signoff tool '\(measured.identifier)' resolves to conflicting executable identities."
                )
            }
            identities[measured.identifier] = measured
        }
        return identities.values.sorted { $0.identifier < $1.identifier }
    }

    private func canonicalArtifactBindings(
        domainManifestURL: URL,
        artifacts: [Artifact],
        configuration: Configuration
    ) throws -> [FlowArtifactBinding] {
        let runPrefix = "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(configuration.runID)"
        let manifestPath = try RoundTripArtifactResolver(
            runDirectory: try XcircuiteWorkspaceLayout(projectRoot: configuration.projectRoot)
                .runDirectoryURL(for: configuration.runID)
        ).relativePath(for: domainManifestURL)
        guard manifestPath == "round-trip-manifest.json" else {
            throw StudioError.projectSaveFailed(
                "The canonical round-trip manifest resolved to an unexpected run path: \(manifestPath)"
            )
        }
        var bindings = try artifacts.map { artifact in
            try artifactBinding(
                logicalID: canonicalArtifactID(for: artifact),
                path: "\(runPrefix)/\(artifact.path)",
                role: artifact.binding.role,
                kind: canonicalFileKind(for: artifact.kind),
                format: canonicalFileFormat(for: artifact.path),
                projectRoot: configuration.projectRoot
            )
        }
        bindings.append(try artifactBinding(
            logicalID: "round-trip-manifest",
            path: "\(runPrefix)/\(manifestPath)",
            role: .output,
            kind: .report,
            format: .json,
            projectRoot: configuration.projectRoot
        ))

        for binding in bindings {
            let integrity = LocalArtifactVerifier().verify(
                binding.reference,
                at: try artifactLocator(for: binding),
                relativeTo: configuration.projectRoot
            )
            guard integrity.isVerified else {
                throw StudioError.projectSaveFailed(
                    "Canonical run artifact integrity failed for \(binding.availabilityDescription): \(integrityMessage(integrity))"
                )
            }
        }
        return bindings
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

    private func artifactBinding(
        logicalID: String,
        path: String,
        role: ArtifactRole = .output,
        kind: ArtifactKind,
        format: ArtifactFormat,
        projectRoot: URL
    ) throws -> FlowArtifactBinding {
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: role,
            kind: kind,
            format: format
        )
        let captured = try LocalArtifactReferencer().reference(locator, relativeTo: projectRoot)
        let relativePath = try ArtifactRelativePath(
            segments: path.split(separator: "/").map(String.init)
        )
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        return try FlowArtifactBinding(
            logicalID: logicalID,
            reference: captured,
            availability: .local(
                artifactID: captured.id,
                rootID: workspaceStore.artifactRootID,
                relativePath: relativePath
            )
        )
    }

    private func artifactLocator(for binding: FlowArtifactBinding) throws -> ArtifactLocator {
        let relativePath = try binding.requireLocalRelativePath()
        return ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: relativePath.stringValue),
            role: binding.role,
            kind: binding.kind,
            format: binding.format
        )
    }

    private func canonicalArtifactID(for artifact: Artifact) -> String {
        artifact.binding.logicalID
    }

    private func canonicalArtifactID(kind: String, path: String) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitizedKind = String(kind.unicodeScalars.map {
            allowed.contains($0) ? Character(String($0)) : "-"
        })
        let kind = sanitizedKind.isEmpty ? "headless-artifact" : sanitizedKind
        let digest = try SHA256ContentDigester().digest(data: Data(path.utf8), using: .sha256)
        return "\(kind.prefix(96))-\(digest.hexadecimalValue.prefix(24))"
    }

    private func canonicalFileKind(for kind: String) -> ArtifactKind {
        if kind == "external-signoff-executable" {
            return .other
        }
        if kind.contains("netlist") {
            return .netlist
        }
        if kind.contains("waveform") {
            return .waveform
        }
        if kind.contains("pex") || kind.contains("parasitic") {
            return .parasitics
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

    private func canonicalFileFormat(for path: String) -> ArtifactFormat {
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
    ) async throws -> (
        review: ExternalSignoffReview,
        supportingTools: [ProducerIdentity],
        results: [ExternalSignoffCommandResult],
        evidenceURL: URL?,
        artifactRole: ArtifactRole
    )? {
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
            return (review, [], [], nil, .input)
        }

        guard !configuration.externalSignoffCommands.isEmpty else {
            return nil
        }

        let artifactDirectory = runDirectory.appending(path: "external-signoff")
        let batch = try await signoffCommandRunner.run(
            commands: configuration.externalSignoffCommands,
            artifactDirectory: artifactDirectory
        )
        var review = batch.review
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

        return (
            review,
            batch.results.map(\.provenance.producer),
            batch.results,
            batch.evidenceURL,
            .output
        )
    }

    private func captureExternalSignoffExecutionArtifacts(
        reports: [ExternalSignoffToolReport],
        results: [ExternalSignoffCommandResult],
        evidenceURL: URL?,
        role: ArtifactRole,
        runDirectory: URL
    ) throws -> [Artifact] {
        let logPaths = Array(Set(reports.map(\.logPath))).sorted()
        var artifacts = if role == .input {
            try captureInputArtifacts(
                paths: logPaths,
                kind: "external-signoff-log",
                runDirectory: runDirectory,
                subdirectory: "signoff"
            )
        } else {
            try captureGeneratedArtifacts(
                paths: logPaths,
                kind: "external-signoff-log",
                runDirectory: runDirectory,
                subdirectory: "signoff"
            )
        }
        artifacts.append(contentsOf: try captureGeneratedArtifacts(
            paths: Array(Set(results.map {
                $0.executableSnapshotURL.path(percentEncoded: false)
            })).sorted(),
            kind: "external-signoff-executable",
            runDirectory: runDirectory,
            subdirectory: "signoff/executables"
        ))
        if let evidenceURL {
            artifacts.append(contentsOf: try captureGeneratedArtifacts(
                paths: [evidenceURL.path(percentEncoded: false)],
                kind: "external-signoff-execution-evidence",
                runDirectory: runDirectory,
                subdirectory: "signoff"
            ))
        }
        return artifacts
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

    private func layoutTrustArtifacts(
        _ published: LayoutTrustArtifactWriter.WriteResult,
        runDirectory: URL
    ) throws -> [Artifact] {
        var artifacts = [
            try artifact(
                kind: "layout-trust-canonical-layout",
                url: URL(filePath: published.canonicalLayoutPath),
                runDirectory: runDirectory
            ),
            try artifact(
                kind: "layout-ownership-map",
                url: URL(filePath: published.ownershipMapPath),
                runDirectory: runDirectory
            ),
            try artifact(
                kind: "net-aware-layout-report",
                url: URL(filePath: published.netAwareReportPath),
                runDirectory: runDirectory
            ),
            try artifact(
                kind: LayoutTrustReport.artifactKind,
                url: URL(filePath: published.layoutTrustReportPath),
                runDirectory: runDirectory
            ),
        ]
        if let manifestPath = published.layoutArtifactManifestPath {
            artifacts.append(try artifact(
                kind: "layout-trust-artifact-manifest",
                url: URL(filePath: manifestPath),
                runDirectory: runDirectory
            ))
        }
        return artifacts
    }

    private func persistPrePEXVerificationArtifact(
        _ report: DesignFlowVerificationReport,
        runDirectory: URL,
        artifacts: inout [Artifact]
    ) throws {
        let reportURL = runDirectory.appending(path: "physical-verification.json")
        try writeJSON(report, to: reportURL)
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
                return try artifact(
                    kind: kind,
                    url: sourceURL,
                    runDirectory: runDirectory,
                    role: .input
                )
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
                role: .input,
                sourcePath: sourcePath
            )
        }
    }

    private func captureGeneratedArtifacts(
        paths: [String],
        kind: String,
        runDirectory: URL,
        subdirectory: String
    ) throws -> [Artifact] {
        guard !paths.isEmpty else { return [] }
        let captureDirectory = runDirectory
            .appending(path: "generated-artifacts")
            .appending(path: subdirectory)
        try createDirectory(captureDirectory)

        var usedNames = Set<String>()
        return try paths.map { path in
            let sourceURL = URL(filePath: path)
            let sourcePath = sourceURL.path(percentEncoded: false)
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: sourcePath, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                throw StudioError.projectLoadFailed(
                    "Generated artifact is missing or not a regular file: \(sourcePath)"
                )
            }
            let resolvedSourceURL = sourceURL.resolvingSymlinksInPath()
            let values = try resolvedSourceURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                throw StudioError.projectLoadFailed(
                    "Generated artifact must resolve to a regular file: \(sourcePath)"
                )
            }
            if isArtifactAlreadyInsideRunDirectory(
                sourceURL: resolvedSourceURL,
                runDirectory: runDirectory
            ) {
                return try artifact(
                    kind: kind,
                    url: resolvedSourceURL,
                    runDirectory: runDirectory,
                    role: .output
                )
            }
            let destinationURL = uniqueCaptureURL(
                for: resolvedSourceURL,
                in: captureDirectory,
                usedNames: &usedNames
            )
            do {
                try FileManager.default.copyItem(at: resolvedSourceURL, to: destinationURL)
            } catch {
                throw StudioError.projectSaveFailed(
                    "Failed to retain generated artifact \(sourcePath): \(error.localizedDescription)"
                )
            }
            return try artifact(
                kind: kind,
                url: destinationURL,
                runDirectory: runDirectory,
                role: .output,
                sourcePath: sourcePath
            )
        }
    }

    private func artifact(
        kind: String,
        url: URL,
        runDirectory: URL,
        role: ArtifactRole = .output,
        sourcePath: String? = nil
    ) throws -> Artifact {
        let path = try RoundTripArtifactResolver(
            runDirectory: runDirectory
        ).relativePath(for: url)
        let binding = try FlowArtifactBinding.circuitStudioBinding(
            logicalID: canonicalArtifactID(kind: kind, path: path),
            kind: kind,
            relativePath: path,
            fileURL: url,
            role: role
        )
        return Artifact(
            binding: binding,
            sourcePath: sourcePath
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
        if verification.externalSignoff == nil {
            parts.append("retained external DRC/LVS signoff evidence is missing")
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
