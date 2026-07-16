import CircuitSignoff
import Foundation
import CircuitStudioCore
import PEXEngine
import CircuitPhysicalDesign
import CoreSpiceWaveform
import LayoutCore
import LayoutTech
import LayoutEngine
import Xcircuite
import DesignFlowKernel

public struct DesignFlowService: Sendable {
    private let simulationService: SimulationService
    private let netlistGenerator: NetlistGenerator
    private let layoutTrustEvaluator: any LayoutTrustEvaluating
    private let layoutTrustArtifactWriter: any LayoutTrustArtifactWriting
    public let layoutEngineCatalog: any LayoutEngineCataloging

    public init(
        simulationService: SimulationService = SimulationService(),
        netlistGenerator: NetlistGenerator = NetlistGenerator(),
        layoutTrustEvaluator: any LayoutTrustEvaluating = LayoutTrustEvaluationService(),
        layoutTrustArtifactWriter: any LayoutTrustArtifactWriting = LayoutTrustArtifactWriter(),
        layoutEngineCatalog: any LayoutEngineCataloging = CircuitPhysicalDesignDefaults.layoutEngineCatalog()
    ) {
        self.simulationService = simulationService
        self.netlistGenerator = netlistGenerator
        self.layoutTrustEvaluator = layoutTrustEvaluator
        self.layoutTrustArtifactWriter = layoutTrustArtifactWriter
        self.layoutEngineCatalog = layoutEngineCatalog
    }

    public var activeSimulationJobID: UUID? {
        simulationService.activeJobID
    }

    @discardableResult
    public func cancelActiveSimulation() -> UUID? {
        guard let jobID = simulationService.activeJobID else {
            return nil
        }
        simulationService.cancel(jobID: jobID)
        return jobID
    }

    public func runSPICESimulation(
        _ request: DesignFlowSPICESimulationRequest
    ) async throws -> SimulationResult {
        try await simulationService.runSPICE(
            source: request.source,
            fileName: request.fileName,
            processConfiguration: request.processConfiguration,
            onWaveformUpdate: request.onWaveformUpdate
        )
    }

    public func generateNetlist(_ request: DesignFlowNetlistRequest) throws -> String {
        try netlistGenerator.generate(
            from: request.schematic,
            library: request.library,
            title: request.title ?? "Schematic",
            testbench: request.testbench,
            processConfiguration: request.processConfiguration
        )
    }

    public func runAnalysis(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration?,
        command: AnalysisCommand
    ) async throws -> SimulationResult {
        try await simulationService.runAnalysis(
            source: source,
            fileName: fileName,
            processConfiguration: processConfiguration,
            command: command
        )
    }

    /// Returns every analysis the SPICE source declares, in declaration order.
    public func detectAnalyses(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration?
    ) async throws -> [AnalysisCommand] {
        try await simulationService.detectAnalyses(
            source: source,
            fileName: fileName,
            processConfiguration: processConfiguration
        )
    }

    /// Runs an analysis × corner matrix and returns one record per cell.
    public func runAnalysisMatrix(
        _ request: AnalysisMatrixRequest,
        onRecordFinished: (@Sendable (AnalysisRunRecord) -> Void)? = nil
    ) async -> [AnalysisRunRecord] {
        await AnalysisMatrixRunner(simulationService: simulationService)
            .run(request, onRecordFinished: onRecordFinished)
    }

    public func runSchematicSimulation(
        _ request: DesignFlowSchematicSimulationRequest
    ) async throws -> DesignFlowSchematicSimulationResult {
        let netlist = try generateNetlist(DesignFlowNetlistRequest(
            schematic: request.schematic,
            library: request.library,
            title: request.title ?? "Schematic Simulation",
            testbench: request.testbench,
            processConfiguration: request.processConfiguration
        ))
        let result = try await simulationService.runSPICE(
            source: netlist,
            fileName: "schematic.cir",
            processConfiguration: request.processConfiguration,
            onWaveformUpdate: request.onWaveformUpdate
        )
        return DesignFlowSchematicSimulationResult(
            netlist: netlist,
            simulationResult: result
        )
    }

    @MainActor
    public func generateLayout(
        _ request: DesignFlowLayoutGenerationRequest
    ) throws -> CircuitLayoutSynthesisOutput {
        try CircuitLayoutSynthesizer(layoutEngineCatalog: layoutEngineCatalog).generate(
            from: request.schematic,
            catalog: request.catalog,
            tech: request.tech,
            placementStrategy: request.placementStrategy,
            routingStrategy: request.routingStrategy,
            constraints: request.constraints
        )
    }

    public func runPrePEXVerification(
        _ request: DesignFlowPrePEXVerificationRequest
    ) -> PhysicalVerificationReport {
        PhysicalVerificationService().runPrePEXVerification(
            schematic: request.schematic,
            layout: request.layout,
            tech: request.tech,
            designUnit: request.designUnit,
            catalog: request.catalog,
            externalSignoff: request.externalSignoff
        )
    }

    public func buildPostLayoutNetlist(
        baseNetlist: String,
        parasitics: PEXParasiticIR
    ) -> String {
        PostLayoutSimulationService().buildPostLayoutNetlist(
            baseNetlist: baseNetlist,
            parasitics: parasitics
        )
    }

    public func buildHierarchicalPostLayoutNetlist(
        baseNetlist: String,
        canonicalIR: ParasiticIR,
        topCell: String? = nil
    ) throws -> String {
        try PostLayoutSimulationService().buildHierarchicalPostLayoutNetlist(
            baseNetlist: baseNetlist,
            canonicalIR: canonicalIR,
            topCell: topCell
        )
    }

    public func buildPostLayoutNetlist(
        baseNetlist: String,
        manifestURL: URL,
        cornerID: String,
        topCell: String? = nil
    ) throws -> String {
        let canonicalIR = try PEXArtifactService().loadCanonicalIR(
            for: cornerID,
            manifestURL: manifestURL
        )
        return try buildHierarchicalPostLayoutNetlist(
            baseNetlist: baseNetlist,
            canonicalIR: canonicalIR,
            topCell: topCell
        )
    }

