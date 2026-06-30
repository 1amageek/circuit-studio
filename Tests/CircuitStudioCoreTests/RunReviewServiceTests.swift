import Foundation
import Testing
import DesignFlowKernel
import LayoutCore
import ToolQualification
import Xcircuite
import XcircuitePackage
@testable import CircuitStudioApp
@testable import CircuitStudioCore

/// P4 gate: the cockpit and the flow kernel close one loop over one
/// ledger — a run blocks at the approval gate, the reviewer reads the
/// SAME stage results the kernel persisted and records a decision, and
/// re-running the same runID resumes past the gate.
@Suite("Run review service", .timeLimit(.minutes(2)))
struct RunReviewServiceTests {

    @Test func reviewLoopBlocksDecidesAndResumes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { RunReviewTestSupport.removeTemporaryRoot(root) }

        let request = FlowOperationRequest(
            projectRoot: root,
            runID: "run-review",
            intent: "Review loop",
            stages: [
                FlowStageDefinition(stageID: "001-drc", displayName: "DRC", requiresApproval: true),
                FlowStageDefinition(stageID: "002-ship", displayName: "Ship"),
            ]
        )
        let summaryPath = ".xcircuite/runs/run-review/stages/001-drc/raw/drc-summary.json"
        let summaryPayload = Data(#"{"artifactID":"drc-summary"}"#.utf8)
        let executors: [any FlowStageExecutor] = [
            RunReviewPassingExecutor(
                stageID: "001-drc",
                artifacts: [
                    XcircuiteFileReference(
                        artifactID: "drc-summary",
                        path: summaryPath,
                        kind: .report,
                        format: .json
                    ),
                ],
                artifactPayloads: [summaryPath: summaryPayload]
            ),
            RunReviewPassingExecutor(stageID: "002-ship"),
        ]

        // 1. The flow blocks at the approval gate.
        let blocked = try await DefaultFlowOrchestrator().run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(blocked.status == .blocked)

        // 2. The cockpit reads the ledger: one run, one stage awaiting
        //    this reviewer.
        let service = RunReviewService()
        let runs = try service.listRuns(projectRoot: root)
        #expect(runs.map(\.runID) == ["run-review"])

        var review = try service.loadRun(runID: "run-review", projectRoot: root)
        #expect(review.status == .blocked)
        #expect(review.stages.count == 1)
        #expect(review.bundle.reviewItems.contains {
            $0.kind == .approvalGate
                && $0.status == .needsReview
                && $0.stageID == "001-drc"
        })
        #expect(review.bundle.artifacts.contains {
            $0.role == "stage-result"
                && $0.path == ".xcircuite/runs/run-review/stages/001-drc/result.json"
        })
        #expect(review.bundle.artifacts.contains {
            $0.role == "stage-summary"
                && $0.artifactID == "drc-summary"
                && $0.path == summaryPath
                && $0.integrity?.status == .verified
                && $0.integrity?.actualByteCount == Int64(summaryPayload.count)
        })
        let awaiting = try #require(review.stages.first)
        #expect(awaiting.awaitingApproval)
        #expect(awaiting.approval == nil)

        // 3. The reviewer decides; the decision lands in the ledger.
        _ = try service.decide(
            runID: "run-review",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1",
            note: "verified against the report",
            projectRoot: root
        )
        review = try service.loadRun(runID: "run-review", projectRoot: root)
        #expect(review.bundle.reviewItems.contains {
            $0.kind == .approvalGate
                && $0.status == .readyToResume
                && $0.nextActionID == "001-drc-resume-run"
                && $0.artifactPaths.contains(".xcircuite/runs/run-review/approvals/001-drc.json")
        })
        let approvalActions = try XcircuitePackageStore().loadRunActions(
            runID: "run-review",
            inProjectAt: root
        )
        let approvalAction = try #require(approvalActions.first {
            $0.actionKind == XcircuiteRunReviewDecisionActionKind.approval.rawValue
        })
        #expect(approvalAction.actor.kind == .human)
        #expect(approvalAction.actor.identifier == "reviewer-1")
        #expect(approvalAction.metadata["source"] == .string("circuit-studio.run-review"))
        #expect(approvalAction.metadata["decision"] == .string("approved"))
        #expect(approvalAction.outputs.map(\.path) == [".xcircuite/runs/run-review/approvals/001-drc.json"])

        // 4. Re-running the same runID resumes past the gate; the
        //    cockpit shows the full picture.
        let resumed = try await DefaultFlowOrchestrator().run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(resumed.status == .succeeded)

        review = try service.loadRun(runID: "run-review", projectRoot: root)
        #expect(review.stages.count == 2)
        let decided = try #require(review.stages.first { $0.result.stageID == "001-drc" })
        #expect(!decided.awaitingApproval)
        #expect(decided.approval?.verdict == .approved)
        #expect(decided.approval?.reviewer == "reviewer-1")
        #expect(decided.result.gates.contains { $0.gateID == "approval" && $0.status == .passed })
    }

    @Test func runLedgerFlowReviewProjectionSurfacesSharedBundleRefs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-flow-projection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { RunReviewTestSupport.removeTemporaryRoot(root) }

        let runID = "run-flow-review"
        let stageID = "001-drc"
        let summaryPath = ".xcircuite/runs/\(runID)/stages/\(stageID)/raw/drc-summary.json"
        _ = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: runID,
                intent: "Review projection",
                stages: [
                    FlowStageDefinition(stageID: stageID, displayName: "DRC", requiresApproval: true),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                RunReviewPassingExecutor(
                    stageID: stageID,
                    artifacts: [
                        XcircuiteFileReference(
                            artifactID: "drc-summary",
                            path: summaryPath,
                            kind: .report,
                            format: .json
                        ),
                    ],
                    artifactPayloads: [summaryPath: Data(#"{"artifactID":"drc-summary"}"#.utf8)]
                ),
            ]
        )

        let store = XcircuitePackageStore()
        let ladderPath = ".xcircuite/runs/\(runID)/review/stage-artifact-ladder.json"
        let planningPath = ".xcircuite/runs/\(runID)/planning/candidate-plan.json"
        let retainedPath = ".xcircuite/runs/\(runID)/retention/retained-ci-regression-budget.json"
        let waiverPath = ".xcircuite/runs/\(runID)/waivers/waiver-review.json"
        _ = try RunReviewTestSupport.writeRunJSONArtifact(
            Data(#"{"schemaVersion":1,"readiness":"needsReview"}"#.utf8),
            path: ladderPath,
            artifactID: "review-stage-artifact-ladder",
            root: root,
            runID: runID
        )
        _ = try RunReviewTestSupport.writeRunJSONArtifact(
            Data(#"{"schemaVersion":1,"planID":"plan-1","steps":[]}"#.utf8),
            path: planningPath,
            artifactID: "planning-candidate-plan",
            root: root,
            runID: runID
        )
        _ = try RunReviewTestSupport.writeRunJSONArtifact(
            Data(#"{"schemaVersion":1,"status":"failed","failures":[{"code":"retained_ci_regression_budget_evidence_stale"}]}"#.utf8),
            path: retainedPath,
            artifactID: "retained-ci-regression-budget",
            root: root,
            runID: runID
        )
        let waiverRef = try RunReviewTestSupport.writeRunJSONArtifact(
            Data(#"{"schemaVersion":1,"waiverID":"waiver-1","status":"accepted"}"#.utf8),
            path: waiverPath,
            artifactID: "waiver-review",
            root: root,
            runID: runID
        )

        let service = RunReviewService()
        _ = try service.decide(
            runID: runID,
            stageID: stageID,
            verdict: .approved,
            reviewer: "reviewer-1",
            note: "reviewed",
            projectRoot: root
        )
        try store.appendReviewDecisionAction(
            XcircuiteRunReviewDecisionActionRequest(
                actionID: "waiver-decision-1",
                runID: runID,
                stageID: stageID,
                actor: XcircuiteRunActionActor(kind: .human, identifier: "reviewer-1"),
                decisionKind: .waiver,
                decision: "accepted",
                targetID: "waiver-1",
                targetPath: waiverPath,
                reason: "Reviewed waiver is accepted.",
                outputs: [waiverRef]
            ),
            inProjectAt: root
        )
        try store.appendReviewDecisionAction(
            XcircuiteRunReviewDecisionActionRequest(
                actionID: "resume-decision-1",
                runID: runID,
                actor: XcircuiteRunActionActor(kind: .human, identifier: "reviewer-1"),
                decisionKind: .resume,
                decision: "requested",
                targetID: runID,
                reason: "Approval and waiver decisions are recorded."
            ),
            inProjectAt: root
        )

        let review = try service.loadRun(runID: runID, projectRoot: root)
        #expect(review.flowReview.hasContent)
        #expect(review.flowReview.signoffLadderArtifacts.contains {
            $0.role == "stage-artifact-ladder" && $0.path == ladderPath
        })
        #expect(review.flowReview.planningArtifacts.contains {
            $0.role == "planning-candidate-plan" && $0.path == planningPath
        })
        #expect(review.flowReview.retainedHistoryArtifacts.contains {
            $0.role == "retained-ci-regression-budget" && $0.path == retainedPath
        })
        #expect(review.flowReview.approvalActions.map(\.decision) == ["approved"])
        #expect(review.flowReview.waiverActions.map(\.targetID) == ["waiver-1"])
        #expect(review.flowReview.resumeActions.map(\.targetID) == [runID])
        #expect(review.flowReview.resumeItems.contains {
            $0.kind == .approvalGate && $0.status == .readyToResume
        })
        #expect(review.flowReview.blockedItems.contains {
            $0.kind == .retainedHistory
                && $0.diagnosticCodes.contains("retained_ci_regression_budget_evidence_stale")
        })
        #expect(review.flowReview.coverageDomains.contains { $0.domain == "approval" })
        #expect(review.flowReview.coverageDomains.contains { $0.domain == "waiver" })
        #expect(review.flowReview.coverageDomains.contains { $0.domain == "resume" })
        #expect(review.flowReview.coverageDomains.contains { $0.domain == "planning" })
        #expect(review.flowReview.coverageDomains.contains { $0.domain == "retained-history" })
        #expect(review.flowReview.coverageRefs.contains {
            $0.domain == "retained-history"
                && $0.path == retainedPath
                && $0.reviewItemIDs == ["review-retained-history"]
        })
        #expect(review.retainedDashboard.hasContent)
        #expect(review.retainedDashboard.status == .needsRepair)
        #expect(review.retainedDashboard.artifactStates.contains {
            $0.role == "retained-ci-regression-budget"
                && $0.path == retainedPath
                && $0.evidenceStatus == "stale"
                && $0.diagnosticCodes.contains("retained_ci_regression_budget_evidence_stale")
        })
        #expect(review.retainedDashboard.blockerSummaries.contains {
            $0.id == "review-retained-history"
                && $0.status == .needsRepair
                && $0.nextActionID == "repair-retained-history-evidence"
        })
        #expect(review.retainedDashboard.decisionSummaries.map(\.targetID).contains("waiver-1"))
        #expect(review.retainedDashboard.decisionSummaries.map(\.targetID).contains(runID))
        #expect(review.retainedDashboard.diagnosticCodes.contains("retained_ci_regression_budget_evidence_stale"))

        let dashboardRef = try service.persistRetainedDashboardProjection(
            runID: runID,
            projectRoot: root
        )
        #expect(dashboardRef.artifactID == "retained-dashboard-projection")
        #expect(dashboardRef.path == ".xcircuite/runs/\(runID)/review/retained-dashboard-projection.json")
        #expect(dashboardRef.sha256 != nil)
        #expect(dashboardRef.byteCount != nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persistedProjection = try decoder.decode(
            RunReviewRetainedDashboardProjection.self,
            from: Data(contentsOf: root.appending(path: dashboardRef.path))
        )
        #expect(persistedProjection.status == .needsRepair)
        #expect(persistedProjection.artifactStates.contains { $0.path == retainedPath })
        let runManifest = try store.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/\(runID)/manifest.json")
        )
        #expect(runManifest.artifacts.contains {
            $0.artifactID == "retained-dashboard-projection"
                && $0.path == dashboardRef.path
        })
    }

    @Test func runReviewViewSurfacesFlowReviewProjectionCard() throws {
        let source = try RunReviewTestSupport.projectSource("Sources/CircuitStudioApp/Views/RunReviewView.swift")
        #expect(source.contains("review.flowReview.hasContent"))
        #expect(source.contains("RunReviewFlowReviewProjectionCard(projection: review.flowReview)"))
    }

    @Test func runReviewViewSurfacesRetainedDashboardCard() throws {
        let source = try RunReviewTestSupport.projectSource("Sources/CircuitStudioApp/Views/RunReviewView.swift")
        #expect(source.contains("review.retainedDashboard.hasContent"))
        #expect(source.contains("RunReviewRetainedDashboardCard(projection: review.retainedDashboard)"))
    }

    @Test func reviewFailureStatesProjectMissingIntegrityBlockedAndStaleEvidence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-failure-states-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { RunReviewTestSupport.removeTemporaryRoot(root) }

        let runID = "run-failure-states"
        let stageID = "001-drc"
        let rawPrefix = ".xcircuite/runs/\(runID)/stages/\(stageID)/raw"
        let missingPath = "\(rawPrefix)/missing-report.json"
        let mismatchPath = "\(rawPrefix)/mismatch-report.json"
        let stalePath = "\(rawPrefix)/stale-report.json"
        let staleURL = root.appending(path: stalePath)
        try FileManager.default.createDirectory(
            at: staleURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"state":"unhashed"}"#.utf8).write(to: staleURL, options: .atomic)

        let mismatchPayload = Data(#"{"state":"original"}"#.utf8)
        _ = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: runID,
                intent: "Review failure states",
                stages: [
                    FlowStageDefinition(stageID: stageID, displayName: "DRC", requiresApproval: true),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                RunReviewPassingExecutor(
                    stageID: stageID,
                    artifacts: [
                        XcircuiteFileReference(
                            artifactID: "missing-report",
                            path: missingPath,
                            kind: .report,
                            format: .json
                        ),
                        XcircuiteFileReference(
                            artifactID: "mismatch-report",
                            path: mismatchPath,
                            kind: .report,
                            format: .json
                        ),
                        XcircuiteFileReference(
                            artifactID: "stale-report",
                            path: stalePath,
                            kind: .report,
                            format: .json
                        ),
                    ],
                    artifactPayloads: [
                        mismatchPath: mismatchPayload,
                    ]
                ),
            ]
        )

        let mismatchURL = root.appending(path: mismatchPath)
        try Data(#"{"state":"changed-after-ledger"}"#.utf8).write(to: mismatchURL, options: .atomic)

        let service = RunReviewService()
        let review = try service.loadRun(runID: runID, projectRoot: root)
        let failureStates = review.failureStates

        #expect(failureStates.count(of: .missingArtifact) >= 1)
        #expect(failureStates.count(of: .integrityMismatch) >= 1)
        #expect(failureStates.count(of: .staleEvidence) >= 1)
        #expect(failureStates.count(of: .blockedGate) >= 1)
        #expect(service.failureStateSummary(from: review) == failureStates)

        let missing = try #require(failureStates.states(of: .missingArtifact).first {
            $0.artifactRefs.contains { $0.path == missingPath && $0.integrityStatus == "missingArtifact" }
        })
        #expect(missing.suggestedActions.contains("restore-or-regenerate-artifact"))

        let mismatch = try #require(failureStates.states(of: .integrityMismatch).first {
            $0.artifactRefs.contains {
                $0.path == mismatchPath
                    && ($0.integrityStatus == "sha256Mismatch" || $0.integrityStatus == "byteCountMismatch")
            }
        })
        #expect(mismatch.suggestedActions.contains("rerun-artifact-integrity-gate"))

        let stale = try #require(failureStates.states(of: .staleEvidence).first {
            $0.artifactRefs.contains {
                $0.path == stalePath
                    && ($0.integrityStatus == "missingDigest" || $0.integrityStatus == "missingByteCount")
            }
        })
        #expect(stale.suggestedActions.contains("record-digest-and-byte-count"))

        let blockedGate = try #require(failureStates.states(of: .blockedGate).first {
            $0.stageID == stageID && $0.gateID == "approval"
        })
        #expect(blockedGate.nextActionID == "\(stageID)-decide-approval")
        #expect(blockedGate.suggestedActions.contains("record-approval-decision"))

        let unsupportedBundle = FlowRunReviewBundle(
            runID: "unsupported-action",
            status: .blocked,
            runDirectoryPath: ".xcircuite/runs/unsupported-action",
            summary: FlowRunLedgerSummary(
                runID: "unsupported-action",
                status: .blocked,
                runDirectoryPath: ".xcircuite/runs/unsupported-action",
                nextActions: [
                    FlowRunNextAction(
                        actionID: "unsupported-repair",
                        kind: "repair",
                        severity: .warning,
                        reason: "An unsupported repair command was proposed.",
                        suggestedCommands: [
                            FlowRunSuggestedCommand(
                                commandID: "unsupported-command",
                                readiness: .requiresInput,
                                executable: "unsupported-tool",
                                arguments: [],
                                reason: "Unsupported by the local toolchain."
                            ),
                        ]
                    ),
                ]
            )
        )
        let unsupportedSummary = service.failureStateSummary(
            bundle: unsupportedBundle,
            stages: [],
            planningDecodeIssues: [],
            signoffDecodeIssues: [],
            waiverDecodeIssues: []
        )
        let unsupported = try #require(unsupportedSummary.states(of: .unsupportedAction).first)
        #expect(unsupported.nextActionID == "unsupported-repair")
        #expect(unsupported.suggestedActions == ["unsupported-command"])
    }

    @Test func waiverEditVerificationContextReportsMissingInputs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-context-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { RunReviewTestSupport.removeTemporaryRoot(root) }

        let runID = "run-missing-context"
        let stageID = "001-review"
        let designSpecPath = ".xcircuite/runs/\(runID)/stages/\(stageID)/raw/design-spec.json"
        let layoutDocumentPath = ".xcircuite/runs/\(runID)/stages/\(stageID)/raw/layout-document.json"
        let service = RunReviewService()

        _ = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: runID,
                intent: "Missing review context",
                stages: [
                    FlowStageDefinition(stageID: stageID, displayName: "Review"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                RunReviewPassingExecutor(
                    stageID: stageID,
                    artifacts: [
                        XcircuiteFileReference(
                            artifactID: "design-spec",
                            path: designSpecPath,
                            kind: .other,
                            format: .json
                        ),
                    ],
                    artifactPayloads: [
                        designSpecPath: try RunReviewTestSupport.encodedJSONData(RunReviewTestSupport.reviewVerificationDesignSpec()),
                    ]
                ),
            ]
        )

        let missingLayoutReview = try service.loadRun(runID: runID, projectRoot: root)
        #expect(throws: RunReviewServiceError.waiverEditVerificationLayoutDocumentNotFound(runID: runID)) {
            try service.waiverEditVerificationContext(
                review: missingLayoutReview,
                projectRoot: root
            )
        }

        _ = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: runID,
                intent: "Missing review context",
                stages: [
                    FlowStageDefinition(stageID: stageID, displayName: "Review"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                RunReviewPassingExecutor(
                    stageID: stageID,
                    artifacts: [
                        XcircuiteFileReference(
                            artifactID: "design-spec",
                            path: designSpecPath,
                            kind: .other,
                            format: .json
                        ),
                        XcircuiteFileReference(
                            artifactID: "layout-document",
                            path: layoutDocumentPath,
                            kind: .layout,
                            format: .json
                        ),
                    ],
                    artifactPayloads: [
                        designSpecPath: try RunReviewTestSupport.encodedJSONData(RunReviewTestSupport.reviewVerificationDesignSpec()),
                    ]
                ),
            ]
        )

        let missingFileReview = try service.loadRun(runID: runID, projectRoot: root)
        #expect(throws: RunReviewServiceError.waiverEditVerificationInputMissing(path: layoutDocumentPath)) {
            try service.waiverEditVerificationContext(
                review: missingFileReview,
                projectRoot: root
            )
        }
    }

    @Test func rejectionIsVisibleInTheReview() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-reject-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { RunReviewTestSupport.removeTemporaryRoot(root) }

        let request = FlowOperationRequest(
            projectRoot: root,
            runID: "run-reject",
            intent: "Review loop",
            stages: [
                FlowStageDefinition(stageID: "001-drc", displayName: "DRC", requiresApproval: true),
            ]
        )
        let executors: [any FlowStageExecutor] = [RunReviewPassingExecutor(stageID: "001-drc")]

        _ = try await DefaultFlowOrchestrator().run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        let service = RunReviewService()
        _ = try service.decide(
            runID: "run-reject",
            stageID: "001-drc",
            verdict: .rejected,
            reviewer: "reviewer-1",
            note: "rail too narrow",
            projectRoot: root
        )
        let rerun = try await DefaultFlowOrchestrator().run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(rerun.status == .failed)

        let review = try service.loadRun(runID: "run-reject", projectRoot: root)
        let stage = try #require(review.stages.first)
        #expect(stage.approval?.verdict == .rejected)
        #expect(stage.result.gates.contains { $0.gateID == "approval" && $0.status == .failed })
        #expect(review.bundle.reviewItems.contains {
            $0.kind == .stageFailure
                && $0.status == .needsRepair
                && $0.stageID == "001-drc"
        })
    }


}
