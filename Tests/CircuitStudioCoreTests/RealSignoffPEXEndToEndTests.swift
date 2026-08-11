import CircuitSignoff
import CircuiteFoundation
import DesignFlowKernel
import DRCPersistence
import Foundation
import LVSPersistence
import Testing
import PEXEngine
import PEXPersistence
import ToolQualification
import Xcircuite
@testable import CircuitStudioApp
@testable import CircuitStudioCore

/// A5: end-to-end proof that all three real backends run on ONE real layout
/// through circuit-studio's own dependencies — real DRC + real LVS (via
/// DesignFlowService.runLiveSignoff) and real PEX (via the same DefaultPEXEngine
/// the pexengine CLI wraps, backendID=magic). Gated on the toolchain.
@Suite("Real DRC+LVS+PEX end-to-end (gated)")
struct RealSignoffPEXEndToEndTests {

    private static let packageRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let requiredMarker = packageRoot.appending(path: ".build/require-real-tools")
    private static let environmentFile = packageRoot.appending(
        path: ".build/real-tool-environment"
    )
    static let available = ProcessInfo.processInfo.environment[
        "CIRCUIT_STUDIO_REQUIRE_REAL_TOOLS"
    ] == "1"
        || FileManager.default.fileExists(atPath: requiredMarker.path(percentEncoded: false))
        || LiveSignoffService.locate() != nil && MagicToolchain.locate() != nil
    private let topCell = "sky130_fd_sc_hd__inv_1"