    public func runPostLayoutSimulation(
        _ request: DesignFlowPostLayoutSimulationRequest
    ) async throws -> SimulationResult {
        try await PostLayoutSimulationService().runPostLayoutAnalysis(
            baseNetlist: request.baseNetlist,
            parasitics: request.parasitics,
            command: request.command,
            processConfiguration: request.processConfiguration,
            simulationService: simulationService
        )
    }

    public func runHierarchicalPostLayoutSimulation(
        baseNetlist: String,
        canonicalIR: ParasiticIR,
        topCell: String? = nil,
        command: AnalysisCommand,
        processConfiguration: ProcessConfiguration? = nil
    ) async throws -> SimulationResult {
        try await PostLayoutSimulationService().runHierarchicalPostLayoutAnalysis(
            baseNetlist: baseNetlist,
            canonicalIR: canonicalIR,
            topCell: topCell,
            command: command,
            processConfiguration: processConfiguration,
            simulationService: simulationService
        )
    }

    public func runPostLayoutSimulation(
        baseNetlist: String,
        manifestURL: URL,
        cornerID: String,
        topCell: String? = nil,
        command: AnalysisCommand,
        processConfiguration: ProcessConfiguration? = nil
    ) async throws -> SimulationResult {
        let canonicalIR = try PEXArtifactService().loadCanonicalIR(
            for: cornerID,
            manifestURL: manifestURL
        )
        return try await runHierarchicalPostLayoutSimulation(
            baseNetlist: baseNetlist,
            canonicalIR: canonicalIR,
            topCell: topCell,
            command: command,
            processConfiguration: processConfiguration
        )
    }

    public func comparePostLayout(
        preLayoutResult: SimulationResult,
        postLayoutResult: SimulationResult,
        limits: PostLayoutComparisonLimits? = nil
    ) -> CircuitStudioCore.PostLayoutComparisonReport {
        PostLayoutComparisonService().compare(
            preLayoutResult: preLayoutResult,
            postLayoutResult: postLayoutResult,
            limits: limits
        )
    }

    @MainActor
    public func runRoundTrip(
        _ request: DesignFlowRoundTripRequest
    ) async throws -> HeadlessRoundTripService.Result {
        try await HeadlessRoundTripService(
            layoutEngineCatalog: layoutEngineCatalog
        ).run(
            schematic: request.schematic,
            configuration: request.configuration
        )
    }

    public func loadPEXInput(
        manifestURL: URL,
        cornerID: String
    ) throws -> DesignFlowPEXInput {
        let service = PEXArtifactService()
        _ = try service.loadManifest(manifestURL: manifestURL)
        let ir = try service.loadIR(for: cornerID, manifestURL: manifestURL)
        let artifactPaths = try service.auditArtifactURLs(manifestURL: manifestURL, cornerID: cornerID)
            .map { $0.path(percentEncoded: false) }
        return DesignFlowPEXInput(ir: ir, artifactPaths: artifactPaths)
    }

    public func runPEXExtraction(
        _ request: DesignFlowPEXExtractionRequest
    ) async throws -> PEXBackendExtractionResult {
        let adapter = PEXEngineCommandBackendAdapter(executablePath: request.executablePath)
        return try await adapter.extract(request: PEXBackendExtractionRequest(
            configURL: request.configURL,
            workingDirectory: request.workingDirectory,
            cornerID: request.cornerID,
            executablePath: request.executablePath,
            additionalArguments: request.additionalArguments
        ))
    }

    public func loadExternalSignoffReview(
        logs: [ExternalSignoffLogArtifact]
    ) throws -> ExternalSignoffReview {
        try ExternalSignoffArtifactService().load(logs: logs)
    }

    /// Produces a signoff review by running the REAL DRC + LVS tools on a layout
    /// (instead of replaying golden logs). Throws `signoffToolchainUnavailable`
    /// when the toolchain is absent — never silently falls back to mock/replay.
    public func runLiveSignoff(
        layoutGDS: URL,
        topCell: String,
        schematicNetlist: URL,
        artifactDirectory: URL
    ) async throws -> ExternalSignoffReview {
        guard let service = LiveSignoffService.locate() else {
            throw DesignFlowCommandError.signoffToolchainUnavailable
        }
        return try await service.run(
            layoutGDS: layoutGDS,
            topCell: topCell,
            schematicNetlist: schematicNetlist,
            artifactDirectory: artifactDirectory
        )
    }

    /// Runs the agent edit → signoff → iterate loop (G4) with real signoff:
    /// `nextCandidate` is the agent's edit decision each round, and the loop
    /// converges when a candidate passes real DRC+LVS. Throws
    /// `signoffToolchainUnavailable` when the toolchain is absent (no silent
    /// fallback).
    public func runSignoffIterationLoop(
        maxIterations: Int,
        artifactDirectory: URL,
        nextCandidate: (_ index: Int, _ lastReview: ExternalSignoffReview?) async throws -> SignoffIterationLoop.Candidate?
    ) async throws -> SignoffIterationLoop.LoopResult {
        guard let loop = SignoffIterationLoop.locate() else {
            throw DesignFlowCommandError.signoffToolchainUnavailable
        }
        return try await loop.run(
            maxIterations: maxIterations,
            artifactDirectory: artifactDirectory,
            nextCandidate: nextCandidate
        )
    }

    public func summarizeBottlenecks(
        projectRoot: URL
    ) throws -> RoundTripBottleneckHistoryService.Summary {
        try RoundTripBottleneckHistoryService().summarize(forProjectAt: projectRoot)
    }

    public func summarizeSignoffRepairCandidateCycles(
        projectRoot: URL
    ) throws -> RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary {
        try RunReviewSignoffRepairCandidateCycleHistoryIndexService().summarize(forProjectAt: projectRoot)
    }

    public func qualifySignoffRepairCandidateCycles(
        projectRoot: URL,
        request: RunReviewSignoffRepairCandidateCycleHistoryQualificationService.Request
    ) throws -> RunReviewSignoffRepairCandidateCycleHistoryQualificationService.Report {
        try RunReviewSignoffRepairCandidateCycleHistoryQualificationService()
            .qualify(forProjectAt: projectRoot, request: request)
    }

