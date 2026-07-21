import Foundation

public protocol SignoffCommandRunning: Sendable {
    func run(
        commands: [ExternalSignoffCommand],
        artifactDirectory: URL
    ) async throws -> ExternalSignoffBatchResult
}
