import Foundation

/// A completed analysis × corner matrix run, retained so results stay
/// browsable in the UI after later runs.
public struct AnalysisRunBatch: Sendable, Identifiable {
    public let id: UUID
    /// Canonical `.xcircuite` run identity. Nil is reserved for isolated tests.
    public let runID: String?
    public let startedAt: Date
    public let records: [AnalysisRunRecord]

    public init(
        id: UUID = UUID(),
        runID: String? = nil,
        startedAt: Date = Date(),
        records: [AnalysisRunRecord]
    ) {
        self.id = id
        self.runID = runID
        self.startedAt = startedAt
        self.records = records
    }
}
