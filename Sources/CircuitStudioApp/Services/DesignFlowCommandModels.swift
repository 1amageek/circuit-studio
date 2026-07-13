import Foundation
import CircuitStudioCore
import CircuitPhysicalDesign
import CoreSpiceWaveform
import LayoutCore
import LayoutTech
import LayoutEngine
import Xcircuite
import DesignFlowKernel

public struct DesignFlowSPICESimulationRequest: Sendable {
    public let source: String
    public let fileName: String?
    public let processConfiguration: ProcessConfiguration?
    public let onWaveformUpdate: (@Sendable (WaveformData) -> Void)?

    public init(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration? = nil,
        onWaveformUpdate: (@Sendable (WaveformData) -> Void)? = nil
    ) {
        self.source = source
        self.fileName = fileName
        self.processConfiguration = processConfiguration
        self.onWaveformUpdate = onWaveformUpdate
    }
}

public struct DesignFlowSchematicSimulationRequest: Sendable {
    public let schematic: SchematicDocument
    public let library: CellLibrary
    public let title: String?
    public let testbench: Testbench
    public let processConfiguration: ProcessConfiguration?
    public let onWaveformUpdate: (@Sendable (WaveformData) -> Void)?

    public init(
        schematic: SchematicDocument,
        library: CellLibrary = CellLibrary(),
        title: String? = nil,
        testbench: Testbench,
        processConfiguration: ProcessConfiguration? = nil,
        onWaveformUpdate: (@Sendable (WaveformData) -> Void)? = nil
    ) {
        self.schematic = schematic
        self.library = library
        self.title = title
        self.testbench = testbench
        self.processConfiguration = processConfiguration
        self.onWaveformUpdate = onWaveformUpdate
    }
}

public struct DesignFlowSchematicSimulationResult: Sendable {
    public let netlist: String
    public let simulationResult: SimulationResult

    public init(netlist: String, simulationResult: SimulationResult) {
        self.netlist = netlist
        self.simulationResult = simulationResult
    }
}

public struct DesignFlowNetlistRequest: Sendable {
    public let schematic: SchematicDocument
    public let library: CellLibrary
    public let title: String?
    public let testbench: Testbench?
    public let processConfiguration: ProcessConfiguration?

    public init(
        schematic: SchematicDocument,
        library: CellLibrary = CellLibrary(),
        title: String? = nil,
        testbench: Testbench? = nil,
        processConfiguration: ProcessConfiguration? = nil
    ) {
        self.schematic = schematic
        self.library = library
        self.title = title
        self.testbench = testbench
        self.processConfiguration = processConfiguration
    }
}

public struct DesignFlowLayoutGenerationRequest: Sendable {
    public let schematic: SchematicDocument
    public let catalog: DeviceCatalog
    public let tech: LayoutTechDatabase?
    public let placementStrategy: PlacementEngineSelection
    public let routingStrategy: RoutingEngineSelection
    public let constraints: [LayoutConstraint]

    public init(
        schematic: SchematicDocument,
        catalog: DeviceCatalog = .standard(),
        tech: LayoutTechDatabase? = nil,
        placementStrategy: PlacementEngineSelection = .greedy,
        routingStrategy: RoutingEngineSelection = .simple,
        constraints: [LayoutConstraint] = []
    ) {
        self.schematic = schematic
        self.catalog = catalog
        self.tech = tech
        self.placementStrategy = placementStrategy
        self.routingStrategy = routingStrategy
        self.constraints = constraints
    }
}

public struct DesignFlowPrePEXVerificationRequest: Sendable {
    public let schematic: SchematicDocument
    public let layout: LayoutDocument
    public let tech: LayoutTechDatabase
    public let designUnit: DesignUnit?
    public let catalog: DeviceCatalog
    public let externalSignoff: ExternalSignoffReview?

