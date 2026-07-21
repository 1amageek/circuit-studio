import CircuiteFoundation
import Foundation

public struct ExternalSignoffBatchError: Error, LocalizedError {
    public let completedResults: [ExternalSignoffCommandResult]
    public let failedCommandIndex: Int
    public let failedProducer: ProducerIdentity?
    public let evidenceURL: URL?
    public let cause: ExternalSignoffCommandError

    public init(
        completedResults: [ExternalSignoffCommandResult],
        failedCommandIndex: Int,
        failedProducer: ProducerIdentity?,
        evidenceURL: URL?,
        cause: ExternalSignoffCommandError
    ) {
        self.completedResults = completedResults
        self.failedCommandIndex = failedCommandIndex
        self.failedProducer = failedProducer
        self.evidenceURL = evidenceURL
        self.cause = cause
    }

    public var errorDescription: String? {
        "External signoff command \(failedCommandIndex) failed: \(cause.localizedDescription)"
    }
}
