public protocol TimingCharacterizationExecutionPolicy: Sendable {
    func execute<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T
}

public struct DirectTimingCharacterizationExecutionPolicy: TimingCharacterizationExecutionPolicy {
    public init() {}

    public func execute<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await operation()
    }
}
