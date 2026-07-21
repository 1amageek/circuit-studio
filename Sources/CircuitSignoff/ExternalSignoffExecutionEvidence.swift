import CircuiteFoundation
import Foundation

public struct ExternalSignoffExecutionEvidence: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let completedResults: [ExternalSignoffCommandResult]
    public let failedCommandIndex: Int?
    public let failedProducer: ProducerIdentity?
    public let sanitizedFailureReason: String?

    public init(
        completedResults: [ExternalSignoffCommandResult],
        failedCommandIndex: Int? = nil,
        failedProducer: ProducerIdentity? = nil,
        sanitizedFailureReason: String? = nil
    ) throws {
        if let failedCommandIndex {
            guard failedCommandIndex >= 0,
                  failedCommandIndex == completedResults.count else {
                throw ExternalSignoffEvidenceError.invalidFailedCommandIndex(
                    failedCommandIndex,
                    completedResultCount: completedResults.count
                )
            }
            guard let sanitizedFailureReason,
                  !sanitizedFailureReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ExternalSignoffEvidenceError.missingFailureReason
            }
        } else if failedProducer != nil || sanitizedFailureReason != nil {
            throw ExternalSignoffEvidenceError.unexpectedFailureMetadata
        }
        self.schemaVersion = Self.currentSchemaVersion
        self.completedResults = completedResults
        self.failedCommandIndex = failedCommandIndex
        self.failedProducer = failedProducer
        self.sanitizedFailureReason = sanitizedFailureReason
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ExternalSignoffEvidenceError.unsupportedSchemaVersion(schemaVersion)
        }
        let completedResults = try container.decode(
            [ExternalSignoffCommandResult].self,
            forKey: .completedResults
        )
        let failedCommandIndex = try container.decodeIfPresent(
            Int.self,
            forKey: .failedCommandIndex
        )
        let failedProducer = try container.decodeIfPresent(
            ProducerIdentity.self,
            forKey: .failedProducer
        )
        let sanitizedFailureReason = try container.decodeIfPresent(
            String.self,
            forKey: .sanitizedFailureReason
        )
        try self.init(
            completedResults: completedResults,
            failedCommandIndex: failedCommandIndex,
            failedProducer: failedProducer,
            sanitizedFailureReason: sanitizedFailureReason
        )
    }
}