    public init(
        schematic: SchematicDocument,
        layout: LayoutDocument,
        tech: LayoutTechDatabase,
        designUnit: DesignUnit?,
        catalog: DeviceCatalog = .standard(),
        externalSignoff: ExternalSignoffReview? = nil
    ) {
        self.schematic = schematic
        self.layout = layout
        self.tech = tech
        self.designUnit = designUnit
        self.catalog = catalog
        self.externalSignoff = externalSignoff
    }
}

public struct DesignFlowPostLayoutSimulationRequest: Sendable {
    public let baseNetlist: String
    public let parasitics: PEXParasiticIR
    public let command: AnalysisCommand
    public let processConfiguration: ProcessConfiguration?

    public init(
        baseNetlist: String,
        parasitics: PEXParasiticIR,
        command: AnalysisCommand,
        processConfiguration: ProcessConfiguration? = nil
    ) {
        self.baseNetlist = baseNetlist
        self.parasitics = parasitics
        self.command = command
        self.processConfiguration = processConfiguration
    }
}

public struct DesignFlowRoundTripRequest {
    public let schematic: SchematicDocument
    public let configuration: HeadlessRoundTripService.Configuration

    public init(
        schematic: SchematicDocument,
        configuration: HeadlessRoundTripService.Configuration
    ) {
        self.schematic = schematic
        self.configuration = configuration
    }
}

public struct DesignFlowPEXInput: Sendable, Hashable {
    public let ir: PEXParasiticIR
    public let artifactPaths: [String]

    public init(ir: PEXParasiticIR, artifactPaths: [String]) {
        self.ir = ir
        self.artifactPaths = artifactPaths
    }
}

public struct DesignFlowPEXExtractionRequest: Sendable, Hashable {
    public let configURL: URL
    public let workingDirectory: URL?
    public let cornerID: String
    public let executablePath: String?
    public let additionalArguments: [String]

    public init(
        configURL: URL,
        workingDirectory: URL? = nil,
        cornerID: String = "tt_25c_1v0",
        executablePath: String? = nil,
        additionalArguments: [String] = []
    ) {
        self.configURL = configURL
        self.workingDirectory = workingDirectory
        self.cornerID = cornerID
        self.executablePath = executablePath
        self.additionalArguments = additionalArguments
    }
}

struct DesignFlowVerificationInput {
    let schematic: SchematicDocument
    let fixtureName: String?
    let designName: String?
}

