import Foundation
import CircuitStudioCore

public struct RunReviewSignoffRepairCandidateCycleHistoryIndexService: Sendable {
    public struct Summary: Sendable, Hashable, Codable {
        public let runCount: Int
        public let cycleCount: Int
        public let acceptedCount: Int
        public let notAcceptedCount: Int
        public let consumedRejectedPlanFeedbackRecordCount: Int
        public let maximumGlobalRejectedPlanFeedbackCount: Int
        public let feedbackRankChangeCount: Int
        public let feedbackScoreDeltaCount: Int
        public let selectedActionIDs: [String]
        public let selectedActionDomainIDs: [String]
        public let selectedObjectiveDomainIDs: [String]
        public let objectiveDomainSummaries: [RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary]
        public let feedbackPenalizedActionIDs: [String]
        public let feedbackRankChangedActionIDs: [String]
        public let feedbackScoreDeltaActionIDs: [String]
        public let runs: [RunSummary]
        public let recommendations: [String]

        public init(
            runCount: Int,
            cycleCount: Int,
            acceptedCount: Int,
            notAcceptedCount: Int,
            consumedRejectedPlanFeedbackRecordCount: Int,
            maximumGlobalRejectedPlanFeedbackCount: Int,
            feedbackRankChangeCount: Int,
            feedbackScoreDeltaCount: Int,
            selectedActionIDs: [String],
            selectedActionDomainIDs: [String] = [],
            selectedObjectiveDomainIDs: [String] = [],
            objectiveDomainSummaries: [RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary] = [],
            feedbackPenalizedActionIDs: [String],
            feedbackRankChangedActionIDs: [String],
            feedbackScoreDeltaActionIDs: [String],
            runs: [RunSummary],
            recommendations: [String]
        ) {
            self.runCount = runCount
            self.cycleCount = cycleCount
            self.acceptedCount = acceptedCount
            self.notAcceptedCount = notAcceptedCount
            self.consumedRejectedPlanFeedbackRecordCount = consumedRejectedPlanFeedbackRecordCount
            self.maximumGlobalRejectedPlanFeedbackCount = maximumGlobalRejectedPlanFeedbackCount
            self.feedbackRankChangeCount = feedbackRankChangeCount
            self.feedbackScoreDeltaCount = feedbackScoreDeltaCount
            self.selectedActionIDs = selectedActionIDs
            self.selectedActionDomainIDs = selectedActionDomainIDs
            self.selectedObjectiveDomainIDs = selectedObjectiveDomainIDs
            self.objectiveDomainSummaries = objectiveDomainSummaries
            self.feedbackPenalizedActionIDs = feedbackPenalizedActionIDs
            self.feedbackRankChangedActionIDs = feedbackRankChangedActionIDs
            self.feedbackScoreDeltaActionIDs = feedbackScoreDeltaActionIDs
            self.runs = runs
            self.recommendations = recommendations
        }

