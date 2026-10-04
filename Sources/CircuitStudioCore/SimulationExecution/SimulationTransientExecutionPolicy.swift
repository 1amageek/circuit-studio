import CoreSpice

/// The exact policy admitted by a completed native transient execution.
public struct SimulationTransientExecutionPolicy: Sendable, Hashable, Codable {
    public enum Source: String, Sendable, Hashable, Codable {
        case caller
        case deckOptions
    }

    public let source: Source
    public let limits: TransientExecutionLimits

    init(source: Source, limits: TransientExecutionLimits) {
        self.source = source
        self.limits = limits
    }
}