public struct DesignFlowCommand: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case listFixtures
        case generateFixtureNetlist
        case runFixtureSimulation
        case runFixtureRoundTrip
        case generateDesignNetlist
        case runDesignSimulation
        case runDesignRoundTrip
        case summarizeBottlenecks
        case summarizeSignoffRepairCandidateCycles
        case qualifySignoffRepairCandidateCycles
        case loadTechnologyPackage
        case runPEXExtraction
        case inspectTimingModelProfiles
        case buildTimingLibrary
        case applyDesignEdit
        case applyLayoutEdit
        case runLayoutTrust
        case runVerification
        case approveGate
        case reviewRoundTrip
        case selectFailureSuggestedCommand
        case runSelectedSuggestedCommand
        case applyWaiverEditProposal
        case runPostWaiverEditVerification
        case applyWaiverEditProposalAndRunPostVerification
        case formulateSignoffRepairPlanningProblem
        case runSignoffRepairCandidateCycle
        case runGoalLayoutAgent
        case scaffoldDesignSpec
    }

    public let kind: Kind
    public let fixtureName: String?
    public let designSpecPath: String?
    public let projectRootPath: String?
    public let runID: String?
    public let approveSignoff: Bool
    public let pexManifestPath: String?
    public let pexCornerID: String?
    public let signoffDRCLogPath: String?
    public let signoffLVSLogPath: String?
    public let maxAbsoluteDelta: Double?
    public let maxRelativeDelta: Double?
    public let relativeDeltaDenominatorFloor: Double?
    public let domainComparisonLimits: [PostLayoutSignalDomainComparisonLimit]?
    public let variableComparisonLimits: [CircuitStudioCore.PostLayoutVariableComparisonLimit]?
    public let oscillationMetricLimits: [PostLayoutOscillationMetricLimit]?
    public let technologyPackagePath: String?
    public let pexConfigPath: String?
    public let pexExecutablePath: String?
    public let timingModelProfilePath: String?
    public let timingModelProfileCatalogPath: String?
    public let timingModelProfileID: String?
    public let timingModelCornerID: String?
    public let editScriptPath: String?
    public let outputDesignSpecPath: String?
    public let layoutDocumentPath: String?
    public let outputLayoutDocumentPath: String?
    public let designUnitPath: String?
    public let roundTripManifestPath: String?
    public let failureEnvelopePath: String?
    public let suggestedCommandID: String?
    public let approvalGateID: FlowGateID?
    public let approvalTargetPath: String?
    public let approvalReviewer: String?
    public let approvalDecision: GateApprovalDecision?
    public let approvalPolicy: String?
    public let approvalNote: String?
    public let waiverIDs: [String]
    public let waiverReviewID: String?
    public let waiverProposalID: String?
    public let actionActorKind: XcircuiteRunActionActor.Kind?
    public let drcRepairHintPath: String?
    public let lvsRepairHintPath: String?
    public let planningFormulationID: String?
    public let planningIntentID: String?
    public let planningIntent: String?
    public let planningProblemID: String?
    public let candidateStrategy: String?
    public let candidateVerificationMode: String?
    public let signoffRepairHistoryQualificationProfilePath: String?
    public let signoffRepairHistoryMinimumRunCount: Int?
    public let signoffRepairHistoryMinimumCycleCount: Int?
    public let signoffRepairHistoryMinimumAcceptedCount: Int?
    public let signoffRepairHistoryMinimumFeedbackRankChangeCount: Int?
    public let signoffRepairHistoryMinimumFeedbackScoreDeltaCount: Int?
    public let signoffRepairHistoryMinimumAcceptedCountPerSelectedObjectiveDomain: Int?
    public let signoffRepairHistoryRequiredSelectedActionDomainIDs: [String]?
    public let signoffRepairHistoryRequiredSelectedObjectiveDomainIDs: [String]?
    /// `.subckt` intent file for `runGoalLayoutAgent`.
    public let intentSubcktPath: String?
    /// Design (top cell) name for `runGoalLayoutAgent`; defaults to the
    /// `.subckt` header name when absent.
    public let designName: String?

    public init(
        kind: Kind,
        fixtureName: String? = nil,
        designSpecPath: String? = nil,
        projectRootPath: String? = nil,
        runID: String? = nil,
        approveSignoff: Bool = false,
        pexManifestPath: String? = nil,
        pexCornerID: String? = nil,
        signoffDRCLogPath: String? = nil,
        signoffLVSLogPath: String? = nil,
        maxAbsoluteDelta: Double? = nil,
        maxRelativeDelta: Double? = nil,
        relativeDeltaDenominatorFloor: Double? = nil,
        domainComparisonLimits: [PostLayoutSignalDomainComparisonLimit] = [],
        variableComparisonLimits: [CircuitStudioCore.PostLayoutVariableComparisonLimit] = [],
        oscillationMetricLimits: [PostLayoutOscillationMetricLimit] = [],
        technologyPackagePath: String? = nil,
        pexConfigPath: String? = nil,
        pexExecutablePath: String? = nil,
        timingModelProfilePath: String? = nil,
        timingModelProfileCatalogPath: String? = nil,
        timingModelProfileID: String? = nil,
        timingModelCornerID: String? = nil,
        editScriptPath: String? = nil,
        outputDesignSpecPath: String? = nil,
        layoutDocumentPath: String? = nil,
        outputLayoutDocumentPath: String? = nil,
        designUnitPath: String? = nil,
        roundTripManifestPath: String? = nil,
        failureEnvelopePath: String? = nil,
        suggestedCommandID: String? = nil,
        approvalGateID: FlowGateID? = nil,
        approvalTargetPath: String? = nil,
        approvalReviewer: String? = nil,
        approvalDecision: GateApprovalDecision? = nil,
        approvalPolicy: String? = nil,
        approvalNote: String? = nil,
        waiverIDs: [String] = [],
        waiverReviewID: String? = nil,
        waiverProposalID: String? = nil,
        actionActorKind: XcircuiteRunActionActor.Kind? = nil,
        drcRepairHintPath: String? = nil,
        lvsRepairHintPath: String? = nil,
        planningFormulationID: String? = nil,
        planningIntentID: String? = nil,
        planningIntent: String? = nil,
        planningProblemID: String? = nil,
        candidateStrategy: String? = nil,
        candidateVerificationMode: String? = nil,
        signoffRepairHistoryQualificationProfilePath: String? = nil,
        signoffRepairHistoryMinimumRunCount: Int? = nil,
        signoffRepairHistoryMinimumCycleCount: Int? = nil,
        signoffRepairHistoryMinimumAcceptedCount: Int? = nil,
        signoffRepairHistoryMinimumFeedbackRankChangeCount: Int? = nil,
        signoffRepairHistoryMinimumFeedbackScoreDeltaCount: Int? = nil,
        signoffRepairHistoryMinimumAcceptedCountPerSelectedObjectiveDomain: Int? = nil,
        signoffRepairHistoryRequiredSelectedActionDomainIDs: [String]? = nil,
        signoffRepairHistoryRequiredSelectedObjectiveDomainIDs: [String]? = nil,
        intentSubcktPath: String? = nil,
        designName: String? = nil
    ) {
        self.kind = kind
        self.fixtureName = fixtureName
        self.designSpecPath = designSpecPath
        self.projectRootPath = projectRootPath
        self.runID = runID
        self.approveSignoff = approveSignoff
        self.pexManifestPath = pexManifestPath
        self.pexCornerID = pexCornerID
        self.signoffDRCLogPath = signoffDRCLogPath
        self.signoffLVSLogPath = signoffLVSLogPath
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
        self.relativeDeltaDenominatorFloor = relativeDeltaDenominatorFloor
        self.domainComparisonLimits = domainComparisonLimits.isEmpty ? nil : domainComparisonLimits
        self.variableComparisonLimits = variableComparisonLimits.isEmpty ? nil : variableComparisonLimits
        self.oscillationMetricLimits = oscillationMetricLimits.isEmpty ? nil : oscillationMetricLimits
        self.technologyPackagePath = technologyPackagePath
        self.pexConfigPath = pexConfigPath
        self.pexExecutablePath = pexExecutablePath
        self.timingModelProfilePath = timingModelProfilePath
        self.timingModelProfileCatalogPath = timingModelProfileCatalogPath
        self.timingModelProfileID = timingModelProfileID
        self.timingModelCornerID = timingModelCornerID
        self.editScriptPath = editScriptPath
        self.outputDesignSpecPath = outputDesignSpecPath
        self.layoutDocumentPath = layoutDocumentPath
        self.outputLayoutDocumentPath = outputLayoutDocumentPath
        self.designUnitPath = designUnitPath
        self.roundTripManifestPath = roundTripManifestPath
        self.failureEnvelopePath = failureEnvelopePath
        self.suggestedCommandID = suggestedCommandID
        self.approvalGateID = approvalGateID
        self.approvalTargetPath = approvalTargetPath
        self.approvalReviewer = approvalReviewer
        self.approvalDecision = approvalDecision
        self.approvalPolicy = approvalPolicy
        self.approvalNote = approvalNote
        self.waiverIDs = waiverIDs
        self.waiverReviewID = waiverReviewID
        self.waiverProposalID = waiverProposalID
        self.actionActorKind = actionActorKind
        self.drcRepairHintPath = drcRepairHintPath
        self.lvsRepairHintPath = lvsRepairHintPath
        self.planningFormulationID = planningFormulationID
        self.planningIntentID = planningIntentID
        self.planningIntent = planningIntent
        self.planningProblemID = planningProblemID
        self.candidateStrategy = candidateStrategy
        self.candidateVerificationMode = candidateVerificationMode
        self.signoffRepairHistoryQualificationProfilePath = signoffRepairHistoryQualificationProfilePath
        self.signoffRepairHistoryMinimumRunCount = signoffRepairHistoryMinimumRunCount
        self.signoffRepairHistoryMinimumCycleCount = signoffRepairHistoryMinimumCycleCount
        self.signoffRepairHistoryMinimumAcceptedCount = signoffRepairHistoryMinimumAcceptedCount
        self.signoffRepairHistoryMinimumFeedbackRankChangeCount = signoffRepairHistoryMinimumFeedbackRankChangeCount
        self.signoffRepairHistoryMinimumFeedbackScoreDeltaCount = signoffRepairHistoryMinimumFeedbackScoreDeltaCount
        self.signoffRepairHistoryMinimumAcceptedCountPerSelectedObjectiveDomain =
            signoffRepairHistoryMinimumAcceptedCountPerSelectedObjectiveDomain
        self.signoffRepairHistoryRequiredSelectedActionDomainIDs =
            signoffRepairHistoryRequiredSelectedActionDomainIDs
        self.signoffRepairHistoryRequiredSelectedObjectiveDomainIDs =
            signoffRepairHistoryRequiredSelectedObjectiveDomainIDs
        self.intentSubcktPath = intentSubcktPath
        self.designName = designName
    }

    public static func listFixtures() -> DesignFlowCommand {
        DesignFlowCommand(kind: .listFixtures)
    }
}

