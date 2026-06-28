import Foundation

public struct RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary: Sendable, Hashable, Codable {
    public let domainID: String
    public let cycleCount: Int
    public let acceptedCount: Int
    public let notAcceptedCount: Int
    public let acceptanceRate: Double
    public let feedbackRankChangeCount: Int
    public let feedbackScoreDeltaCount: Int
    public let selectedActionIDs: [String]
    public let selectedActionDomainIDs: [String]

    public init(
        domainID: String,
        cycleCount: Int,
        acceptedCount: Int,
        notAcceptedCount: Int,
        acceptanceRate: Double,
        feedbackRankChangeCount: Int,
        feedbackScoreDeltaCount: Int,
        selectedActionIDs: [String],
        selectedActionDomainIDs: [String]
    ) {
        self.domainID = domainID
        self.cycleCount = cycleCount
        self.acceptedCount = acceptedCount
        self.notAcceptedCount = notAcceptedCount
        self.acceptanceRate = acceptanceRate
        self.feedbackRankChangeCount = feedbackRankChangeCount
        self.feedbackScoreDeltaCount = feedbackScoreDeltaCount
        self.selectedActionIDs = selectedActionIDs
        self.selectedActionDomainIDs = selectedActionDomainIDs
    }

    public static func summarize(
        cycles: [RunReviewSignoffRepairCandidateCycleHistoryItem]
    ) -> [RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary] {
        let domainIDs = uniquePreservingOrder(cycles.flatMap(\.selectedObjectiveDomainIDs))
        return domainIDs.map { domainID in
            let domainCycles = cycles.filter { cycle in
                cycle.selectedObjectiveDomainIDs.contains(domainID)
            }
            return summarize(
                domainID: domainID,
                cycleCount: domainCycles.count,
                acceptedCount: domainCycles.filter(\.accepted).count,
                notAcceptedCount: domainCycles.filter { !$0.accepted }.count,
                feedbackRankChangeCount: domainCycles.reduce(0) {
                    $0 + $1.feedbackRankChanges.count
                },
                feedbackScoreDeltaCount: domainCycles.reduce(0) {
                    $0 + $1.feedbackScoreDeltas.count
                },
                selectedActionIDs: uniquePreservingOrder(domainCycles.flatMap(\.selectedActionIDs)),
                selectedActionDomainIDs: uniquePreservingOrder(domainCycles.flatMap(\.selectedActionDomainIDs))
            )
        }
    }

    public static func aggregate(
        summaries: [RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary]
    ) -> [RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary] {
        let domainIDs = uniquePreservingOrder(summaries.map(\.domainID))
        return domainIDs.map { domainID in
            let domainSummaries = summaries.filter { $0.domainID == domainID }
            return summarize(
                domainID: domainID,
                cycleCount: domainSummaries.reduce(0) { $0 + $1.cycleCount },
                acceptedCount: domainSummaries.reduce(0) { $0 + $1.acceptedCount },
                notAcceptedCount: domainSummaries.reduce(0) { $0 + $1.notAcceptedCount },
                feedbackRankChangeCount: domainSummaries.reduce(0) {
                    $0 + $1.feedbackRankChangeCount
                },
                feedbackScoreDeltaCount: domainSummaries.reduce(0) {
                    $0 + $1.feedbackScoreDeltaCount
                },
                selectedActionIDs: uniquePreservingOrder(domainSummaries.flatMap(\.selectedActionIDs)),
                selectedActionDomainIDs: uniquePreservingOrder(domainSummaries.flatMap(\.selectedActionDomainIDs))
            )
        }
    }

    private static func summarize(
        domainID: String,
        cycleCount: Int,
        acceptedCount: Int,
        notAcceptedCount: Int,
        feedbackRankChangeCount: Int,
        feedbackScoreDeltaCount: Int,
        selectedActionIDs: [String],
        selectedActionDomainIDs: [String]
    ) -> RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary {
        let acceptanceRate: Double
        if cycleCount > 0 {
            acceptanceRate = Double(acceptedCount) / Double(cycleCount)
        } else {
            acceptanceRate = 0
        }
        return RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary(
            domainID: domainID,
            cycleCount: cycleCount,
            acceptedCount: acceptedCount,
            notAcceptedCount: notAcceptedCount,
            acceptanceRate: acceptanceRate,
            feedbackRankChangeCount: feedbackRankChangeCount,
            feedbackScoreDeltaCount: feedbackScoreDeltaCount,
            selectedActionIDs: selectedActionIDs,
            selectedActionDomainIDs: selectedActionDomainIDs
        )
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
