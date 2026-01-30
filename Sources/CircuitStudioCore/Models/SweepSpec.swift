import Foundation

/// Defines a parameter sweep for batch simulation.
public struct SweepSpec: Sendable, Codable, Hashable {
    public var parameterName: String
    public var values: SweepValues

    public init(parameterName: String, values: SweepValues) {
        self.parameterName = parameterName
        self.values = values
    }
}

/// How sweep values are specified.
public enum SweepValues: Sendable, Codable, Hashable {
    case linear(start: Double, stop: Double, step: Double)
    case list([Double])

    public var allValues: [Double] {
        switch self {
        case .linear(let start, let stop, let step):
            guard step > 0, stop >= start else { return [] }
            var values: [Double] = []
            var current = start
            while current <= stop + step * 0.001 {
                values.append(current)
                current += step
            }
            return values
        case .list(let values):
            return values
        }
    }
}