public struct DesignFlowCommandResult: Sendable, Hashable, Codable {
    public let kind: DesignFlowCommand.Kind
    public let fixtureNames: [String]
    public let fixtureName: String?
    public let designName: String?
    public let runID: String?
    public let netlist: String?
    public let simulationStatus: String?
    public let projectRootPath: String?
    public let manifestPath: String?
    public let readyForPEX: Bool?
    public let pexCornerID: String?
    public let pexElementCount: Int?
    public let comparisonLimitsConfigured: Bool?
    public let pexManifestPath: String?
    public let bottleneckSummary: HeadlessRoundTripService.BottleneckSummary?
    public let bottleneckHistory: RoundTripBottleneckHistoryService.Summary?
    public let signoffRepairCandidateCycleHistoryIndex: RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary?
    public let signoffRepairCandidateCycleHistoryQualification:
        RunReviewSignoffRepairCandidateCycleHistoryQualificationService.Report?
    public let signoffRepairCandidateCycleHistoryQualificationArtifact: XcircuiteFileReference?
    public let signoffRepairCandidateCycleHistoryQualificationPath: String?
    public let technologyPackageID: String?
    public let technologyPackagePath: String?
    public let timingArtifactManifestPath: String?
    public let timingLibraryPath: String?
    public let timingModelProfileSelectionPath: String?
    public let timingModelProfileID: String?
    public let timingModelProfilePath: String?
    public let timingModelProfileCatalogID: String?
    public let timingModelProfileCatalogPath: String?
    public let timingModelProfileCatalogInspection: TimingModelProfileCatalogInspection?
    public let timingModelCornerID: String?
    public let validationDiagnostics: [TechnologyPackageValidationReport.Diagnostic]?
    public let designSpecPath: String?
    public let layoutDocumentPath: String?
    public let actionLogPath: String?
    public let designDiffPath: String?
    public let layoutDiffPath: String?
    public let layoutTrustPassed: Bool?
    public let layoutTrustReportPath: String?
    public let layoutTrustReport: LayoutTrustReport?
    public let verificationReportPath: String?
    public let verificationReport: DesignFlowVerificationReport?
    public let approvalRecordPath: String?
    public let approvalRecord: GateApprovalRecord?
    public let roundTripReview: RoundTripReviewSummary?
    public let selectedSuggestedCommand: XcircuiteSuggestedCommandSelection?
    public let signoffRepairPlanningResult: RunReviewSignoffRepairPlanningResult?
    public let signoffRepairCandidateCycleResult: RunReviewSignoffRepairCandidateCycleResult?
    public let signoffRepairCandidateCycleHistorySummary: RunReviewSignoffRepairCandidateCycleHistorySummary?
    public let actionDomainPath: String?
    public let repairFormulationPath: String?
    public let planningProblemPath: String?
    public let candidatePlanPath: String?
    public let planExecutionPath: String?
    public let planVerificationPath: String?
    public let rejectedPlansPath: String?
    public let candidateCycleHistorySummaryPath: String?
    public let candidateAccepted: Bool?
    public let actionRecordIDs: [String]?
    /// `runGoalLayoutAgent`: whether the intent closed (wired, clean,
    /// LVS-matched, replay-deterministic).
    public let goalAgentClosed: Bool?
    /// `runGoalLayoutAgent`: path of the persisted evidence JSON.
    public let goalAgentEvidencePath: String?
    /// `runGoalLayoutAgent`: path of the exported GDS artifact.
    public let exportedLayoutPath: String?
    public let message: String?

