import Foundation
import CoreSpiceEvent

/// Tracks the state of a running simulation job.
public struct SimulationJob: Sendable, Identifiable {
    public let id: UUID
    public let experimentID: UUID
    public var status: RunStatus
    public var progress: Double
    public var currentStep: String
    public let cancellationToken: CancellationToken

    public init(
        id: UUID = UUID(),
        experimentID: UUID,
        status: RunStatus = .pending,
        progress: Double = 0,
        currentStep: String = "",
        cancellationToken: CancellationToken = CancellationToken()
    ) {
        self.id = id
        self.experimentID = experimentID
        self.status = status
        self.progress = progress
        self.currentStep = currentStep
        self.cancellationToken = cancellationToken
    }
}