        private enum CodingKeys: String, CodingKey {
            case runCount
            case cycleCount
            case acceptedCount
            case notAcceptedCount
            case consumedRejectedPlanFeedbackRecordCount
            case maximumGlobalRejectedPlanFeedbackCount
            case feedbackRankChangeCount
            case feedbackScoreDeltaCount
            case selectedActionIDs
            case selectedActionDomainIDs
            case selectedObjectiveDomainIDs
            case objectiveDomainSummaries
            case feedbackPenalizedActionIDs
            case feedbackRankChangedActionIDs
            case feedbackScoreDeltaActionIDs
            case runs
            case recommendations
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.runCount = try container.decode(Int.self, forKey: .runCount)
            self.cycleCount = try container.decode(Int.self, forKey: .cycleCount)
            self.acceptedCount = try container.decode(Int.self, forKey: .acceptedCount)
            self.notAcceptedCount = try container.decode(Int.self, forKey: .notAcceptedCount)
            self.consumedRejectedPlanFeedbackRecordCount = try container.decode(
                Int.self,
                forKey: .consumedRejectedPlanFeedbackRecordCount
            )
            self.maximumGlobalRejectedPlanFeedbackCount = try container.decode(
                Int.self,
                forKey: .maximumGlobalRejectedPlanFeedbackCount
            )
            self.feedbackRankChangeCount = try container.decode(Int.self, forKey: .feedbackRankChangeCount)
            self.feedbackScoreDeltaCount = try container.decode(Int.self, forKey: .feedbackScoreDeltaCount)
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
            self.feedbackRankChangedActionIDs = try container.decodeIfPresent(
                [String].self,
                forKey: .feedbackRankChangedActionIDs
            ) ?? []
            self.feedbackScoreDeltaActionIDs = try container.decodeIfPresent(
                [String].self,
                forKey: .feedbackScoreDeltaActionIDs
            ) ?? []
            self.runs = try container.decodeIfPresent([RunSummary].self, forKey: .runs) ?? []
            self.recommendations = try container.decodeIfPresent([String].self, forKey: .recommendations) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(runCount, forKey: .runCount)
            try container.encode(cycleCount, forKey: .cycleCount)
            try container.encode(acceptedCount, forKey: .acceptedCount)
            try container.encode(notAcceptedCount, forKey: .notAcceptedCount)
            try container.encode(
                consumedRejectedPlanFeedbackRecordCount,
                forKey: .consumedRejectedPlanFeedbackRecordCount
            )
            try container.encode(
                maximumGlobalRejectedPlanFeedbackCount,
                forKey: .maximumGlobalRejectedPlanFeedbackCount
            )
            try container.encode(feedbackRankChangeCount, forKey: .feedbackRankChangeCount)
            try container.encode(feedbackScoreDeltaCount, forKey: .feedbackScoreDeltaCount)
            try container.encode(selectedActionIDs, forKey: .selectedActionIDs)
            try container.encode(selectedActionDomainIDs, forKey: .selectedActionDomainIDs)
            try container.encode(selectedObjectiveDomainIDs, forKey: .selectedObjectiveDomainIDs)
            try container.encode(objectiveDomainSummaries, forKey: .objectiveDomainSummaries)
            try container.encode(feedbackPenalizedActionIDs, forKey: .feedbackPenalizedActionIDs)
            try container.encode(feedbackRankChangedActionIDs, forKey: .feedbackRankChangedActionIDs)
            try container.encode(feedbackScoreDeltaActionIDs, forKey: .feedbackScoreDeltaActionIDs)
            try container.encode(runs, forKey: .runs)
            try container.encode(recommendations, forKey: .recommendations)
        }
    }

    public struct RunSummary: Sendable, Hashable, Codable {
        public let runID: String
        public let summaryPath: String
        public let cycleCount: Int
        public let acceptedCount: Int
        public let notAcceptedCount: Int
        public let latestCycleIndex: Int?
        public let latestAccepted: Bool?
        public let consumedRejectedPlanFeedbackRecordCount: Int
        public let maximumGlobalRejectedPlanFeedbackCount: Int
        public let feedbackRankChangeCount: Int
        public let feedbackScoreDeltaCount: Int
        public let selectedActionIDs: [String]
        public let selectedActionDomainIDs: [String]
        public let selectedObjectiveDomainIDs: [String]
        public let objectiveDomainSummaries: [RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary]
        public let feedbackPenalizedActionIDs: [String]
        public let feedbackRankChangedActionIDs: [String]
        public let feedbackScoreDeltaActionIDs: [String]

        public init(
            runID: String,
            summaryPath: String,
            summary: RunReviewSignoffRepairCandidateCycleHistorySummary
        ) {
            self.runID = runID
            self.summaryPath = summaryPath
            self.cycleCount = summary.cycleCount
            self.acceptedCount = summary.acceptedCount
            self.notAcceptedCount = summary.notAcceptedCount
            self.latestCycleIndex = summary.latestCycleIndex
            self.latestAccepted = summary.latestAccepted
            self.consumedRejectedPlanFeedbackRecordCount = summary.consumedRejectedPlanFeedbackRecordCount
            self.maximumGlobalRejectedPlanFeedbackCount = summary.maximumGlobalRejectedPlanFeedbackCount
            self.feedbackRankChangeCount = summary.feedbackRankChangeCount
            self.feedbackScoreDeltaCount = summary.feedbackScoreDeltaCount
            self.selectedActionIDs = summary.selectedActionIDs
            self.selectedActionDomainIDs = summary.selectedActionDomainIDs
            self.selectedObjectiveDomainIDs = summary.selectedObjectiveDomainIDs
            self.objectiveDomainSummaries = summary.objectiveDomainSummaries
            self.feedbackPenalizedActionIDs = summary.feedbackPenalizedActionIDs
            self.feedbackRankChangedActionIDs = summary.feedbackRankChangedActionIDs
            self.feedbackScoreDeltaActionIDs = summary.feedbackScoreDeltaActionIDs
        }