    private func signoffRepairHistoryQualificationRequest(
        for command: DesignFlowCommand,
        profile: RunReviewSignoffRepairCandidateCycleHistoryQualificationService.Profile?
    ) -> RunReviewSignoffRepairCandidateCycleHistoryQualificationService.Request {
        let base = profile?.request ?? RunReviewSignoffRepairCandidateCycleHistoryQualificationService.Request()
        return RunReviewSignoffRepairCandidateCycleHistoryQualificationService.Request(
            minimumRunCount: command.signoffRepairHistoryMinimumRunCount ?? base.minimumRunCount,
            minimumCycleCount: command.signoffRepairHistoryMinimumCycleCount ?? base.minimumCycleCount,
            minimumAcceptedCount: command.signoffRepairHistoryMinimumAcceptedCount ?? base.minimumAcceptedCount,
            minimumFeedbackRankChangeCount:
                command.signoffRepairHistoryMinimumFeedbackRankChangeCount ?? base.minimumFeedbackRankChangeCount,
            minimumFeedbackScoreDeltaCount:
                command.signoffRepairHistoryMinimumFeedbackScoreDeltaCount ?? base.minimumFeedbackScoreDeltaCount,
            minimumAcceptedCountPerSelectedObjectiveDomain:
                command.signoffRepairHistoryMinimumAcceptedCountPerSelectedObjectiveDomain
                    ?? base.minimumAcceptedCountPerSelectedObjectiveDomain,
            requiredSelectedActionDomainIDs:
                command.signoffRepairHistoryRequiredSelectedActionDomainIDs
                    ?? base.requiredSelectedActionDomainIDs,
            requiredSelectedObjectiveDomainIDs:
                command.signoffRepairHistoryRequiredSelectedObjectiveDomainIDs
                    ?? base.requiredSelectedObjectiveDomainIDs
        )
    }

