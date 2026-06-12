import Foundation

/// One executed cell of an analysis × corner matrix run.
public struct AnalysisRunRecord: Sendable, Identifiable {
    public let id: UUID
    public let analysis: AnalysisCommand
    /// The corner this cell ran on, or nil when it ran on the base configuration.
    public let cornerName: String?
    /// The temperature the configuration dictated for this cell, or nil when
    /// nothing dictated one (the simulator's own resolution applies).
    public let temperature: Double?
    public let status: RunStatus
    public let result: SimulationResult?
    public let failureReason: String?
    public let startedAt: Date
    public let finishedAt: Date?

    public init(
        id: UUID = UUID(),
        analysis: AnalysisCommand,
        cornerName: String? = nil,
        temperature: Double? = nil,
        status: RunStatus,
        result: SimulationResult? = nil,
        failureReason: String? = nil,
        startedAt: Date = Date(),
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.analysis = analysis
        self.cornerName = cornerName
        self.temperature = temperature
        self.status = status
        self.result = result
        self.failureReason = failureReason
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
