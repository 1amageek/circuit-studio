import Foundation
import CircuitStudioCore

public struct RunReviewSignoffRepairCandidateCycleHistoryIndexService: Sendable {
    public enum ValidationError: Error, LocalizedError, Equatable {
        case invalidSummary(String)
        case invalidRunSummary(String)

        public var errorDescription: String? {
            switch self {
            case .invalidSummary(let reason):
                return "Invalid candidate-cycle history summary: \(reason)"
            case .invalidRunSummary(let reason):
                return "Invalid candidate-cycle run summary: \(reason)"
            }
        }
    }

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
            self.selectedActionIDs = try container.decode([String].self, forKey: .selectedActionIDs)
            self.selectedActionDomainIDs = try container.decode(
                [String].self,
                forKey: .selectedActionDomainIDs
            )
            self.selectedObjectiveDomainIDs = try container.decode(
                [String].self,
                forKey: .selectedObjectiveDomainIDs
            )
            self.objectiveDomainSummaries = try container.decode(
                [RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary].self,
                forKey: .objectiveDomainSummaries
            )
            self.feedbackPenalizedActionIDs = try container.decode(
                [String].self,
                forKey: .feedbackPenalizedActionIDs
            )
            self.feedbackRankChangedActionIDs = try container.decode(
                [String].self,
                forKey: .feedbackRankChangedActionIDs
            )
            self.feedbackScoreDeltaActionIDs = try container.decode(
                [String].self,
                forKey: .feedbackScoreDeltaActionIDs
            )
            self.runs = try container.decode([RunSummary].self, forKey: .runs)
            self.recommendations = try container.decode([String].self, forKey: .recommendations)
            do {
                try validate()
            } catch {
                throw DecodingError.dataCorruptedError(
                    forKey: .runCount,
                    in: container,
                    debugDescription: error.localizedDescription
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            do {
                try validate()
            } catch {
                throw EncodingError.invalidValue(
                    self,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: error.localizedDescription
                    )
                )
            }
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

        public func validate() throws {
            let counts = [
                runCount,
                cycleCount,
                acceptedCount,
                notAcceptedCount,
                consumedRejectedPlanFeedbackRecordCount,
                maximumGlobalRejectedPlanFeedbackCount,
                feedbackRankChangeCount,
                feedbackScoreDeltaCount,
            ]
            guard counts.allSatisfy({ $0 >= 0 }) else {
                throw ValidationError.invalidSummary("Counts must be nonnegative.")
            }
            guard runCount == runs.count else {
                throw ValidationError.invalidSummary("runCount must equal the number of run summaries.")
            }
            guard cycleCount == acceptedCount + notAcceptedCount else {
                throw ValidationError.invalidSummary("cycleCount must equal acceptedCount plus notAcceptedCount.")
            }
            for run in runs {
                try run.validate()
            }
            guard cycleCount == runs.reduce(0, { $0 + $1.cycleCount }),
                  acceptedCount == runs.reduce(0, { $0 + $1.acceptedCount }),
                  notAcceptedCount == runs.reduce(0, { $0 + $1.notAcceptedCount }),
                  consumedRejectedPlanFeedbackRecordCount == runs.reduce(
                    0,
                    { $0 + $1.consumedRejectedPlanFeedbackRecordCount }
                  ),
                  feedbackRankChangeCount == runs.reduce(0, { $0 + $1.feedbackRankChangeCount }),
                  feedbackScoreDeltaCount == runs.reduce(0, { $0 + $1.feedbackScoreDeltaCount }) else {
                throw ValidationError.invalidSummary("Aggregate counts must match the retained run summaries.")
            }
            let expectedMaximumFeedbackCount = runs
                .map(\.maximumGlobalRejectedPlanFeedbackCount)
                .max() ?? 0
            guard maximumGlobalRejectedPlanFeedbackCount == expectedMaximumFeedbackCount else {
                throw ValidationError.invalidSummary(
                    "maximumGlobalRejectedPlanFeedbackCount must match the retained run summaries."
                )
            }
            let identifierCollections = [
                selectedActionIDs,
                selectedActionDomainIDs,
                selectedObjectiveDomainIDs,
                feedbackPenalizedActionIDs,
                feedbackRankChangedActionIDs,
                feedbackScoreDeltaActionIDs,
            ]
            guard identifierCollections.allSatisfy(Self.hasValidUniqueIdentifiers) else {
                throw ValidationError.invalidSummary("Identifier collections must contain unique, trimmed values.")
            }
            guard Self.hasValidUniqueIdentifiers(objectiveDomainSummaries.map(\.domainID)) else {
                throw ValidationError.invalidSummary("Objective-domain summaries must have unique, trimmed IDs.")
            }
            for domain in objectiveDomainSummaries {
                let domainCounts = [
                    domain.cycleCount,
                    domain.acceptedCount,
                    domain.notAcceptedCount,
                    domain.feedbackRankChangeCount,
                    domain.feedbackScoreDeltaCount,
                ]
                guard domainCounts.allSatisfy({ $0 >= 0 }),
                      domain.cycleCount == domain.acceptedCount + domain.notAcceptedCount,
                      domain.acceptanceRate.isFinite,
                      domain.acceptanceRate >= 0,
                      domain.acceptanceRate <= 1,
                      Self.hasValidUniqueIdentifiers(domain.selectedActionIDs),
                      Self.hasValidUniqueIdentifiers(domain.selectedActionDomainIDs) else {
                    throw ValidationError.invalidSummary(
                        "Objective-domain summary \(domain.domainID) is internally inconsistent."
                    )
                }
                let expectedRate = domain.cycleCount == 0
                    ? 0
                    : Double(domain.acceptedCount) / Double(domain.cycleCount)
                guard abs(domain.acceptanceRate - expectedRate) <= 1e-12 else {
                    throw ValidationError.invalidSummary(
                        "Objective-domain summary \(domain.domainID) has an inconsistent acceptance rate."
                    )
                }
            }
        }

        private static func hasValidUniqueIdentifiers(_ values: [String]) -> Bool {
            values.allSatisfy {
                !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines)
            } && Set(values).count == values.count
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
            self.selectedActionIDs = try container.decode([String].self, forKey: .selectedActionIDs)
            self.selectedActionDomainIDs = try container.decode(
                [String].self,
                forKey: .selectedActionDomainIDs
            )
            self.selectedObjectiveDomainIDs = try container.decode(
                [String].self,
                forKey: .selectedObjectiveDomainIDs
            )
            self.objectiveDomainSummaries = try container.decode(
                [RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary].self,
                forKey: .objectiveDomainSummaries
            )
            self.feedbackPenalizedActionIDs = try container.decode(
                [String].self,
                forKey: .feedbackPenalizedActionIDs
            )
            self.feedbackRankChangedActionIDs = try container.decode(
                [String].self,
                forKey: .feedbackRankChangedActionIDs
            )
            self.feedbackScoreDeltaActionIDs = try container.decode(
                [String].self,
                forKey: .feedbackScoreDeltaActionIDs
            )
            do {
                try validate()
            } catch {
                throw DecodingError.dataCorruptedError(
                    forKey: .runID,
                    in: container,
                    debugDescription: error.localizedDescription
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            do {
                try validate()
            } catch {
                throw EncodingError.invalidValue(
                    self,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: error.localizedDescription
                    )
                )
            }
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

        public func validate() throws {
            guard !runID.isEmpty,
                  runID == runID.trimmingCharacters(in: .whitespacesAndNewlines),
                  !summaryPath.isEmpty,
                  summaryPath == summaryPath.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw ValidationError.invalidRunSummary("Run ID and summary path must be trimmed and nonempty.")
            }
            let counts = [
                cycleCount,
                acceptedCount,
                notAcceptedCount,
                consumedRejectedPlanFeedbackRecordCount,
                maximumGlobalRejectedPlanFeedbackCount,
                feedbackRankChangeCount,
                feedbackScoreDeltaCount,
            ]
            guard counts.allSatisfy({ $0 >= 0 }),
                  cycleCount == acceptedCount + notAcceptedCount else {
                throw ValidationError.invalidRunSummary("Run counts are internally inconsistent.")
            }
            guard (latestCycleIndex == nil) == (latestAccepted == nil),
                  latestCycleIndex.map({ $0 >= 0 }) ?? true else {
                throw ValidationError.invalidRunSummary(
                    "Latest cycle index and acceptance must both be present or both be absent."
                )
            }
            let identifierCollections = [
                selectedActionIDs,
                selectedActionDomainIDs,
                selectedObjectiveDomainIDs,
                feedbackPenalizedActionIDs,
                feedbackRankChangedActionIDs,
                feedbackScoreDeltaActionIDs,
                objectiveDomainSummaries.map(\.domainID),
            ]
            guard identifierCollections.allSatisfy(Self.hasValidUniqueIdentifiers) else {
                throw ValidationError.invalidRunSummary(
                    "Run identifier collections must contain unique, trimmed values."
                )
            }
        }

        private static func hasValidUniqueIdentifiers(_ values: [String]) -> Bool {
            values.allSatisfy {
                !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines)
            } && Set(values).count == values.count
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
