import Foundation

/// A completed analysis × corner matrix run, retained so results stay
/// browsable in the UI after later runs.
public struct AnalysisRunBatch: Sendable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public let records: [AnalysisRunRecord]

    public init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        records: [AnalysisRunRecord]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.records = records
    }
}
