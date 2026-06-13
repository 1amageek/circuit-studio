import Foundation
import CircuitStudioCore
import CoreSpiceWaveform
import LayoutCore
import LayoutTech

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
    public let placementStrategy: PlacementStrategy
    public let routingStrategy: RoutingStrategy
    public let constraints: [LayoutConstraint]

    public init(
        schematic: SchematicDocument,
        catalog: DeviceCatalog = .standard(),
        tech: LayoutTechDatabase? = nil,
        placementStrategy: PlacementStrategy = .greedy,
        routingStrategy: RoutingStrategy = .simple,
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

private struct DesignFlowVerificationInput {
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
        case loadTechnologyPackage
        case runPEXExtraction
        case applyDesignEdit
        case applyLayoutEdit
        case runLayoutTrust
        case runVerification
        case approveGate
        case reviewRoundTrip
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
    public let variableComparisonLimits: [PostLayoutVariableComparisonLimit]?
    public let oscillationMetricLimits: [PostLayoutOscillationMetricLimit]?
    public let technologyPackagePath: String?
    public let pexConfigPath: String?
    public let pexExecutablePath: String?
    public let editScriptPath: String?
    public let outputDesignSpecPath: String?
    public let layoutDocumentPath: String?
    public let outputLayoutDocumentPath: String?
    public let designUnitPath: String?
    public let roundTripManifestPath: String?
    public let approvalGateID: FlowGateID?
    public let approvalTargetPath: String?
    public let approvalReviewer: String?
    public let approvalDecision: GateApprovalDecision?
    public let approvalPolicy: String?
    public let approvalNote: String?
    public let waiverIDs: [String]

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
        variableComparisonLimits: [PostLayoutVariableComparisonLimit] = [],
        oscillationMetricLimits: [PostLayoutOscillationMetricLimit] = [],
        technologyPackagePath: String? = nil,
        pexConfigPath: String? = nil,
        pexExecutablePath: String? = nil,
        editScriptPath: String? = nil,
        outputDesignSpecPath: String? = nil,
        layoutDocumentPath: String? = nil,
        outputLayoutDocumentPath: String? = nil,
        designUnitPath: String? = nil,
        roundTripManifestPath: String? = nil,
        approvalGateID: FlowGateID? = nil,
        approvalTargetPath: String? = nil,
        approvalReviewer: String? = nil,
        approvalDecision: GateApprovalDecision? = nil,
        approvalPolicy: String? = nil,
        approvalNote: String? = nil,
        waiverIDs: [String] = []
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
        self.editScriptPath = editScriptPath
        self.outputDesignSpecPath = outputDesignSpecPath
        self.layoutDocumentPath = layoutDocumentPath
        self.outputLayoutDocumentPath = outputLayoutDocumentPath
        self.designUnitPath = designUnitPath
        self.roundTripManifestPath = roundTripManifestPath
        self.approvalGateID = approvalGateID
        self.approvalTargetPath = approvalTargetPath
        self.approvalReviewer = approvalReviewer
        self.approvalDecision = approvalDecision
        self.approvalPolicy = approvalPolicy
        self.approvalNote = approvalNote
        self.waiverIDs = waiverIDs
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
    public let technologyPackageID: String?
    public let technologyPackagePath: String?
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
        technologyPackageID: String? = nil,
        technologyPackagePath: String? = nil,
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
        self.technologyPackageID = technologyPackageID
        self.technologyPackagePath = technologyPackagePath
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
    case missingRoundTripManifestPath
    case missingApprovalGateID
    case missingApprovalReviewer
    case signoffToolchainUnavailable

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
        case .missingRoundTripManifestPath:
            return "Design flow command requires a round-trip manifest path, or a project root path with a run ID."
        case .missingApprovalGateID:
            return "Design flow command requires an approval gate ID."
        case .missingApprovalReviewer:
            return "Design flow command requires an approval reviewer."
        case .signoffToolchainUnavailable:
            return "Live signoff was requested but the Magic + Netgen + Sky130 toolchain was not found (set MAGIC_BIN/NETGEN_BIN/PDK_ROOT or install the tools)."
        }
    }
}

public struct DesignFlowService: Sendable {
    private let simulationService: SimulationService
    private let netlistGenerator: NetlistGenerator
    private let layoutTrustEvaluator: any LayoutTrustEvaluating
    private let layoutTrustArtifactWriter: any LayoutTrustArtifactWriting

