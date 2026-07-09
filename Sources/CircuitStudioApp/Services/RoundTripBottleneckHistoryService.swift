import Foundation
import CircuitStudioCore

public struct RoundTripBottleneckHistoryService: Sendable {
    public struct Summary: Sendable, Hashable, Codable {
        public let runCount: Int
        public let failedRunCount: Int
        public let stageSummaries: [StageSummary]
        public let mostFrequentFailedStageName: String?
        public let mostExpensiveStageName: String?
        public let recommendations: [String]

        public init(
            runCount: Int,
            failedRunCount: Int,
            stageSummaries: [StageSummary],
            mostFrequentFailedStageName: String?,
            mostExpensiveStageName: String?,
            recommendations: [String]
        ) {
            self.runCount = runCount
            self.failedRunCount = failedRunCount
            self.stageSummaries = stageSummaries
            self.mostFrequentFailedStageName = mostFrequentFailedStageName
            self.mostExpensiveStageName = mostExpensiveStageName
            self.recommendations = recommendations
        }
    }

    public struct StageSummary: Sendable, Hashable, Codable {
        public let stageName: String
        public let observedCount: Int
        public let failedCount: Int
        public let totalDurationSeconds: Double
        public let averageDurationSeconds: Double
        public let maxDurationSeconds: Double

        public init(
            stageName: String,
            observedCount: Int,
            failedCount: Int,
            totalDurationSeconds: Double,
            averageDurationSeconds: Double,
            maxDurationSeconds: Double
        ) {
            self.stageName = stageName
            self.observedCount = observedCount
            self.failedCount = failedCount
            self.totalDurationSeconds = totalDurationSeconds
            self.averageDurationSeconds = averageDurationSeconds
            self.maxDurationSeconds = maxDurationSeconds
        }
    }

    private struct MutableStageSummary {
        var observedCount = 0
        var failedCount = 0
        var totalDurationSeconds = 0.0
        var maxDurationSeconds = 0.0
    }

    private let decoder: JSONDecoder

    public init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func summarize(forProjectAt projectRoot: URL) throws -> Summary {
        let runsDirectories = RoundTripRunDirectory.existingRunsDirectories(projectRoot: projectRoot)
        guard !runsDirectories.isEmpty else {
            return emptySummary()
        }

        let manifestURLs = try runsDirectories.flatMap { directory in
            try manifestURLs(in: directory)
        }
        let manifests = try manifestURLs.map { url in
            try readManifest(from: url)
        }
        return summarize(manifests: manifests)
    }

    public func summarize(manifests: [HeadlessRoundTripService.Manifest]) -> Summary {
        var stageState: [String: MutableStageSummary] = [:]
        var failedStageCounts: [String: Int] = [:]

        for manifest in manifests {
            if let failedStageName = manifest.bottleneckSummary?.failedStageName {
                failedStageCounts[failedStageName, default: 0] += 1
            }

            for stage in manifest.stages where stage.status != .skipped {
                var summary = stageState[stage.name] ?? MutableStageSummary()
                summary.observedCount += 1
                if stage.status == .failed {
                    summary.failedCount += 1
                }
                if let duration = stage.durationSeconds {
                    summary.totalDurationSeconds += duration
                    summary.maxDurationSeconds = max(summary.maxDurationSeconds, duration)
                }
                stageState[stage.name] = summary
            }
        }

        let stageSummaries = stageState
            .map { stageName, summary in
                StageSummary(
                    stageName: stageName,
                    observedCount: summary.observedCount,
                    failedCount: summary.failedCount,
                    totalDurationSeconds: summary.totalDurationSeconds,
                    averageDurationSeconds: summary.observedCount == 0
                        ? 0
                        : summary.totalDurationSeconds / Double(summary.observedCount),
                    maxDurationSeconds: summary.maxDurationSeconds
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalDurationSeconds == rhs.totalDurationSeconds {
                    return lhs.stageName < rhs.stageName
                }
                return lhs.totalDurationSeconds > rhs.totalDurationSeconds
            }

        let mostExpensiveStageName = stageSummaries.first?.stageName
        let mostFrequentFailedStageName = failedStageCounts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .first?.key

        return Summary(
            runCount: manifests.count,
            failedRunCount: manifests.filter { !$0.isRoundTripComplete }.count,
            stageSummaries: stageSummaries,
            mostFrequentFailedStageName: mostFrequentFailedStageName,
            mostExpensiveStageName: mostExpensiveStageName,
            recommendations: recommendations(
                failedStageName: mostFrequentFailedStageName,
                expensiveStageName: mostExpensiveStageName
            )
        )
    }

    private func manifestURLs(in runsDirectory: URL) throws -> [URL] {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: runsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw StudioError.projectLoadFailed("Failed to list round-trip runs: \(error.localizedDescription)")
        }

        return entries
            .map { $0.appending(path: "round-trip-manifest.json") }
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
            .sorted { lhs, rhs in
                lhs.path(percentEncoded: false) < rhs.path(percentEncoded: false)
            }
    }

    private func readManifest(from url: URL) throws -> HeadlessRoundTripService.Manifest {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StudioError.projectLoadFailed("Failed to read round-trip manifest: \(error.localizedDescription)")
        }

        do {
            return try decoder.decode(HeadlessRoundTripService.Manifest.self, from: data)
        } catch {
            throw StudioError.projectLoadFailed("Failed to decode round-trip manifest: \(error.localizedDescription)")
        }
    }

    private func emptySummary() -> Summary {
        Summary(
            runCount: 0,
            failedRunCount: 0,
            stageSummaries: [],
            mostFrequentFailedStageName: nil,
            mostExpensiveStageName: nil,
            recommendations: ["No round-trip manifests were found."]
        )
    }

    private func recommendations(
        failedStageName: String?,
        expensiveStageName: String?
    ) -> [String] {
        var values: [String] = []
        if let failedStageName {
            values.append("Prioritize repeated failures in \(failedStageName).")
        }
        if let expensiveStageName, expensiveStageName != failedStageName {
            values.append("Reduce measured runtime in \(expensiveStageName).")
        }
        if values.isEmpty {
            values.append("No repeated bottleneck is visible yet.")
        }
        return values
    }
}
