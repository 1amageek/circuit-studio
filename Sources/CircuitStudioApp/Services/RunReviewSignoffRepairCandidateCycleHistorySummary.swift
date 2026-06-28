import Foundation

public struct RunReviewSignoffRepairCandidateCycleHistorySummary: Sendable, Hashable, Codable {
    public let cycleCount: Int
    public let acceptedCount: Int
    public let notAcceptedCount: Int
    public let latestCycleIndex: Int?
    public let latestAccepted: Bool?
    public let consumedRejectedPlanFeedbackRecordCount: Int
    public let maximumGlobalRejectedPlanFeedbackCount: Int
    public let selectedActionIDs: [String]
    public let selectedActionDomainIDs: [String]
    public let selectedObjectiveDomainIDs: [String]
    public let objectiveDomainSummaries: [RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary]
    public let feedbackPenalizedActionIDs: [String]
    public let feedbackRankChangeCount: Int
    public let feedbackRankChangedActionIDs: [String]
    public let feedbackScoreDeltaCount: Int
    public let feedbackScoreDeltaActionIDs: [String]

    public init(cycles: [RunReviewSignoffRepairCandidateCycleHistoryItem]) {
        let latestCycle = cycles.max { left, right in
            if left.cycleIndex != right.cycleIndex {
                return left.cycleIndex < right.cycleIndex
            }
            return left.createdAt < right.createdAt
        }

        cycleCount = cycles.count
        acceptedCount = cycles.filter(\.accepted).count
        notAcceptedCount = cycles.filter { !$0.accepted }.count
        latestCycleIndex = latestCycle?.cycleIndex
        latestAccepted = latestCycle?.accepted
        consumedRejectedPlanFeedbackRecordCount = cycles.reduce(0) {
            $0 + $1.rejectedPlanFeedbackRecordCount
        }
        maximumGlobalRejectedPlanFeedbackCount = cycles
            .map(\.globalRejectedPlanFeedbackCount)
            .max() ?? 0
        selectedActionIDs = Self.uniquePreservingOrder(
            cycles.flatMap(\.selectedActionIDs)
        )
        selectedActionDomainIDs = Self.uniquePreservingOrder(
            cycles.flatMap(\.selectedActionDomainIDs)
        )
        selectedObjectiveDomainIDs = Self.uniquePreservingOrder(
            cycles.flatMap(\.selectedObjectiveDomainIDs)
        )
        objectiveDomainSummaries = RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary
            .summarize(cycles: cycles)
        feedbackPenalizedActionIDs = Self.uniquePreservingOrder(
            cycles.flatMap(\.feedbackPenalizedActionIDs)
        )
        feedbackRankChangeCount = cycles.reduce(0) {
            $0 + $1.feedbackRankChanges.count
        }
        feedbackRankChangedActionIDs = Self.uniquePreservingOrder(
            cycles
                .flatMap(\.feedbackRankChanges)
                .map(Self.actionID)
        )
        feedbackScoreDeltaCount = cycles.reduce(0) {
            $0 + $1.feedbackScoreDeltas.count
        }
        feedbackScoreDeltaActionIDs = Self.uniquePreservingOrder(
            cycles
                .flatMap(\.feedbackScoreDeltas)
                .map(Self.actionID)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case cycleCount
        case acceptedCount
        case notAcceptedCount
        case latestCycleIndex
        case latestAccepted
        case consumedRejectedPlanFeedbackRecordCount
        case maximumGlobalRejectedPlanFeedbackCount
        case selectedActionIDs
        case selectedActionDomainIDs
        case selectedObjectiveDomainIDs
        case objectiveDomainSummaries
        case feedbackPenalizedActionIDs
        case feedbackRankChangeCount
        case feedbackRankChangedActionIDs
        case feedbackScoreDeltaCount
        case feedbackScoreDeltaActionIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.cycleCount = try container.decode(Int.self, forKey: .cycleCount)
        self.acceptedCount = try container.decode(Int.self, forKey: .acceptedCount)
        self.notAcceptedCount = try container.decode(Int.self, forKey: .notAcceptedCount)
        self.latestCycleIndex = try container.decodeIfPresent(Int.self, forKey: .latestCycleIndex)
        self.latestAccepted = try container.decodeIfPresent(Bool.self, forKey: .latestAccepted)
        self.consumedRejectedPlanFeedbackRecordCount = try container.decode(
            Int.self,
            forKey: .consumedRejectedPlanFeedbackRecordCount
        )
        self.maximumGlobalRejectedPlanFeedbackCount = try container.decode(
            Int.self,
            forKey: .maximumGlobalRejectedPlanFeedbackCount
        )
        self.selectedActionIDs = try container.decodeIfPresent([String].self, forKey: .selectedActionIDs) ?? []
        self.selectedActionDomainIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .selectedActionDomainIDs
        ) ?? []
        self.selectedObjectiveDomainIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .selectedObjectiveDomainIDs
        ) ?? []
        self.objectiveDomainSummaries = try container.decodeIfPresent(
            [RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary].self,
            forKey: .objectiveDomainSummaries
        ) ?? []
        self.feedbackPenalizedActionIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .feedbackPenalizedActionIDs
        ) ?? []
        self.feedbackRankChangeCount = try container.decode(
            Int.self,
            forKey: .feedbackRankChangeCount
        )
        self.feedbackRankChangedActionIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .feedbackRankChangedActionIDs
        ) ?? []
        self.feedbackScoreDeltaCount = try container.decode(
            Int.self,
            forKey: .feedbackScoreDeltaCount
        )
        self.feedbackScoreDeltaActionIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .feedbackScoreDeltaActionIDs
        ) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cycleCount, forKey: .cycleCount)
        try container.encode(acceptedCount, forKey: .acceptedCount)
        try container.encode(notAcceptedCount, forKey: .notAcceptedCount)
        try container.encodeIfPresent(latestCycleIndex, forKey: .latestCycleIndex)
        try container.encodeIfPresent(latestAccepted, forKey: .latestAccepted)
        try container.encode(
            consumedRejectedPlanFeedbackRecordCount,
            forKey: .consumedRejectedPlanFeedbackRecordCount
        )
        try container.encode(
            maximumGlobalRejectedPlanFeedbackCount,
            forKey: .maximumGlobalRejectedPlanFeedbackCount
        )
        try container.encode(selectedActionIDs, forKey: .selectedActionIDs)
        try container.encode(selectedActionDomainIDs, forKey: .selectedActionDomainIDs)
        try container.encode(selectedObjectiveDomainIDs, forKey: .selectedObjectiveDomainIDs)
        try container.encode(objectiveDomainSummaries, forKey: .objectiveDomainSummaries)
        try container.encode(feedbackPenalizedActionIDs, forKey: .feedbackPenalizedActionIDs)
        try container.encode(feedbackRankChangeCount, forKey: .feedbackRankChangeCount)
        try container.encode(feedbackRankChangedActionIDs, forKey: .feedbackRankChangedActionIDs)
        try container.encode(feedbackScoreDeltaCount, forKey: .feedbackScoreDeltaCount)
        try container.encode(feedbackScoreDeltaActionIDs, forKey: .feedbackScoreDeltaActionIDs)
    }

    public var hasFeedbackImpact: Bool {
        !feedbackPenalizedActionIDs.isEmpty
            || feedbackRankChangeCount > 0
            || feedbackScoreDeltaCount > 0
    }

    private static func actionID(from feedbackMetric: String) -> String {
        guard let separatorIndex = feedbackMetric.firstIndex(of: ":") else {
            return feedbackMetric
        }
        return String(feedbackMetric[..<separatorIndex])
    }

    private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !value.isEmpty && !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
