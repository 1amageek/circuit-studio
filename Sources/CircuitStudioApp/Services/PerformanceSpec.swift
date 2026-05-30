import Foundation

/// A measurable electrical performance target a design must meet — the pre-layout
/// "intent" the agent loop drives toward (delay, gain, slew, …). This is the missing
/// piece between "the design simulates" and "the design meets its spec": the Decide
/// stage compares a measured metric against this target.
public struct PerformanceSpec: Sendable, Hashable, Codable {

    public enum Metric: String, Sendable, Hashable, Codable {
        /// Input→output propagation delay (seconds), measured at the 50% level.
        case propagationDelaySeconds
    }

    public enum Comparison: String, Sendable, Hashable, Codable {
        case atMost   // measured must be <= target
        case atLeast  // measured must be >= target
    }

    public let metric: Metric
    public let comparison: Comparison
    public let target: Double

    public init(metric: Metric, comparison: Comparison, target: Double) {
        self.metric = metric
        self.comparison = comparison
        self.target = target
    }

    /// Whether a measured value satisfies the target.
    public func isMet(by measured: Double) -> Bool {
        switch comparison {
        case .atMost: return measured <= target
        case .atLeast: return measured >= target
        }
    }

    /// How far the measurement is from meeting the spec, signed so that a positive
    /// value is a failing margin (the amount by which it misses). Zero or negative
    /// means the spec is met with that much slack.
    public func shortfall(of measured: Double) -> Double {
        switch comparison {
        case .atMost: return measured - target   // too large by this much
        case .atLeast: return target - measured  // too small by this much
        }
    }
}
