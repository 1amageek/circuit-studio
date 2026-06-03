import Foundation

public struct ACC4FunctionalTraceArtifact: Sendable, Hashable, Codable, ArtifactPayloadValidating {
    public static let currentSchemaVersion = 1
    public static let artifactKind = "acc4-functional-trace"

    public struct TracePoint: Sendable, Hashable, Codable {
        public let cycle: Int
        public let pc: Int
        public let acc: Int

        public init(cycle: Int, pc: Int, acc: Int) {
            self.cycle = cycle
            self.pc = pc
            self.acc = acc
        }
    }

    public enum ValidationError: Error, LocalizedError, Equatable {
        case invalidSchemaVersion(Int)
        case invalidKind(String)
        case cycleCountMismatch(expected: Int, actual: Int)
        case nonMonotonicCycle(index: Int, value: Int)
        case outOfRangeState(cycle: Int, pc: Int, acc: Int)

        public var errorDescription: String? {
            switch self {
            case .invalidSchemaVersion(let version):
                return "Unsupported ACC4 functional trace schema version \(version)."
            case .invalidKind(let kind):
                return "Invalid ACC4 functional trace artifact kind '\(kind)'."
            case .cycleCountMismatch(let expected, let actual):
                return "ACC4 functional trace expected \(expected) cycles but contains \(actual)."
            case .nonMonotonicCycle(let index, let value):
                return "ACC4 functional trace point \(index) has non-monotonic cycle \(value)."
            case .outOfRangeState(let cycle, let pc, let acc):
                return "ACC4 functional trace cycle \(cycle) has out-of-range pc \(pc) or acc \(acc)."
            }
        }
    }

    public let schemaVersion: Int
    public let kind: String
    public let designName: String
    public let cycles: Int
    public let trace: [TracePoint]

    public init(designName: String, trace: [ACC4Reference.CycleState]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.kind = Self.artifactKind
        self.designName = designName
        self.cycles = trace.count
        self.trace = trace.enumerated().map { index, state in
            TracePoint(cycle: index, pc: state.pc, acc: state.acc)
        }
    }

    public func validateForPersistence() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ValidationError.invalidSchemaVersion(schemaVersion)
        }
        guard kind == Self.artifactKind else {
            throw ValidationError.invalidKind(kind)
        }
        guard trace.count == cycles else {
            throw ValidationError.cycleCountMismatch(expected: cycles, actual: trace.count)
        }
        for (index, point) in trace.enumerated() {
            guard point.cycle == index else {
                throw ValidationError.nonMonotonicCycle(index: index, value: point.cycle)
            }
            guard (0...15).contains(point.pc), (0...15).contains(point.acc) else {
                throw ValidationError.outOfRangeState(cycle: point.cycle, pc: point.pc, acc: point.acc)
            }
        }
    }
}