        private enum CodingKeys: String, CodingKey {
            case runID
            case summaryPath
            case cycleCount
            case acceptedCount
            case notAcceptedCount
            case latestCycleIndex
            case latestAccepted
            case consumedRejectedPlanFeedbackRecordCount
            case maximumGlobalRejectedPlanFeedbackCount
            case feedbackRankChangeCount
            case feedbackScoreDeltaCount
            case selectedActionIDs
            case selectedActionDomainIDs
            case selectedObjectiveDomainIDs
            case objectiveDomainSummaries
            case feedbackPenalizedActionIDs
            case feedbackRankChangedActionIDs
            case feedbackScoreDeltaActionIDs
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.runID = try container.decode(String.self, forKey: .runID)
            self.summaryPath = try container.decode(String.self, forKey: .summaryPath)
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
            self.feedbackRankChangeCount = try container.decode(Int.self, forKey: .feedbackRankChangeCount)
            self.feedbackScoreDeltaCount = try container.decode(Int.self, forKey: .feedbackScoreDeltaCount)
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
            self.feedbackRankChangedActionIDs = try container.decodeIfPresent(
                [String].self,
                forKey: .feedbackRankChangedActionIDs
            ) ?? []
            self.feedbackScoreDeltaActionIDs = try container.decodeIfPresent(
                [String].self,
                forKey: .feedbackScoreDeltaActionIDs
            ) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(runID, forKey: .runID)
            try container.encode(summaryPath, forKey: .summaryPath)
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
            try container.encode(feedbackRankChangeCount, forKey: .feedbackRankChangeCount)
            try container.encode(feedbackScoreDeltaCount, forKey: .feedbackScoreDeltaCount)
            try container.encode(selectedActionIDs, forKey: .selectedActionIDs)
            try container.encode(selectedActionDomainIDs, forKey: .selectedActionDomainIDs)
            try container.encode(selectedObjectiveDomainIDs, forKey: .selectedObjectiveDomainIDs)
            try container.encode(objectiveDomainSummaries, forKey: .objectiveDomainSummaries)
            try container.encode(feedbackPenalizedActionIDs, forKey: .feedbackPenalizedActionIDs)
            try container.encode(feedbackRankChangedActionIDs, forKey: .feedbackRankChangedActionIDs)
            try container.encode(feedbackScoreDeltaActionIDs, forKey: .feedbackScoreDeltaActionIDs)
        }
    }

    private let decoder: JSONDecoder

    public init() {
        self.decoder = JSONDecoder()
    }

    public func summarize(forProjectAt projectRoot: URL) throws -> Summary {
        let runsDirectory = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
        guard FileManager.default.fileExists(atPath: runsDirectory.path(percentEncoded: false)) else {
            return emptySummary()
        }

        let runSummaries = try summaryURLs(in: runsDirectory).map { url in
            let runID = url
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .lastPathComponent
            let summary = try readSummary(from: url)
            return RunSummary(
                runID: runID,
                summaryPath: ".xcircuite/runs/\(runID)/planning/candidate-cycle-history-summary.json",
                summary: summary
            )
        }
        return summarize(runSummaries: runSummaries)
    }