    private func lvsFixture(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "lvs"))
    }

    @Test(
        "A real layout passes live DRC+LVS and yields real PEX parasitics",
        .enabled(if: RealSignoffPEXEndToEndTests.available),
        .timeLimit(.minutes(4))
    )
    func fullRealFlow() async throws {
        let toolEnvironment = try Self.loadToolEnvironment()
        let work = FileManager.default.temporaryDirectory
            .appending(path: "RealE2E-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { removeCoreTestTemporaryDirectory(work) }

        let gds = try lvsFixture("inv1", "gds")

        // 1) Real DRC + LVS through the flow's live-signoff entry point.
        let liveSignoff = try #require(
            LiveSignoffService.locate(environment: toolEnvironment)
        )
        let signoffExecution = try await liveSignoff.execute(
            layoutGDS: gds,
            topCell: topCell,
            schematicNetlist: try lvsFixture("inv_schematic", "spice"),
            artifactDirectory: work.appending(path: "signoff")
        )
        #expect(signoffExecution.review.passed, "live DRC+LVS should pass on the clean inv1 layout")

        // 2) Real PEX on the same layout via the default engine (backendID=magic).
        let netlist = try lvsFixture("inv_schematic", "spice")
        let tech = TechnologyIR(
            processName: "sky130A", stack: [], logicalToPhysicalLayerMap: [:],
            vias: [], defaultExtractionRules: .default, backendHints: [:]
        )
        let pexRequest = PEXRunRequest(
            layoutURL: gds,
            layoutFormat: .gds,
            sourceNetlistURL: netlist,
            sourceNetlistFormat: .spice,
            topCell: topCell,
            corners: [PEXCorner(id: "tt")],
            technology: .inline(tech),
            backendSelection: PEXBackendSelection(backendID: "magic"),
            options: PEXRunOptions(
                extractMode: .cOnly, includeCouplingCaps: true,
                minCapacitanceF: nil, minResistanceOhm: nil, maxParallelJobs: 1,
                emitRawArtifacts: true, emitIRJSON: true, strictValidation: false
            ),
            workingDirectory: work.appending(path: "pex")
        )
        let magicToolchain = try #require(
            MagicToolchain.locate(environment: toolEnvironment)
        )
        let pexEngine = DefaultPEXEngine(
            adapterRegistry: PEXAdapterRegistry(
                adapters: [MagicPEXAdapter(toolchain: magicToolchain)]
            ),
            parserRegistry: PEXDefaultParsers.makeRegistry()
        )
        let pexResult = try await pexEngine.run(pexRequest)
        #expect(pexResult.status == .success)
        let ir = try #require(pexResult.cornerResults.first?.ir)
        #expect(ir.metadata["sourceFormat"] == "magic-spice", "PEX must use the real Magic backend")
        #expect(!ir.elements.isEmpty, "an inverter layout should yield real parasitic elements")

        // 3) Retain the engine-owned summaries and a real ngspice comparison in
        // the shared run ledger, then exercise the same review/approval/resume
        // path used by the app.
        let ngspicePath = try #require(toolEnvironment["NGSPICE_BIN"])
        let oracleAgreement = try await PostLayoutOracleService(
            external: ExternalSpiceSimulator(
                runner: NgspiceRunner(executablePath: ngspicePath)
            )
        ).crossCheck(
            deck: Self.oracleDeck,
            command: .tran(TranSpec(stopTime: 32e-9, stepTime: 0.05e-9)),
            probes: ["out"],
            toleranceV: 0.05
        )
        #expect(oracleAgreement.isConsistent)

        let projectRoot = work.appending(path: "review-project")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let runID = "real-tool-review"
        let stageID = "001-real-signoff"
        let rawPrefix = ".xcircuite/runs/\(runID)/stages/\(stageID)/raw"
        let drcSummaryPath = "\(rawPrefix)/drc-summary.json"
        let lvsSummaryPath = "\(rawPrefix)/lvs-summary.json"
        let pexSummaryPath = "\(rawPrefix)/pex-summary.json"
        let simulationSummaryPath = "\(rawPrefix)/simulation-summary.json"
        let oraclePath = "\(rawPrefix)/ngspice-oracle-agreement.json"
        let drcLogPath = "\(rawPrefix)/magic-drc.log"
        let lvsLogPath = "\(rawPrefix)/netgen-lvs.log"
        let profilePath = ".xcircuite/runs/\(runID)/toolchain-profile.json"

        let drcSummaryData = try RunReviewTestSupport.encodedJSONData(
            DRCRunSummaryBuilder().build(result: signoffExecution.drc)
        )
        let lvsSummaryData = try RunReviewTestSupport.encodedJSONData(
            LVSRunSummaryBuilder().build(result: signoffExecution.lvs)
        )
        let pexSummaryData = try RunReviewTestSupport.encodedJSONData(
            PEXRunSummaryBuilder().build(manifestURL: pexResult.manifestURL)
        )
        let simulationSummaryData = try RunReviewTestSupport.encodedJSONData(
            XcircuiteSimulationMetricReport(
                status: oracleAgreement.isConsistent ? "passed" : "failed",
                source: "ngspice-oracle",
                sourceReportPath: oraclePath,
                analysisLabel: "post-layout transient",
                expectations: [],
                measurements: [],
                verdicts: [
                    XcircuiteSimulationMetricReport.MeasurementVerdict(
                        name: "max-absolute-delta-v(out)",
                        status: oracleAgreement.isConsistent ? "passed" : "failed",
                        value: oracleAgreement.maxDivergenceV,
                        target: 0,
                        tolerance: oracleAgreement.toleranceV
                    ),
                ],
                diagnostics: []
            )
        )
        let oracleData = try RunReviewTestSupport.encodedJSONData(oracleAgreement)
        let drcLogData = try Data(
            contentsOf: URL(filePath: signoffExecution.drc.result.logPath)
        )
        let lvsLogData = try Data(
            contentsOf: URL(filePath: signoffExecution.lvs.result.logPath)
        )

        let profile = XcircuiteFlowToolchainProfile(
            profileID: "local-real-signoff",
            pdkID: "sky130A",
            metadata: [
                "magicExecutable": try #require(
                    signoffExecution.drc.result.provenance?.executablePath
                ),
                "netgenExecutable": try #require(
                    signoffExecution.lvs.result.provenance?.executablePath
                ),
                "pdkRoot": try #require(
                    signoffExecution.drc.result.provenance?.pdkRoot
                ),
                "ngspiceCommand": ngspicePath,
            ]
        )
        let profileData = try RunReviewTestSupport.encodedJSONData(profile)
        let profileBinding = try RunReviewTestSupport.artifactBinding(
            artifactID: "flow-toolchain-profile",
            path: profilePath,
            payload: profileData,
            kind: .other,
            format: .json
        )

        let stageArtifacts = try [
            RunReviewTestSupport.artifactBinding(
                artifactID: "drc-summary",
                path: drcSummaryPath,
                payload: drcSummaryData,
                producer: signoffExecution.drc.provenance.producer
            ),
            RunReviewTestSupport.artifactBinding(
                artifactID: "drc-real-tool-log",
                path: drcLogPath,
                payload: drcLogData,
                format: .text,
                producer: signoffExecution.drc.provenance.producer
            ),
            RunReviewTestSupport.artifactBinding(
                artifactID: "lvs-summary",
                path: lvsSummaryPath,
                payload: lvsSummaryData,
                producer: signoffExecution.lvs.provenance.producer
            ),
            RunReviewTestSupport.artifactBinding(
                artifactID: "lvs-real-tool-log",
                path: lvsLogPath,
                payload: lvsLogData,
                format: .text,
                producer: signoffExecution.lvs.provenance.producer
            ),
            RunReviewTestSupport.artifactBinding(
                artifactID: "pex-summary",
                path: pexSummaryPath,
                payload: pexSummaryData,
                producer: pexResult.provenance.producer
            ),
            RunReviewTestSupport.artifactBinding(
                artifactID: "planning-simulation-summary",
                path: simulationSummaryPath,
                payload: simulationSummaryData,
                producer: pexResult.provenance.producer
            ),
            RunReviewTestSupport.artifactBinding(
                artifactID: "ngspice-oracle-agreement",
                path: oraclePath,
                payload: oracleData,
                kind: .measurement,
                format: .json
            ),
        ]
        let stagePayloads = [
            drcSummaryPath: drcSummaryData,
            drcLogPath: drcLogData,
            lvsSummaryPath: lvsSummaryData,
            lvsLogPath: lvsLogData,
            pexSummaryPath: pexSummaryData,
            simulationSummaryPath: simulationSummaryData,
            oraclePath: oracleData,
        ]
        let designDiff = DesignDiff(
            runID: runID,
            title: "Real signoff candidate",
            actor: "real-tool-integration",
            changes: [
                DesignDiffChange(
                    changeID: "retain-inverter-layout",
                    domain: .layout,
                    operation: .replace,
                    path: "/cells/\(topCell)/layout",
                    before: .string("unverified"),
                    after: .string("magic-drc-lvs-pex-verified"),
                    artifacts: stageArtifacts,
                    summary: "Retain the inverter layout verified by the real signoff toolchain."
                ),
            ]
        )
        let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let flowRequest = FlowOperationRequest(
            workspaceID: try await RunReviewTestSupport.workspaceID(projectRoot: projectRoot),
            runID: runID,
            intent: "Review real Magic, Netgen, PEX, and ngspice evidence",
            toolchainProfile: profile.flowToolchainRecord(profileArtifactPath: profilePath),
            stages: [
                FlowStageDefinition(
                    stageID: stageID,
                    displayName: "Real signoff review",
                    requiresApproval: true
                ),
                FlowStageDefinition(stageID: "002-retain", displayName: "Retain approved evidence"),
            ]
        )
        let executors: [any FlowStageExecutor] = [
            RunReviewPassingExecutor(
                stageID: stageID,
                artifacts: stageArtifacts,
                artifactPayloads: stagePayloads
            ),
            RunReviewPassingExecutor(stageID: "002-retain"),
        ]
        let orchestrator = try RunReviewTestSupport.orchestrator(projectRoot: projectRoot)
        let blocked = try await orchestrator.run(
            request: flowRequest,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors,
            artifactPreparer: RunReviewArtifactPreparer(
                workspaceStore: store,
                artifacts: [profileBinding],
                artifactPayloads: [profilePath: profileData],
                designDiff: designDiff
            )
        )
        #expect(blocked.status == .blocked)

        let service = RunReviewService()
        var retainedReview = try await service.loadRun(runID: runID, projectRoot: projectRoot)
        #expect(retainedReview.toolchain.hasContent)
        #expect(retainedReview.toolchain.summary?.profileID == "local-real-signoff")
        #expect(retainedReview.toolchain.summary?.pdkID == "sky130A")
        #expect(!retainedReview.toolchain.hasUnverifiedArtifacts)
        #expect(retainedReview.bundle.artifacts.allSatisfy { $0.integrity?.status == .verified })
        #expect(retainedReview.planning.designDiffSummary?.changeCount == 1)
        #expect(retainedReview.signoff.decodeIssues.isEmpty)
        #expect(Set(retainedReview.signoff.cards.map(\.domain)).isSuperset(of: [
            "DRC", "LVS", "PEX", "Simulation",
        ]))
        #expect(retainedReview.signoff.cards.first { $0.domain == "DRC" }?.passed == true)
        #expect(retainedReview.signoff.cards.first { $0.domain == "LVS" }?.passed == true)
        #expect(retainedReview.signoff.cards.first { $0.domain == "PEX" }?.passed == true)
        #expect(retainedReview.signoff.cards.first { $0.domain == "Simulation" }?.passed == true)

        _ = try await service.decide(
            runID: runID,
            stageID: stageID,
            verdict: .approved,
            reviewer: "real-tool-reviewer",
            note: "Reviewed retained real-tool evidence and verified artifact integrity.",
            projectRoot: projectRoot
        )
        retainedReview = try await service.loadRun(runID: runID, projectRoot: projectRoot)
        let resumeNextAction = try #require(retainedReview.bundle.summary.nextActions.first {
            $0.kind == "resumeRun"
        })
        try await store.appendReviewDecisionAction(
            FlowRunReviewDecisionRequest(
                actionID: "resume-real-tool-review",
                runID: runID,
                stageID: stageID,
                actor: FlowRunActor(kind: .human, identifier: "real-tool-reviewer"),
                decisionKind: .resume,
                decision: "selected",
                targetID: resumeNextAction.actionID,
                reason: resumeNextAction.reason
            )
        )

        var resumeRequest = flowRequest
        resumeRequest.allowExistingRun = true
        let resumed = try await orchestrator.run(
            request: resumeRequest,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(resumed.status == .succeeded)
        retainedReview = try await service.loadRun(runID: runID, projectRoot: projectRoot)
        #expect(retainedReview.status == .succeeded)
        #expect(retainedReview.approvals.first?.verdict == .approved)
        let retainedActions = try await store.loadRunActions(runID: runID)
        #expect(retainedActions.contains {
            $0.actionKind == FlowRunReviewDecisionKind.resume.rawValue
                && $0.context.reviewDecision?.targetID == resumeNextAction.actionID
        })
        #expect(retainedReview.stages.count == 2)
    }

    private static let oracleDeck = """
    * real-tool review oracle: level-1 inverter with extracted-style parasitics
    VDD vdd 0 dc 1.8
    VIN in 0 PULSE(0 1.8 2n 1n 1n 8n 16n)
    MN out in 0 0 NM W=2u L=0.15u
    MP out in vdd vdd PM W=4u L=0.15u
    CL out 0 30f
    CC in out 2f
    .model NM NMOS level=1 vto=0.45 kp=120u lambda=0.1 gamma=0.4 phi=0.65
    .model PM PMOS level=1 vto=-0.45 kp=40u lambda=0.1 gamma=0.4 phi=0.65
    """

    private static func loadToolEnvironment() throws -> [String: String] {
        let data = try Data(contentsOf: environmentFile)
        guard let contents = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        var environment: [String: String] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: "=") else {
                continue
            }
            let key = String(line[..<separator])
            let value = String(line[line.index(after: separator)...])
            environment[key] = value
        }
        return environment
    }
}
