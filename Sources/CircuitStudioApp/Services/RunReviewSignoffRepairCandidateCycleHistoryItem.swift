import Foundation
import XcircuitePackage

public struct RunReviewSignoffRepairCandidateCycleHistoryItem: Sendable, Hashable, Identifiable {
    public var id: String {
        actionID
    }

    public let actionID: String
    public let cycleIndex: Int
    public let status: XcircuiteRunActionStatus
    public let planID: String?
    public let generationStatus: String?
    public let executionStatus: String?
    public let verificationStatus: String?
    public let accepted: Bool
    public let rejectedPlansPath: String?
    public let rejectedPlanFeedbackRecordCount: Int
    public let globalRejectedPlanFeedbackCount: Int
    public let selectedActionIDs: [String]
    public let selectedActionDomainIDs: [String]
    public let selectedObjectiveDomainIDs: [String]
    public let feedbackPenalizedActionIDs: [String]
    public let feedbackRankChanges: [String]
    public let feedbackScoreDeltas: [String]
    public let candidatePlanArtifact: XcircuiteFileReference?
    public let planExecutionArtifact: XcircuiteFileReference?
    public let planVerificationArtifact: XcircuiteFileReference?
    public let rejectedPlansArtifact: XcircuiteFileReference?
    public let designDiffArtifact: XcircuiteFileReference?
    public let createdAt: Date

    public init(
        actionID: String,
        cycleIndex: Int,
        status: XcircuiteRunActionStatus,
        planID: String?,
        generationStatus: String?,
        executionStatus: String?,
        verificationStatus: String?,
        accepted: Bool,
        rejectedPlansPath: String?,
        rejectedPlanFeedbackRecordCount: Int,
        globalRejectedPlanFeedbackCount: Int,
        selectedActionIDs: [String],
        selectedActionDomainIDs: [String] = [],
        selectedObjectiveDomainIDs: [String] = [],
        feedbackPenalizedActionIDs: [String],
        feedbackRankChanges: [String] = [],
        feedbackScoreDeltas: [String] = [],
        candidatePlanArtifact: XcircuiteFileReference?,
        planExecutionArtifact: XcircuiteFileReference?,
        planVerificationArtifact: XcircuiteFileReference?,
        rejectedPlansArtifact: XcircuiteFileReference?,
        designDiffArtifact: XcircuiteFileReference?,
        createdAt: Date
    ) {
        self.actionID = actionID
        self.cycleIndex = cycleIndex
        self.status = status
        self.planID = planID
        self.generationStatus = generationStatus
        self.executionStatus = executionStatus
        self.verificationStatus = verificationStatus
        self.accepted = accepted
        self.rejectedPlansPath = rejectedPlansPath
        self.rejectedPlanFeedbackRecordCount = rejectedPlanFeedbackRecordCount
        self.globalRejectedPlanFeedbackCount = globalRejectedPlanFeedbackCount
        self.selectedActionIDs = selectedActionIDs
        self.selectedActionDomainIDs = selectedActionDomainIDs
        self.selectedObjectiveDomainIDs = selectedObjectiveDomainIDs
        self.feedbackPenalizedActionIDs = feedbackPenalizedActionIDs
        self.feedbackRankChanges = feedbackRankChanges
        self.feedbackScoreDeltas = feedbackScoreDeltas
        self.candidatePlanArtifact = candidatePlanArtifact
        self.planExecutionArtifact = planExecutionArtifact
        self.planVerificationArtifact = planVerificationArtifact
        self.rejectedPlansArtifact = rejectedPlansArtifact
        self.designDiffArtifact = designDiffArtifact
        self.createdAt = createdAt
    }
}
