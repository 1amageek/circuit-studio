import Foundation
import CoreSpiceWaveform

/// The outcome of a simulation run.
public struct SimulationResult: Sendable, Identifiable {
    public let id: UUID
    public let experimentID: UUID
    public let status: RunStatus
    public let startedAt: Date
    public let finishedAt: Date?
    public var waveform: WaveformData?
    public var logMessages: [String]

    public init(
        id: UUID = UUID(),
        experimentID: UUID,
        status: RunStatus,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        waveform: WaveformData? = nil,
        logMessages: [String] = []
    ) {
        self.id = id
        self.experimentID = experimentID
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.waveform = waveform
        self.logMessages = logMessages
    }
}

/// Status of a simulation run.
public enum RunStatus: String, Sendable, Codable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}
