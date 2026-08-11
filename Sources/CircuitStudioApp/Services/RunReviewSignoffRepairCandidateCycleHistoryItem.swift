import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct RunReviewSignoffRepairCandidateCycleHistoryItem: Sendable, Hashable, Codable, Identifiable {
    public var id: String {
        actionID
    }

    public let actionID: String
    public let cycleIndex: Int
    public let status: FlowRunActionStatus
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
    public let candidatePlanArtifact: FlowArtifactBinding?
    public let planExecutionArtifact: FlowArtifactBinding?
    public let planVerificationArtifact: FlowArtifactBinding?
    public let rejectedPlansArtifact: FlowArtifactBinding?
    public let designDiffArtifact: FlowArtifactBinding?
    public let createdAt: Date

    public init(
        actionID: String,
        cycleIndex: Int,
        status: FlowRunActionStatus,
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
        candidatePlanArtifact: FlowArtifactBinding?,
        planExecutionArtifact: FlowArtifactBinding?,
        planVerificationArtifact: FlowArtifactBinding?,
        rejectedPlansArtifact: FlowArtifactBinding?,
        designDiffArtifact: FlowArtifactBinding?,
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
