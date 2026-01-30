import Foundation

/// Monte Carlo simulation specification.
public struct MonteCarloSpec: Sendable, Codable, Hashable {
    public var iterations: Int
    public var seed: Int?
    public var distribution: DistributionKind

    public init(iterations: Int, seed: Int? = nil, distribution: DistributionKind = .gaussian) {
        self.iterations = iterations
        self.seed = seed
        self.distribution = distribution
    }
}

/// Distribution type for Monte Carlo variations.
public enum DistributionKind: String, Sendable, Codable, Hashable {
    case gaussian
    case uniform
}