    public init(
        kind: DesignFlowCommand.Kind,
        fixtureNames: [String] = [],
        fixtureName: String? = nil,
        designName: String? = nil,
        runID: String? = nil,
        netlist: String? = nil,
        simulationStatus: String? = nil,
        projectRootPath: String? = nil,
        manifestPath: String? = nil,
        readyForPEX: Bool? = nil,
        pexCornerID: String? = nil,
        pexElementCount: Int? = nil,
        comparisonLimitsConfigured: Bool? = nil,
        pexManifestPath: String? = nil,
        bottleneckSummary: HeadlessRoundTripService.BottleneckSummary? = nil,
        bottleneckHistory: RoundTripBottleneckHistoryService.Summary? = nil,
        signoffRepairCandidateCycleHistoryIndex: RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary? = nil,
        signoffRepairCandidateCycleHistoryQualification:
            RunReviewSignoffRepairCandidateCycleHistoryQualificationService.Report? = nil,
        signoffRepairCandidateCycleHistoryQualificationArtifact: XcircuiteFileReference? = nil,
        signoffRepairCandidateCycleHistoryQualificationPath: String? = nil,
        technologyPackageID: String? = nil,
        technologyPackagePath: String? = nil,
        timingArtifactManifestPath: String? = nil,
        timingLibraryPath: String? = nil,
        timingModelProfileSelectionPath: String? = nil,
        timingModelProfileID: String? = nil,
        timingModelProfilePath: String? = nil,
        timingModelProfileCatalogID: String? = nil,
        timingModelProfileCatalogPath: String? = nil,
        timingModelProfileCatalogInspection: TimingModelProfileCatalogInspection? = nil,
        timingModelCornerID: String? = nil,
        validationDiagnostics: [TechnologyPackageValidationReport.Diagnostic]? = nil,
        designSpecPath: String? = nil,
        layoutDocumentPath: String? = nil,
        actionLogPath: String? = nil,
        designDiffPath: String? = nil,
        layoutDiffPath: String? = nil,
        layoutTrustPassed: Bool? = nil,
        layoutTrustReportPath: String? = nil,
        layoutTrustReport: LayoutTrustReport? = nil,
        verificationReportPath: String? = nil,
        verificationReport: DesignFlowVerificationReport? = nil,
        approvalRecordPath: String? = nil,
        approvalRecord: GateApprovalRecord? = nil,
        roundTripReview: RoundTripReviewSummary? = nil,
        selectedSuggestedCommand: XcircuiteSuggestedCommandSelection? = nil,
        signoffRepairPlanningResult: RunReviewSignoffRepairPlanningResult? = nil,
        signoffRepairCandidateCycleResult: RunReviewSignoffRepairCandidateCycleResult? = nil,
        signoffRepairCandidateCycleHistorySummary: RunReviewSignoffRepairCandidateCycleHistorySummary? = nil,
        actionDomainPath: String? = nil,
        repairFormulationPath: String? = nil,
        planningProblemPath: String? = nil,
        candidatePlanPath: String? = nil,
        planExecutionPath: String? = nil,
        planVerificationPath: String? = nil,
        rejectedPlansPath: String? = nil,
        candidateCycleHistorySummaryPath: String? = nil,
        candidateAccepted: Bool? = nil,
        actionRecordIDs: [String]? = nil,
        goalAgentClosed: Bool? = nil,
        goalAgentEvidencePath: String? = nil,
        exportedLayoutPath: String? = nil,
        message: String? = nil
    ) {
        self.kind = kind
        self.fixtureNames = fixtureNames
        self.fixtureName = fixtureName
        self.designName = designName
        self.runID = runID
        self.netlist = netlist
        self.simulationStatus = simulationStatus
        self.projectRootPath = projectRootPath
        self.manifestPath = manifestPath
        self.readyForPEX = readyForPEX
        self.pexCornerID = pexCornerID
        self.pexElementCount = pexElementCount
        self.comparisonLimitsConfigured = comparisonLimitsConfigured
        self.pexManifestPath = pexManifestPath
        self.bottleneckSummary = bottleneckSummary
        self.bottleneckHistory = bottleneckHistory
        self.signoffRepairCandidateCycleHistoryIndex = signoffRepairCandidateCycleHistoryIndex
        self.signoffRepairCandidateCycleHistoryQualification = signoffRepairCandidateCycleHistoryQualification
        self.signoffRepairCandidateCycleHistoryQualificationArtifact =
            signoffRepairCandidateCycleHistoryQualificationArtifact
        self.signoffRepairCandidateCycleHistoryQualificationPath =
            signoffRepairCandidateCycleHistoryQualificationPath
        self.technologyPackageID = technologyPackageID
        self.technologyPackagePath = technologyPackagePath
        self.timingArtifactManifestPath = timingArtifactManifestPath
        self.timingLibraryPath = timingLibraryPath
        self.timingModelProfileSelectionPath = timingModelProfileSelectionPath
        self.timingModelProfileID = timingModelProfileID
        self.timingModelProfilePath = timingModelProfilePath
        self.timingModelProfileCatalogID = timingModelProfileCatalogID
        self.timingModelProfileCatalogPath = timingModelProfileCatalogPath
        self.timingModelProfileCatalogInspection = timingModelProfileCatalogInspection
        self.timingModelCornerID = timingModelCornerID
        self.validationDiagnostics = validationDiagnostics
        self.designSpecPath = designSpecPath
        self.layoutDocumentPath = layoutDocumentPath
        self.actionLogPath = actionLogPath
        self.designDiffPath = designDiffPath
        self.layoutDiffPath = layoutDiffPath
        self.layoutTrustPassed = layoutTrustPassed
        self.layoutTrustReportPath = layoutTrustReportPath
        self.layoutTrustReport = layoutTrustReport
        self.verificationReportPath = verificationReportPath
        self.verificationReport = verificationReport
        self.approvalRecordPath = approvalRecordPath
        self.approvalRecord = approvalRecord
        self.roundTripReview = roundTripReview
        self.selectedSuggestedCommand = selectedSuggestedCommand
        self.signoffRepairPlanningResult = signoffRepairPlanningResult
        self.signoffRepairCandidateCycleResult = signoffRepairCandidateCycleResult
        self.signoffRepairCandidateCycleHistorySummary = signoffRepairCandidateCycleHistorySummary
        self.actionDomainPath = actionDomainPath
        self.repairFormulationPath = repairFormulationPath
        self.planningProblemPath = planningProblemPath
        self.candidatePlanPath = candidatePlanPath
        self.planExecutionPath = planExecutionPath
        self.planVerificationPath = planVerificationPath
        self.rejectedPlansPath = rejectedPlansPath
        self.candidateCycleHistorySummaryPath = candidateCycleHistorySummaryPath
        self.candidateAccepted = candidateAccepted
        self.actionRecordIDs = actionRecordIDs
        self.goalAgentClosed = goalAgentClosed
        self.goalAgentEvidencePath = goalAgentEvidencePath
        self.exportedLayoutPath = exportedLayoutPath
        self.message = message
    }
}