    public func loadDesignSpec(_ url: URL) throws -> DesignFlowDesignSpec {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(DesignFlowDesignSpec.self, from: data)
        } catch let error as DesignFlowDesignSpecError {
            throw error
        } catch {
            throw StudioError.projectLoadFailed("Failed to load design spec: \(error.localizedDescription)")
        }
    }

    public func loadDesignEditScript(_ url: URL) throws -> DesignFlowDesignEditScript {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(DesignFlowDesignEditScript.self, from: data)
        } catch {
            throw StudioError.projectLoadFailed("Failed to load design edit script: \(error.localizedDescription)")
        }
    }

    public func loadLayoutDocument(_ url: URL) throws -> LayoutDocument {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(LayoutDocument.self, from: data)
        } catch {
            throw StudioError.projectLoadFailed("Failed to load layout document: \(error.localizedDescription)")
        }
    }

    public func loadLayoutEditScript(_ url: URL) throws -> DesignFlowLayoutEditScript {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(DesignFlowLayoutEditScript.self, from: data)
        } catch {
            throw StudioError.projectLoadFailed("Failed to load layout edit script: \(error.localizedDescription)")
        }
    }

    public func loadDesignUnit(_ url: URL) throws -> DesignUnit {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(DesignUnit.self, from: data)
        } catch {
            throw StudioError.projectLoadFailed("Failed to load design unit: \(error.localizedDescription)")
        }
    }

    public func loadFlowRunnerFailureEnvelope(_ url: URL) throws -> FlowRunnerFailureEnvelope {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(FlowRunnerFailureEnvelope.self, from: data)
        } catch {
            throw StudioError.projectLoadFailed("Failed to load flow-runner failure envelope: \(error.localizedDescription)")
        }
    }

    public func loadTechnologyPackage(_ manifestURL: URL) throws -> TechnologyPackage {
        try TechnologyPackageLoader().load(manifestURL: manifestURL)
    }

    @MainActor
    public func execute(_ command: DesignFlowCommand) async throws -> DesignFlowCommandResult {
        switch command.kind {
        case .listFixtures:
            return DesignFlowCommandResult(
                kind: command.kind,
                fixtureNames: DesignFlowFixtureLibrary.fixtureNames
            )
        case .generateFixtureNetlist:
            let fixture = try fixture(for: command)
            let package = try technologyPackage(for: command)
            let netlist = try generateNetlist(DesignFlowNetlistRequest(
                schematic: fixture.schematic,
                title: fixture.title,
                testbench: fixture.testbench,
                processConfiguration: package?.processConfiguration
            ))
            return DesignFlowCommandResult(
                kind: command.kind,
                fixtureName: fixture.name,
                netlist: netlist,
                technologyPackageID: package?.manifest.packageID,
                technologyPackagePath: package?.manifestURL.path(percentEncoded: false)
            )
        case .runFixtureSimulation:
            let fixture = try fixture(for: command)
            let package = try technologyPackage(for: command)
            let result = try await runSchematicSimulation(DesignFlowSchematicSimulationRequest(
                schematic: fixture.schematic,
                title: fixture.title,
                testbench: fixture.testbench,
                processConfiguration: package?.processConfiguration
            ))
            return DesignFlowCommandResult(
                kind: command.kind,
                fixtureName: fixture.name,
                netlist: result.netlist,
                simulationStatus: result.simulationResult.status.rawValue,
                technologyPackageID: package?.manifest.packageID,
                technologyPackagePath: package?.manifestURL.path(percentEncoded: false)
            )
        case .runFixtureRoundTrip:
            return try await runFixtureRoundTrip(command)
        case .generateDesignNetlist:
            let design = try design(for: command)
            let package = try technologyPackage(for: command)
            let netlist = try generateNetlist(DesignFlowNetlistRequest(
                schematic: design.schematic,
                title: design.title,
                testbench: design.testbench,
                processConfiguration: package?.processConfiguration
            ))
            return DesignFlowCommandResult(
                kind: command.kind,
                designName: design.name,
                netlist: netlist,
                technologyPackageID: package?.manifest.packageID,
                technologyPackagePath: package?.manifestURL.path(percentEncoded: false)
            )
        case .runDesignSimulation:
            let design = try design(for: command)
            let package = try technologyPackage(for: command)
            let result = try await runSchematicSimulation(DesignFlowSchematicSimulationRequest(
                schematic: design.schematic,
                title: design.title,
                testbench: design.testbench,
                processConfiguration: package?.processConfiguration
            ))
            return DesignFlowCommandResult(
                kind: command.kind,
                designName: design.name,
                netlist: result.netlist,
                simulationStatus: result.simulationResult.status.rawValue,
                technologyPackageID: package?.manifest.packageID,
                technologyPackagePath: package?.manifestURL.path(percentEncoded: false)
            )
        case .runDesignRoundTrip:
            return try await runDesignRoundTrip(command)
        case .summarizeBottlenecks:
            guard let projectRootPath = command.projectRootPath else {
                throw DesignFlowCommandError.missingProjectRoot
            }
            let projectRoot = URL(filePath: projectRootPath)
            let summary = try summarizeBottlenecks(projectRoot: projectRoot)
            return DesignFlowCommandResult(
                kind: command.kind,
                projectRootPath: projectRoot.path(percentEncoded: false),
                bottleneckHistory: summary
            )
        case .summarizeSignoffRepairCandidateCycles:
            guard let projectRootPath = command.projectRootPath else {
                throw DesignFlowCommandError.missingProjectRoot
            }
            let projectRoot = URL(filePath: projectRootPath)
            let summary = try summarizeSignoffRepairCandidateCycles(projectRoot: projectRoot)
            return DesignFlowCommandResult(
                kind: command.kind,
                projectRootPath: projectRoot.path(percentEncoded: false),
                signoffRepairCandidateCycleHistoryIndex: summary
            )
        case .qualifySignoffRepairCandidateCycles:
            guard let projectRootPath = command.projectRootPath else {
                throw DesignFlowCommandError.missingProjectRoot
            }
            let projectRoot = URL(filePath: projectRootPath)
            let qualificationService = RunReviewSignoffRepairCandidateCycleHistoryQualificationService()
            let profilePath = command.signoffRepairHistoryQualificationProfilePath
            let profile = try profilePath.map {
                try qualificationService.loadProfile(from: URL(filePath: $0))
            }
            let report = try qualificationService.qualify(
                forProjectAt: projectRoot,
                request: signoffRepairHistoryQualificationRequest(
                    for: command,
                    profile: profile
                ),
                profile: profile,
                profilePath: profilePath
            )
            let artifact = try await qualificationService.persist(report, forProjectAt: projectRoot)
            return DesignFlowCommandResult(
                kind: command.kind,
                projectRootPath: projectRoot.path(percentEncoded: false),
                signoffRepairCandidateCycleHistoryIndex: report.summary,
                signoffRepairCandidateCycleHistoryQualification: report.attachingArtifactReference(artifact),
                signoffRepairCandidateCycleHistoryQualificationArtifact: artifact,
                signoffRepairCandidateCycleHistoryQualificationPath: try absolutePath(
                    for: artifact,
                    projectRoot: projectRoot
                )
            )
        case .loadTechnologyPackage:
            let package = try requiredTechnologyPackage(for: command)
            return DesignFlowCommandResult(
                kind: command.kind,
                technologyPackageID: package.manifest.packageID,
                technologyPackagePath: package.manifestURL.path(percentEncoded: false),
                validationDiagnostics: package.validationReport.diagnostics,
                message: package.manifest.name
            )
        case .runPEXExtraction:
            return try await runPEXExtraction(command)
        case .inspectTimingModelProfiles:
            return try inspectTimingModelProfiles(command)
        case .buildTimingLibrary:
            return try await buildTimingLibrary(command)
        case .applyDesignEdit:
            return try applyDesignEdit(command)
        case .applyLayoutEdit:
            return try applyLayoutEdit(command)
        case .runLayoutTrust:
            return try runLayoutTrust(command)
        case .runVerification:
            return try await runVerification(command)
        case .approveGate:
            return try approveGate(command)
        case .reviewRoundTrip:
            return try reviewRoundTrip(command)
        case .selectFailureSuggestedCommand:
            return try selectFailureSuggestedCommand(command)
        case .runSelectedSuggestedCommand:
            return try await runSelectedSuggestedCommand(command)
        case .applyWaiverEditProposal:
            return try await applyWaiverEditProposal(command)
        case .runPostWaiverEditVerification:
            return try await runPostWaiverEditVerification(command)
        case .applyWaiverEditProposalAndRunPostVerification:
            return try await applyWaiverEditProposalAndRunPostVerification(command)
        case .formulateSignoffRepairPlanningProblem:
            return try await formulateSignoffRepairPlanningProblem(command)
        case .runSignoffRepairCandidateCycle:
            return try await runSignoffRepairCandidateCycle(command)
        case .runGoalLayoutAgent:
            return try runGoalLayoutAgent(command)
        case .scaffoldDesignSpec:
            return try scaffoldDesignSpec(command)
        }
    }



    private func approveGate(_ command: DesignFlowCommand) throws -> DesignFlowCommandResult {
        guard let gateID = command.approvalGateID else {
            throw DesignFlowCommandError.missingApprovalGateID
        }
        guard let reviewer = command.approvalReviewer else {
            throw DesignFlowCommandError.missingApprovalReviewer
        }
        let result = try FlowRunGovernanceService().approve(GateApprovalRequest(
            gateID: gateID,
            decision: command.approvalDecision ?? .approved,
            reviewer: reviewer,
            projectRoot: command.projectRootPath.map { URL(filePath: $0) },
            runID: command.runID,
            manifestURL: command.roundTripManifestPath.map { URL(filePath: $0) },
            targetArtifactURL: command.approvalTargetPath.map { URL(filePath: $0) },
            policy: command.approvalPolicy,
            waiverIDs: command.waiverIDs,
            note: command.approvalNote
        ))
        return DesignFlowCommandResult(
            kind: command.kind,
            runID: result.record.runID,
            projectRootPath: command.projectRootPath,
            approvalRecordPath: result.recordPath,
            approvalRecord: result.record,
            message: result.record.decision.rawValue
        )
    }

    @MainActor
    private func runLayoutTrust(_ command: DesignFlowCommand) throws -> DesignFlowCommandResult {
        guard let layoutDocumentPath = command.layoutDocumentPath else {
            throw DesignFlowCommandError.missingLayoutDocumentPath
        }
        let artifactDirectory = try layoutTrustArtifactDirectory(for: command)
        let package = try requiredTechnologyPackage(for: command)
        let layout = try loadLayoutDocument(URL(filePath: layoutDocumentPath))
        let tech = try layoutTech(for: package)
        let report = try layoutTrustEvaluator.evaluate(document: layout, tech: tech, policy: LayoutOwnershipPolicy())
        let artifacts = try layoutTrustArtifactWriter.write(
            document: layout,
            report: report,
            to: artifactDirectory
        )

        return DesignFlowCommandResult(
            kind: command.kind,
            runID: command.runID,
            projectRootPath: command.projectRootPath,
            technologyPackageID: package.manifest.packageID,
            technologyPackagePath: package.manifestURL.path(percentEncoded: false),
            layoutTrustPassed: report.passed,
            layoutTrustReportPath: artifacts.layoutTrustReportPath,
            layoutTrustReport: report,
            message: report.status.rawValue
        )
    }

    @MainActor
    func runVerification(_ command: DesignFlowCommand) async throws -> DesignFlowCommandResult {
        guard let layoutDocumentPath = command.layoutDocumentPath else {
            throw DesignFlowCommandError.missingLayoutDocumentPath
        }
        let artifactDirectory = try verificationArtifactDirectory(for: command)
        let verificationInput = try verificationDesign(for: command)
        let package = try requiredTechnologyPackage(for: command)
        try validateSignoffLogPair(in: command)
        let layout = try loadLayoutDocument(URL(filePath: layoutDocumentPath))
        let loadedDesignUnit = try command.designUnitPath.map { try loadDesignUnit(URL(filePath: $0)) }
        let designUnit = verificationDesignUnit(
            provided: loadedDesignUnit,
            schematic: verificationInput.schematic,
            layout: layout
        )
        let rawExternalSignoff = try await loadExternalSignoffReview(from: command, package: package)
        let externalSignoff = command.approveSignoff
            ? rawExternalSignoff?.approving(
                by: "design-flow-command",
                at: Date(),
                approvalKind: .automated
            )
            : rawExternalSignoff
        let tech = try layoutTech(for: package)
        let layoutTrustReport = try layoutTrustEvaluator.evaluate(document: layout, tech: tech, policy: LayoutOwnershipPolicy())
        let report = runPrePEXVerification(DesignFlowPrePEXVerificationRequest(
            schematic: verificationInput.schematic,
            layout: layout,
            tech: tech,
            designUnit: designUnit,
            catalog: .standard(),
            externalSignoff: externalSignoff
        ))
        let verificationReport = DesignFlowVerificationReport(report: report, layoutTrust: layoutTrustReport)

        let layoutTrustArtifacts = try layoutTrustArtifactWriter.write(
            document: layout,
            report: layoutTrustReport,
            to: artifactDirectory.appending(path: "layout")
        )
        let reportDirectory = artifactDirectory.appending(path: "reports")
        try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
        let reportURL = reportDirectory.appending(path: "physical-verification.json")
        try writeJSON(verificationReport, to: reportURL)

        return DesignFlowCommandResult(
            kind: command.kind,
            fixtureName: verificationInput.fixtureName,
            designName: verificationInput.designName,
            runID: command.runID,
            projectRootPath: command.projectRootPath,
            readyForPEX: verificationReport.readyForPEX,
            technologyPackageID: package.manifest.packageID,
            technologyPackagePath: package.manifestURL.path(percentEncoded: false),
            layoutTrustPassed: layoutTrustReport.passed,
            layoutTrustReportPath: layoutTrustArtifacts.layoutTrustReportPath,
            layoutTrustReport: layoutTrustReport,
            verificationReportPath: reportURL.path(percentEncoded: false),
            verificationReport: verificationReport,
            message: verificationReport.status
        )
    }

    private func reviewRoundTrip(_ command: DesignFlowCommand) throws -> DesignFlowCommandResult {
        let service = RoundTripReviewService()
        let summary: RoundTripReviewSummary
        if let path = command.roundTripManifestPath {
            summary = try service.loadReview(manifestURL: URL(filePath: path))
        } else if let projectRootPath = command.projectRootPath,
                  let runID = command.runID {
            summary = try service.loadReview(forProjectAt: URL(filePath: projectRootPath), runID: runID)
        } else {
            throw DesignFlowCommandError.missingRoundTripManifestPath
        }
        return DesignFlowCommandResult(
            kind: command.kind,
            runID: summary.runID,
            projectRootPath: command.projectRootPath,
            manifestPath: summary.manifestPath,
            readyForPEX: summary.isReadyForPEX,
            roundTripReview: summary,
            message: summary.status.rawValue
        )
    }

    private func selectFailureSuggestedCommand(
        _ command: DesignFlowCommand
    ) throws -> DesignFlowCommandResult {
        guard let failureEnvelopePath = command.failureEnvelopePath else {
            throw DesignFlowCommandError.missingFailureEnvelopePath
        }
        guard let commandID = command.suggestedCommandID else {
            throw DesignFlowCommandError.missingSuggestedCommandID
        }
        guard let reviewer = command.approvalReviewer else {
            throw DesignFlowCommandError.missingApprovalReviewer
        }

        let failureEnvelopeURL = URL(filePath: failureEnvelopePath)
        let failure = try loadFlowRunnerFailureEnvelope(failureEnvelopeURL)
        let actionLogService = RoundTripActionLogService()
        let record = try actionLogService.recordSuggestedCommandSelection(
            from: failure,
            commandID: commandID,
            reviewer: reviewer
        )
        let manifestURL: URL?
        if let manifest = failure.manifest {
            manifestURL = URL(filePath: manifest)
        } else {
            manifestURL = nil
        }
        let review = try manifestURL.map {
            try RoundTripReviewService().loadReview(manifestURL: $0)
        }
        let selection = try manifestURL.flatMap {
            try actionLogService.loadSuggestedCommandSelections(manifestURL: $0).last
        }

        return DesignFlowCommandResult(
            kind: command.kind,
            runID: failure.runID,
            projectRootPath: failure.projectRoot,
            manifestPath: failure.manifest,
            actionLogPath: manifestURL.map(actionLogService.actionLogPath(manifestURL:)),
            roundTripReview: review,
            selectedSuggestedCommand: selection,
            actionRecordIDs: [record.actionID],
            message: record.actionID
        )
    }

    private func runSelectedSuggestedCommand(
        _ command: DesignFlowCommand
    ) async throws -> DesignFlowCommandResult {
        guard let projectRootPath = command.projectRootPath else {
            throw DesignFlowCommandError.missingProjectRoot
        }
        guard let runID = command.runID else {
            throw DesignFlowCommandError.missingRunID
        }

        let resolved = try RoundTripSelectedSuggestedCommandResolver().resolve(
            request: RoundTripSelectedSuggestedCommandResolutionRequest(
                runID: runID,
                commandID: command.suggestedCommandID
            ),
            projectRoot: URL(filePath: projectRootPath)
        )
        return try await execute(resolved.command)
    }

    private func applyLayoutEdit(_ command: DesignFlowCommand) throws -> DesignFlowCommandResult {
        guard let layoutDocumentPath = command.layoutDocumentPath else {
            throw DesignFlowCommandError.missingLayoutDocumentPath
        }
        guard let editScriptPath = command.editScriptPath else {
            throw DesignFlowCommandError.missingEditScriptPath
        }
        guard let outputLayoutDocumentPath = command.outputLayoutDocumentPath else {
            throw DesignFlowCommandError.missingOutputLayoutDocumentPath
        }

        let outputURL = URL(filePath: outputLayoutDocumentPath)
        let artifactDirectory = try layoutEditArtifactDirectory(for: command, outputURL: outputURL)
        let layout = try loadLayoutDocument(URL(filePath: layoutDocumentPath))
        let script = try loadLayoutEditScript(URL(filePath: editScriptPath))
        let result = try DesignFlowLayoutEditService().apply(script: script, to: layout)
        try writeJSON(result.layout, to: outputURL)

        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        let actionLogURL = artifactDirectory.appending(path: "actions.jsonl")
        let diffURL = artifactDirectory.appending(path: "layout-diff.json")
        try writeLayoutActionLog(result.actionLog, to: actionLogURL)
        try writeJSON(result.diff, to: diffURL)

        return DesignFlowCommandResult(
            kind: command.kind,
            projectRootPath: command.projectRootPath,
            layoutDocumentPath: outputURL.path(percentEncoded: false),
            actionLogPath: actionLogURL.path(percentEncoded: false),
            layoutDiffPath: diffURL.path(percentEncoded: false),
            message: "\(result.actionLog.count) layout edit actions applied"
        )
    }

    private func applyDesignEdit(_ command: DesignFlowCommand) throws -> DesignFlowCommandResult {
        guard let designSpecPath = command.designSpecPath else {
            throw DesignFlowCommandError.missingDesignSpecPath
        }
        guard let editScriptPath = command.editScriptPath else {
            throw DesignFlowCommandError.missingEditScriptPath
        }
        guard let outputDesignSpecPath = command.outputDesignSpecPath else {
            throw DesignFlowCommandError.missingOutputDesignSpecPath
        }

        let outputURL = URL(filePath: outputDesignSpecPath)
        let artifactDirectory = try designEditArtifactDirectory(for: command, outputURL: outputURL)
        let design = try loadDesignSpec(URL(filePath: designSpecPath))
        let script = try loadDesignEditScript(URL(filePath: editScriptPath))
        let result = try DesignFlowDesignEditService().apply(script: script, to: design)
        try writeJSON(result.designSpec, to: outputURL)

        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        let actionLogURL = artifactDirectory.appending(path: "actions.jsonl")
        let diffURL = artifactDirectory.appending(path: "design-diff.json")
        try writeActionLog(result.actionLog, to: actionLogURL)
        try writeJSON(result.diff, to: diffURL)

        return DesignFlowCommandResult(
            kind: command.kind,
            designName: result.designSpec.name,
            projectRootPath: command.projectRootPath,
            designSpecPath: outputURL.path(percentEncoded: false),
            actionLogPath: actionLogURL.path(percentEncoded: false),
            designDiffPath: diffURL.path(percentEncoded: false),
            message: "\(result.actionLog.count) design edit actions applied"
        )
    }

    private func runPEXExtraction(_ command: DesignFlowCommand) async throws -> DesignFlowCommandResult {
        guard let pexConfigPath = command.pexConfigPath else {
            throw DesignFlowCommandError.missingPEXConfigPath
        }
        let result = try await runPEXExtraction(DesignFlowPEXExtractionRequest(
            configURL: URL(filePath: pexConfigPath),
            cornerID: command.pexCornerID ?? "tt_25c_1v0",
            executablePath: command.pexExecutablePath
        ))
        return DesignFlowCommandResult(
            kind: command.kind,
            pexCornerID: result.ir.cornerID,
            pexElementCount: result.ir.elements.count,
            pexManifestPath: result.manifestURL.path(percentEncoded: false),
            message: result.manifest.backendID
        )
    }


    @MainActor
    private func runDesignRoundTrip(_ command: DesignFlowCommand) async throws -> DesignFlowCommandResult {
        guard let designSpecPath = command.designSpecPath else {
            throw DesignFlowCommandError.missingDesignSpecPath
        }
        let design = try design(for: command)
        let runID = command.runID ?? "\(design.name)-\(Self.timestamp())"
        try HeadlessRoundTripService.validateRunID(runID)
        try validateSignoffLogPair(in: command)
        let limits = try comparisonLimits(from: command) ?? design.postLayoutComparisonLimits
        let package = try technologyPackage(for: command)

        let pexInput: DesignFlowPEXInput
        if let pexManifestPath = command.pexManifestPath {
            pexInput = try loadPEXInput(
                manifestURL: URL(filePath: pexManifestPath),
                cornerID: command.pexCornerID ?? "tt_25c_1v0"
            )
        } else if let package, let packagePEXManifestPath = package.manifest.pex?.savedManifestPath {
            pexInput = try loadPEXInput(
                manifestURL: package.resolvedURL(for: packagePEXManifestPath),
                cornerID: command.pexCornerID ?? package.manifest.pex?.defaultCornerID ?? "tt_25c_1v0"
            )
        } else if let pexIR = design.pexIR {
            pexInput = DesignFlowPEXInput(ir: pexIR, artifactPaths: [])
        } else {
            throw DesignFlowDesignSpecError.missingPEXInput
        }

        let externalSignoffReview = try await loadExternalSignoffReview(from: command, package: package)
        let projectRoot = URL(filePath: command.projectRootPath ?? defaultCommandProjectRoot(fixtureName: design.name))
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let resolvedLayoutTech = try package.map { try layoutTech(for: $0) }

        let configuration = HeadlessRoundTripService.Configuration(
            projectRoot: projectRoot,
            runID: runID,
            title: design.title,
            testbench: design.testbench,
            postLayoutCommand: design.postLayoutCommand,
            pexIR: pexInput.ir,
            designArtifactPaths: designArtifactPaths(designSpecPath: designSpecPath, technologyPackage: package),
            pexArtifactPaths: pexInput.artifactPaths,
            postLayoutComparisonLimits: limits,
            externalSignoffCommands: [],
            externalSignoffReview: externalSignoffReview,
            approvedBy: command.approveSignoff ? "design-flow-command" : nil,
            approvedAt: command.approveSignoff ? Date() : nil,
            approvalKind: command.approveSignoff ? .automated : nil,
            createdAt: Date(),
            processConfiguration: package?.processConfiguration,
            layoutTech: resolvedLayoutTech
        )

        let result = try await runRoundTrip(DesignFlowRoundTripRequest(
            schematic: design.schematic,
            configuration: configuration
        ))
        return DesignFlowCommandResult(
            kind: command.kind,
            designName: design.name,
            runID: runID,
            projectRootPath: projectRoot.path(percentEncoded: false),
            manifestPath: result.manifestURL.path(percentEncoded: false),
            readyForPEX: result.manifest.isReadyForPEX,
            pexCornerID: pexInput.ir.cornerID,
            pexElementCount: pexInput.ir.elements.count,
            comparisonLimitsConfigured: limits != nil,
            bottleneckSummary: result.manifest.bottleneckSummary,
            technologyPackageID: package?.manifest.packageID,
            technologyPackagePath: package?.manifestURL.path(percentEncoded: false)
        )
    }

    @MainActor
    private func runFixtureRoundTrip(_ command: DesignFlowCommand) async throws -> DesignFlowCommandResult {
        let fixture = try fixture(for: command)
        let runID = command.runID ?? "\(fixture.name)-\(Self.timestamp())"
        try HeadlessRoundTripService.validateRunID(runID)
        try validateSignoffLogPair(in: command)
        let limits = try comparisonLimits(from: command)
        let package = try technologyPackage(for: command)

        let pexInput: DesignFlowPEXInput
        if let pexManifestPath = command.pexManifestPath {
            pexInput = try loadPEXInput(
                manifestURL: URL(filePath: pexManifestPath),
                cornerID: command.pexCornerID ?? "tt_25c_1v0"
            )
        } else if let package, let packagePEXManifestPath = package.manifest.pex?.savedManifestPath {
            pexInput = try loadPEXInput(
                manifestURL: package.resolvedURL(for: packagePEXManifestPath),
                cornerID: command.pexCornerID ?? package.manifest.pex?.defaultCornerID ?? "tt_25c_1v0"
            )
        } else {
            pexInput = DesignFlowPEXInput(ir: fixture.pexIR, artifactPaths: [])
        }

        let externalSignoffReview = try await loadExternalSignoffReview(from: command, package: package)
        let projectRoot = URL(filePath: command.projectRootPath ?? defaultCommandProjectRoot(fixtureName: fixture.name))
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let resolvedLayoutTech = try package.map { try layoutTech(for: $0) }

        let configuration = HeadlessRoundTripService.Configuration(
            projectRoot: projectRoot,
            runID: runID,
            title: fixture.title,
            testbench: fixture.testbench,
            postLayoutCommand: fixture.postLayoutCommand,
            pexIR: pexInput.ir,
            designArtifactPaths: designArtifactPaths(designSpecPath: nil, technologyPackage: package),
            pexArtifactPaths: pexInput.artifactPaths,
            postLayoutComparisonLimits: limits,
            externalSignoffCommands: [],
            externalSignoffReview: externalSignoffReview,
            approvedBy: command.approveSignoff ? "design-flow-command" : nil,
            approvedAt: command.approveSignoff ? Date() : nil,
            approvalKind: command.approveSignoff ? .automated : nil,
            createdAt: Date(),
            processConfiguration: package?.processConfiguration,
            layoutTech: resolvedLayoutTech
        )

        let result = try await runRoundTrip(DesignFlowRoundTripRequest(
            schematic: fixture.schematic,
            configuration: configuration
        ))
        return DesignFlowCommandResult(
            kind: command.kind,
            fixtureName: fixture.name,
            runID: runID,
            projectRootPath: projectRoot.path(percentEncoded: false),
            manifestPath: result.manifestURL.path(percentEncoded: false),
            readyForPEX: result.manifest.isReadyForPEX,
            pexCornerID: pexInput.ir.cornerID,
            pexElementCount: pexInput.ir.elements.count,
            comparisonLimitsConfigured: limits != nil,
            bottleneckSummary: result.manifest.bottleneckSummary,
            technologyPackageID: package?.manifest.packageID,
            technologyPackagePath: package?.manifestURL.path(percentEncoded: false)
        )
    }

    @MainActor
    private func fixture(for command: DesignFlowCommand) throws -> DesignFlowFixture {
        guard let fixtureName = command.fixtureName else {
            throw DesignFlowCommandError.missingFixtureName
        }
        return try DesignFlowFixtureLibrary.fixture(named: fixtureName)
    }

    private func validateSignoffLogPair(in command: DesignFlowCommand) throws {
        switch (command.signoffDRCLogPath, command.signoffLVSLogPath) {
        case (nil, nil), (.some, .some):
            return
        case (.some, nil), (nil, .some):
            throw DesignFlowCommandError.incompleteSignoffLogPair
        }
    }

    private func technologyPackage(for command: DesignFlowCommand) throws -> TechnologyPackage? {
        guard let path = command.technologyPackagePath else {
            return nil
        }
        return try loadTechnologyPackage(URL(filePath: path))
    }

    func requiredTechnologyPackage(for command: DesignFlowCommand) throws -> TechnologyPackage {
        guard let package = try technologyPackage(for: command) else {
            throw DesignFlowCommandError.missingTechnologyPackagePath
        }
        return package
    }

    func layoutTech(for package: TechnologyPackage) throws -> LayoutTechDatabase {
        return try TechnologyPackageLayoutTechResolver().resolve(package: package)
    }

    private func designArtifactPaths(
        designSpecPath: String?,
        technologyPackage: TechnologyPackage?
    ) -> [String] {
        var paths: [String] = []
        if let designSpecPath {
            paths.append(designSpecPath)
        }
        if let technologyPackage {
            paths.append(technologyPackage.manifestURL.path(percentEncoded: false))
            if let processTechnologyPath = technologyPackage.manifest.processTechnologyPath {
                paths.append(technologyPackage.resolvedURL(for: processTechnologyPath).path(percentEncoded: false))
            }
            if let goldenLayoutManifestPath = technologyPackage.manifest.corpus?.goldenLayoutManifestPath {
                paths.append(technologyPackage.resolvedURL(for: goldenLayoutManifestPath).path(percentEncoded: false))
            }
        }
        return paths
    }

    private func comparisonLimits(from command: DesignFlowCommand) throws -> PostLayoutComparisonLimits? {
        let domainLimits = command.domainComparisonLimits ?? []
        let variableLimits = command.variableComparisonLimits ?? []
        let oscillationMetricLimits = command.oscillationMetricLimits ?? []
        guard command.maxAbsoluteDelta != nil
            || command.maxRelativeDelta != nil
            || command.relativeDeltaDenominatorFloor != nil
            || !domainLimits.isEmpty
            || !variableLimits.isEmpty
            || !oscillationMetricLimits.isEmpty else {
            return nil
        }
        let limits = PostLayoutComparisonLimits(
            maxAbsoluteDelta: command.maxAbsoluteDelta,
            maxRelativeDelta: command.maxRelativeDelta,
            relativeDeltaDenominatorFloor: command.relativeDeltaDenominatorFloor,
            domainLimits: domainLimits,
            variableLimits: variableLimits,
            oscillationMetricLimits: oscillationMetricLimits
        )
        let diagnostics = limits.validationDiagnostics()
        guard diagnostics.isEmpty else {
            throw DesignFlowCommandError.invalidComparisonLimits(diagnostics)
        }
        return limits
    }

    private func loadExternalSignoffReview(
        from command: DesignFlowCommand,
        package: TechnologyPackage? = nil
    ) async throws -> ExternalSignoffReview? {
        switch (command.signoffDRCLogPath, command.signoffLVSLogPath) {
        case (nil, nil):
            guard let package, let signoff = package.manifest.signoff else {
                return nil
            }
            guard let drc = signoff.drc, let lvs = signoff.lvs,
                  let drcLogPath = drc.replayLogPath,
                  let lvsLogPath = lvs.replayLogPath else {
                return nil
            }
            let adapter = try SignoffAdapterFactory().replayAdapter(adapterID: signoff.adapterID)
            return try await adapter.run(request: SignoffAdapterRequest(
                replayLogs: [
                ExternalSignoffLogArtifact(
                    kind: .drc,
                    toolName: drc.toolName,
                    logURL: package.resolvedURL(for: drcLogPath),
                    success: drc.expectedSuccess
                ),
                ExternalSignoffLogArtifact(
                    kind: .lvs,
                    toolName: lvs.toolName,
                    logURL: package.resolvedURL(for: lvsLogPath),
                    success: lvs.expectedSuccess
                ),
                ],
                artifactDirectory: package.rootURL
            ))
        case (.some(let drcPath), .some(let lvsPath)):
            return try loadExternalSignoffReview(logs: [
                ExternalSignoffLogArtifact(
                    kind: .drc,
                    toolName: "imported-drc",
                    logURL: URL(filePath: drcPath),
                    success: true
                ),
                ExternalSignoffLogArtifact(
                    kind: .lvs,
                    toolName: "imported-lvs",
                    logURL: URL(filePath: lvsPath),
                    success: true
                ),
            ])
        case (.some, nil), (nil, .some):
            throw DesignFlowCommandError.incompleteSignoffLogPair
        }
    }

    private func design(for command: DesignFlowCommand) throws -> DesignFlowDesignSpec.BuiltDesign {
        guard let designSpecPath = command.designSpecPath else {
            throw DesignFlowCommandError.missingDesignSpecPath
        }
        return try loadDesignSpec(URL(filePath: designSpecPath)).build()
    }

    @MainActor
    private func verificationDesign(for command: DesignFlowCommand) throws -> DesignFlowVerificationInput {
        if command.designSpecPath != nil {
            let design = try design(for: command)
            return DesignFlowVerificationInput(
                schematic: design.schematic,
                fixtureName: nil,
                designName: design.name
            )
        }
        if command.fixtureName != nil {
            let fixture = try fixture(for: command)
            return DesignFlowVerificationInput(
                schematic: fixture.schematic,
                fixtureName: fixture.name,
                designName: nil
            )
        }
        throw DesignFlowCommandError.missingVerificationDesignInput
    }

    private func verificationDesignUnit(
        provided: DesignUnit?,
        schematic: SchematicDocument,
        layout: LayoutDocument
    ) -> DesignUnit {
        let currentHash = DesignUnit.schematicHash(for: schematic)
        guard provided?.schematicHash != currentHash else {
            return provided ?? DesignUnit(schematicHash: currentHash)
        }

        guard let topCellID = layout.topCellID,
              let topCell = layout.cell(withID: topCellID) else {
            return DesignUnit(
                componentToInstance: [:],
                netNameToLayoutNet: [:],
                deviceKindToCell: provided?.deviceKindToCell ?? [:],
                schematicHash: currentHash
            )
        }

        let instancesByName = Dictionary(
            topCell.instances.map { ($0.name, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        let componentToInstance = Dictionary(
            uniqueKeysWithValues: schematic.components.compactMap { component in
                instancesByName[component.name].map { (component.id, $0) }
            }
        )
        let netNameToLayoutNet = Dictionary(
            topCell.nets.map { ($0.name, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        return DesignUnit(
            componentToInstance: componentToInstance,
            netNameToLayoutNet: netNameToLayoutNet,
            deviceKindToCell: provided?.deviceKindToCell ?? [:],
            schematicHash: currentHash
        )
    }

}