    public init(
        simulationService: SimulationService = SimulationService(),
        netlistGenerator: NetlistGenerator = NetlistGenerator(),
        layoutTrustEvaluator: any LayoutTrustEvaluating = LayoutTrustEvaluationService(),
        layoutTrustArtifactWriter: any LayoutTrustArtifactWriting = LayoutTrustArtifactWriter()
    ) {
        self.simulationService = simulationService
        self.netlistGenerator = netlistGenerator
        self.layoutTrustEvaluator = layoutTrustEvaluator
        self.layoutTrustArtifactWriter = layoutTrustArtifactWriter
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
    ) throws -> AutoLayoutOutput {
        try AutoLayoutService().generate(
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

    public func comparePostLayout(
        preLayoutResult: SimulationResult,
        postLayoutResult: SimulationResult,
        limits: PostLayoutComparisonLimits? = nil
    ) -> PostLayoutComparisonReport {
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
        try await HeadlessRoundTripService().run(
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

    public func loadDesignSpec(_ url: URL) throws -> DesignFlowDesignSpec {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(DesignFlowDesignSpec.self, from: data)
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
        let package = try technologyPackage(for: command)
        let layout = try loadLayoutDocument(URL(filePath: layoutDocumentPath))
        let tech = try layoutTech(for: package) ?? .sampleProcess()
        let report = try layoutTrustEvaluator.evaluate(document: layout, tech: tech, policy: LayoutOwnershipPolicy())
        let artifactDirectory = layoutTrustArtifactDirectory(for: command)
        let artifacts = try layoutTrustArtifactWriter.write(
            document: layout,
            report: report,
            to: artifactDirectory
        )

        return DesignFlowCommandResult(
            kind: command.kind,
            runID: command.runID,
            projectRootPath: command.projectRootPath,
            technologyPackageID: package?.manifest.packageID,
            technologyPackagePath: package?.manifestURL.path(percentEncoded: false),
            layoutTrustPassed: report.passed,
            layoutTrustReportPath: artifacts.layoutTrustReportPath,
            layoutTrustReport: report,
            message: report.status.rawValue
        )
    }

    @MainActor
    private func runVerification(_ command: DesignFlowCommand) async throws -> DesignFlowCommandResult {
        guard let layoutDocumentPath = command.layoutDocumentPath else {
            throw DesignFlowCommandError.missingLayoutDocumentPath
        }
        let verificationInput = try verificationDesign(for: command)
        let package = try technologyPackage(for: command)
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
        let tech = try layoutTech(for: package) ?? .sampleProcess()
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

        let artifactDirectory = verificationArtifactDirectory(for: command)
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
            technologyPackageID: package?.manifest.packageID,
            technologyPackagePath: package?.manifestURL.path(percentEncoded: false),
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

        let layout = try loadLayoutDocument(URL(filePath: layoutDocumentPath))
        let script = try loadLayoutEditScript(URL(filePath: editScriptPath))
        let result = try DesignFlowLayoutEditService().apply(script: script, to: layout)
        let outputURL = URL(filePath: outputLayoutDocumentPath)
        try writeJSON(result.layout, to: outputURL)

        let artifactDirectory = layoutEditArtifactDirectory(for: command, outputURL: outputURL)
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

        let design = try loadDesignSpec(URL(filePath: designSpecPath))
        let script = try loadDesignEditScript(URL(filePath: editScriptPath))
        let result = try DesignFlowDesignEditService().apply(script: script, to: design)
        let outputURL = URL(filePath: outputDesignSpecPath)
        try writeJSON(result.designSpec, to: outputURL)

        let artifactDirectory = designEditArtifactDirectory(for: command, outputURL: outputURL)
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
            layoutTech: try layoutTech(for: package)
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
            layoutTech: try layoutTech(for: package)
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

    private func requiredTechnologyPackage(for command: DesignFlowCommand) throws -> TechnologyPackage {
        guard let package = try technologyPackage(for: command) else {
            throw DesignFlowCommandError.missingTechnologyPackagePath
        }
        return package
    }

    private func layoutTech(for package: TechnologyPackage?) throws -> LayoutTechDatabase? {
        guard let package else {
            return nil
        }
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

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func writeActionLog(_ actions: [DesignFlowDesignEditAction], to url: URL) throws {
        try writeJSONLines(actions, to: url)
    }

    private func writeLayoutActionLog(_ actions: [DesignFlowLayoutEditAction], to url: URL) throws {
        try writeJSONLines(actions, to: url)
    }

    private func writeJSONLines<T: Encodable>(_ values: [T], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = try values.map { value -> String in
            let data = try encoder.encode(value)
            guard let line = String(data: data, encoding: .utf8) else {
                throw StudioError.projectSaveFailed("Failed to encode action log.")
            }
            return line
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func designEditArtifactDirectory(for command: DesignFlowCommand, outputURL: URL) -> URL {
        let root = command.projectRootPath.map { URL(filePath: $0) }
            ?? outputURL.deletingLastPathComponent()
        let runID = command.runID ?? Self.timestamp()
        return root
            .appending(path: ".xcircuite")
            .appending(path: "design-edits")
            .appending(path: runID)
    }

    private func layoutEditArtifactDirectory(for command: DesignFlowCommand, outputURL: URL) -> URL {
        let root = command.projectRootPath.map { URL(filePath: $0) }
            ?? outputURL.deletingLastPathComponent()
        let runID = command.runID ?? Self.timestamp()
        return root
            .appending(path: ".xcircuite")
            .appending(path: "layout-edits")
            .appending(path: runID)
    }

    private func layoutTrustArtifactDirectory(for command: DesignFlowCommand) -> URL {
        runArtifactDirectory(for: command, fallbackRootName: "layout-trust-runs")
            .appending(path: "layout")
    }

    private func verificationArtifactDirectory(for command: DesignFlowCommand) -> URL {
        runArtifactDirectory(for: command, fallbackRootName: "verification-runs")
    }

    private func runArtifactDirectory(for command: DesignFlowCommand, fallbackRootName: String) -> URL {
        let root = command.projectRootPath.map { URL(filePath: $0) }
            ?? URL(filePath: FileManager.default.currentDirectoryPath)
                .appending(path: fallbackRootName)
        let runID = command.runID ?? Self.timestamp()
        return root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: runID)
    }

    private func defaultCommandProjectRoot(fixtureName: String) -> String {
        URL(filePath: FileManager.default.currentDirectoryPath)
            .appending(path: "round-trip-runs")
            .appending(path: fixtureName)
            .path(percentEncoded: false)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ".", with: "")
    }
}
