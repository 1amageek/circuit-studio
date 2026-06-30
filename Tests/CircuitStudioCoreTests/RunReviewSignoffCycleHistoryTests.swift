import Foundation
import Testing
@testable import CircuitStudioApp

@Suite("Run review signoff cycle history", .timeLimit(.minutes(1)))
struct RunReviewSignoffCycleHistoryTests {
    @Test func signoffRepairCandidateCycleHistorySummaryAggregatesFeedbackImpact() throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let firstCycle = RunReviewSignoffRepairCandidateCycleHistoryItem(
            actionID: "cycle-1",
            cycleIndex: 1,
            status: .blocked,
            planID: "plan-1",
            generationStatus: "succeeded",
            executionStatus: "succeeded",
            verificationStatus: "blocked",
            accepted: false,
            rejectedPlansPath: ".xcircuite/runs/run/rejected-plans.jsonl",
            rejectedPlanFeedbackRecordCount: 1,
            globalRejectedPlanFeedbackCount: 2,
            selectedActionIDs: ["repair-a", "repair-b"],
            selectedActionDomainIDs: ["layout-edit", "lvs-signoff"],
            selectedObjectiveDomainIDs: ["drc", "lvs"],
            feedbackPenalizedActionIDs: ["repair-a"],
            feedbackRankChanges: ["repair-a:1->2"],
            feedbackScoreDeltas: ["repair-a:-6"],
            candidatePlanArtifact: nil,
            planExecutionArtifact: nil,
            planVerificationArtifact: nil,
            rejectedPlansArtifact: nil,
            designDiffArtifact: nil,
            createdAt: baseDate
        )
        let secondCycle = RunReviewSignoffRepairCandidateCycleHistoryItem(
            actionID: "cycle-2",
            cycleIndex: 2,
            status: .succeeded,
            planID: "plan-2",
            generationStatus: "succeeded",
            executionStatus: "succeeded",
            verificationStatus: "succeeded",
            accepted: true,
            rejectedPlansPath: ".xcircuite/runs/run/rejected-plans.jsonl",
            rejectedPlanFeedbackRecordCount: 2,
            globalRejectedPlanFeedbackCount: 4,
            selectedActionIDs: ["repair-b", "repair-c"],
            selectedActionDomainIDs: ["lvs-signoff", "pex-extraction"],
            selectedObjectiveDomainIDs: ["lvs", "pex"],
            feedbackPenalizedActionIDs: ["repair-a", "repair-c"],
            feedbackRankChanges: ["repair-b:2->1", "repair-a:1->2"],
            feedbackScoreDeltas: ["repair-c:-3"],
            candidatePlanArtifact: nil,
            planExecutionArtifact: nil,
            planVerificationArtifact: nil,
            rejectedPlansArtifact: nil,
            designDiffArtifact: nil,
            createdAt: baseDate.addingTimeInterval(1)
        )

        let summary = RunReviewSignoffSummary(
            cards: [],
            repairCandidateCycles: [firstCycle, secondCycle]
        ).repairCandidateCycleHistorySummary

        #expect(summary.cycleCount == 2)
        #expect(summary.acceptedCount == 1)
        #expect(summary.notAcceptedCount == 1)
        #expect(summary.latestCycleIndex == 2)
        #expect(summary.latestAccepted == .some(true))
        #expect(summary.consumedRejectedPlanFeedbackRecordCount == 3)
        #expect(summary.maximumGlobalRejectedPlanFeedbackCount == 4)
        #expect(summary.selectedActionIDs == ["repair-a", "repair-b", "repair-c"])
        #expect(summary.selectedActionDomainIDs == ["layout-edit", "lvs-signoff", "pex-extraction"])
        #expect(summary.selectedObjectiveDomainIDs == ["drc", "lvs", "pex"])
        #expect(summary.objectiveDomainSummaries.map(\.domainID) == ["drc", "lvs", "pex"])
        #expect(summary.objectiveDomainSummaries.map(\.cycleCount) == [1, 2, 1])
        #expect(summary.objectiveDomainSummaries.map(\.acceptedCount) == [0, 1, 1])
        #expect(summary.feedbackPenalizedActionIDs == ["repair-a", "repair-c"])
        #expect(summary.feedbackRankChangeCount == 3)
        #expect(summary.feedbackRankChangedActionIDs == ["repair-a", "repair-b"])
        #expect(summary.feedbackScoreDeltaCount == 2)
        #expect(summary.feedbackScoreDeltaActionIDs == ["repair-a", "repair-c"])
        #expect(summary.hasFeedbackImpact)
    }
}