    public func summarize(runSummaries: [RunSummary]) -> Summary {
        let sortedRuns = runSummaries.sorted { left, right in
            left.runID < right.runID
        }
        let cycleCount = sortedRuns.reduce(0) { $0 + $1.cycleCount }
        let acceptedCount = sortedRuns.reduce(0) { $0 + $1.acceptedCount }
        let notAcceptedCount = sortedRuns.reduce(0) { $0 + $1.notAcceptedCount }
        let consumedFeedbackCount = sortedRuns.reduce(0) {
            $0 + $1.consumedRejectedPlanFeedbackRecordCount
        }
        let maximumGlobalFeedbackCount = sortedRuns
            .map(\.maximumGlobalRejectedPlanFeedbackCount)
            .max() ?? 0
        let rankChangeCount = sortedRuns.reduce(0) { $0 + $1.feedbackRankChangeCount }
        let scoreDeltaCount = sortedRuns.reduce(0) { $0 + $1.feedbackScoreDeltaCount }
        let rankChangedActionIDs = Self.uniquePreservingOrder(
            sortedRuns.flatMap(\.feedbackRankChangedActionIDs)
        )
        let scoreDeltaActionIDs = Self.uniquePreservingOrder(
            sortedRuns.flatMap(\.feedbackScoreDeltaActionIDs)
        )
        let selectedActionIDs = Self.uniquePreservingOrder(
            sortedRuns.flatMap(\.selectedActionIDs)
        )
        let selectedActionDomainIDs = Self.uniquePreservingOrder(
            sortedRuns.flatMap(\.selectedActionDomainIDs)
        )
        let selectedObjectiveDomainIDs = Self.uniquePreservingOrder(
            sortedRuns.flatMap(\.selectedObjectiveDomainIDs)
        )
        let objectiveDomainSummaries = RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary.aggregate(
            summaries: sortedRuns.flatMap(\.objectiveDomainSummaries)
        )
        let feedbackPenalizedActionIDs = Self.uniquePreservingOrder(
            sortedRuns.flatMap(\.feedbackPenalizedActionIDs)
        )

        return Summary(
            runCount: sortedRuns.count,
            cycleCount: cycleCount,
            acceptedCount: acceptedCount,
            notAcceptedCount: notAcceptedCount,
            consumedRejectedPlanFeedbackRecordCount: consumedFeedbackCount,
            maximumGlobalRejectedPlanFeedbackCount: maximumGlobalFeedbackCount,
            feedbackRankChangeCount: rankChangeCount,
            feedbackScoreDeltaCount: scoreDeltaCount,
            selectedActionIDs: selectedActionIDs,
            selectedActionDomainIDs: selectedActionDomainIDs,
            selectedObjectiveDomainIDs: selectedObjectiveDomainIDs,
            objectiveDomainSummaries: objectiveDomainSummaries,
            feedbackPenalizedActionIDs: feedbackPenalizedActionIDs,
            feedbackRankChangedActionIDs: rankChangedActionIDs,
            feedbackScoreDeltaActionIDs: scoreDeltaActionIDs,
            runs: sortedRuns,
            recommendations: recommendations(
                runCount: sortedRuns.count,
                acceptedCount: acceptedCount,
                notAcceptedCount: notAcceptedCount,
                rankChangeCount: rankChangeCount
            )
        )
    }

    private func summaryURLs(in runsDirectory: URL) throws -> [URL] {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: runsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw StudioError.projectLoadFailed("Failed to list candidate-cycle runs: \(error.localizedDescription)")
        }

        return entries
            .map {
                $0
                    .appending(path: "planning")
                    .appending(path: "candidate-cycle-history-summary.json")
            }
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
            .sorted { left, right in
                left.path(percentEncoded: false) < right.path(percentEncoded: false)
            }
    }

    private func readSummary(
        from url: URL
    ) throws -> RunReviewSignoffRepairCandidateCycleHistorySummary {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StudioError.projectLoadFailed("Failed to read candidate-cycle summary: \(error.localizedDescription)")
        }

        do {
            return try decoder.decode(RunReviewSignoffRepairCandidateCycleHistorySummary.self, from: data)
        } catch {
            throw StudioError.projectLoadFailed("Failed to decode candidate-cycle summary: \(error.localizedDescription)")
        }
    }

    private func emptySummary() -> Summary {
        Summary(
            runCount: 0,
            cycleCount: 0,
            acceptedCount: 0,
            notAcceptedCount: 0,
            consumedRejectedPlanFeedbackRecordCount: 0,
            maximumGlobalRejectedPlanFeedbackCount: 0,
            feedbackRankChangeCount: 0,
            feedbackScoreDeltaCount: 0,
            selectedActionIDs: [],
            selectedActionDomainIDs: [],
            selectedObjectiveDomainIDs: [],
            objectiveDomainSummaries: [],
            feedbackPenalizedActionIDs: [],
            feedbackRankChangedActionIDs: [],
            feedbackScoreDeltaActionIDs: [],
            runs: [],
            recommendations: ["No signoff repair candidate-cycle summaries were found."]
        )
    }

    private func recommendations(
        runCount: Int,
        acceptedCount: Int,
        notAcceptedCount: Int,
        rankChangeCount: Int
    ) -> [String] {
        guard runCount > 0 else {
            return ["No signoff repair candidate-cycle summaries were found."]
        }
        var values: [String] = []
        if rankChangeCount > 0 {
            values.append("Retain feedback-sensitive ranking evidence across the next corpus run.")
        }
        if notAcceptedCount > acceptedCount {
            values.append("Prioritize failed cycle diagnostics before broadening candidate families.")
        }
        if values.isEmpty {
            values.append("No repeated candidate-cycle repair bottleneck is visible yet.")
        }
        return values
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