public enum DesignFlowCommandError: Error, LocalizedError, Equatable {
    case missingFixtureName
    case missingDesignSpecPath
    case missingProjectRoot
    case incompleteSignoffLogPair
    case invalidComparisonLimits([String])
    case missingTechnologyPackagePath
    case missingPEXConfigPath
    case missingEditScriptPath
    case missingOutputDesignSpecPath
    case missingLayoutDocumentPath
    case missingOutputLayoutDocumentPath
    case missingVerificationDesignInput
    case missingVerificationReport
    case missingRoundTripManifestPath
    case missingFailureEnvelopePath
    case missingSuggestedCommandID
    case missingApprovalGateID
    case missingApprovalReviewer
    case missingRunID
    case missingWaiverReviewID
    case missingWaiverProposalID
    case conflictingTimingModelProfileSelectors
    case timingModelProfileCatalogEntryMismatch(expected: String, actual: String)
    case timingModelProfileCatalogCornerMismatch(profileID: String, declared: String, actual: String)
    case signoffToolchainUnavailable
    case missingIntentSubcktPath
    case missingIntentSubcktName

    public var errorDescription: String? {
        switch self {
        case .missingFixtureName:
            return "Design flow command requires a fixture name."
        case .missingDesignSpecPath:
            return "Design flow command requires a design spec path."
        case .missingProjectRoot:
            return "Design flow command requires a project root path."
        case .incompleteSignoffLogPair:
            return "Both DRC and LVS signoff log paths are required when importing signoff logs."
        case .invalidComparisonLimits(let diagnostics):
            return diagnostics.joined(separator: "; ")
        case .missingTechnologyPackagePath:
            return "Design flow command requires a technology package path."
        case .missingPEXConfigPath:
            return "Design flow command requires a PEX config path."
        case .missingEditScriptPath:
            return "Design flow command requires a design edit script path."
        case .missingOutputDesignSpecPath:
            return "Design flow command requires an output design spec path."
        case .missingLayoutDocumentPath:
            return "Design flow command requires a layout document path."
        case .missingOutputLayoutDocumentPath:
            return "Design flow command requires an output layout document path."
        case .missingVerificationDesignInput:
            return "Design flow verification requires a design spec path or a fixture name."
        case .missingVerificationReport:
            return "Design flow command expected a verification report artifact but none was produced."
        case .missingRoundTripManifestPath:
            return "Design flow command requires a round-trip manifest path, or a project root path with a run ID."
        case .missingFailureEnvelopePath:
            return "Design flow command requires a failure envelope path."
        case .missingSuggestedCommandID:
            return "Design flow command requires a suggested command ID."
        case .missingApprovalGateID:
            return "Design flow command requires an approval gate ID."
        case .missingApprovalReviewer:
            return "Design flow command requires an approval reviewer."
        case .missingRunID:
            return "Design flow command requires a run ID."
        case .missingWaiverReviewID:
            return "Design flow command requires a waiver review ID."
        case .missingWaiverProposalID:
            return "Design flow command requires a waiver proposal ID."
        case .conflictingTimingModelProfileSelectors:
            return "Design flow command must use either an explicit timing model profile path or a timing model profile catalog selector, not both."
        case .timingModelProfileCatalogEntryMismatch(let expected, let actual):
            return "Timing model profile catalog entry '\(expected)' loaded profile '\(actual)'."
        case .timingModelProfileCatalogCornerMismatch(let profileID, let declared, let actual):
            return "Timing model profile catalog entry '\(profileID)' declares corner '\(declared)' but loaded profile corner is '\(actual)'."
        case .signoffToolchainUnavailable:
            return "Live signoff was requested but the Magic + Netgen + selected PDK toolchain was not found (set MAGIC_BIN/NETGEN_BIN/PDK_ROOT or install the tools)."
        case .missingIntentSubcktPath:
            return "Design flow command requires a .subckt intent path."
        case .missingIntentSubcktName:
            return "The .subckt intent does not declare a subcircuit name; pass an explicit design name."
        }
    }
}
