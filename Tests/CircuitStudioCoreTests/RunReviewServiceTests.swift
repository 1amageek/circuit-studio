import Foundation
import Testing
import DesignFlowKernel
import ToolQualification
import XcircuitePackage
@testable import CircuitStudioApp

/// P4 gate: the cockpit and the flow kernel close one loop over one
/// ledger — a run blocks at the approval gate, the reviewer reads the
/// SAME stage results the kernel persisted and records a decision, and
/// re-running the same runID resumes past the gate.
@Suite("Run review service", .timeLimit(.minutes(2)))
struct RunReviewServiceTests {

    private struct PassingExecutor: FlowStageExecutor {
        let stageID: String
        let toolID = "stub-tool"

        func execute(
            stage: FlowStageDefinition,
            context: FlowExecutionContext
        ) async throws -> FlowStageResult {
            FlowStageResult(
                stageID: stage.stageID,
                status: .succeeded,
                gates: [FlowGateResult(gateID: "drc", status: .passed)]
            )
        }
    }

    @Test func reviewLoopBlocksDecidesAndResumes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let request = FlowOperationRequest(
            projectRoot: root,
            runID: "run-review",
            intent: "Review loop",
            stages: [
                FlowStageDefinition(stageID: "001-drc", displayName: "DRC", requiresApproval: true),
                FlowStageDefinition(stageID: "002-ship", displayName: "Ship"),
            ]
        )
        let executors: [any FlowStageExecutor] = [
            PassingExecutor(stageID: "001-drc"),
            PassingExecutor(stageID: "002-ship"),
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

    @Test func rejectionIsVisibleInTheReview() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-reject-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let request = FlowOperationRequest(
            projectRoot: root,
            runID: "run-reject",
            intent: "Review loop",
            stages: [
                FlowStageDefinition(stageID: "001-drc", displayName: "DRC", requiresApproval: true),
            ]
        )
        let executors: [any FlowStageExecutor] = [PassingExecutor(stageID: "001-drc")]

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
    }
}
