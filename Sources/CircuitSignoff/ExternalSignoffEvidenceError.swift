import Foundation

public enum ExternalSignoffEvidenceError: Error, LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidFailedCommandIndex(Int, completedResultCount: Int)
    case missingFailureReason
    case unexpectedFailureMetadata

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported external signoff evidence schema version: \(version)"
        case .invalidFailedCommandIndex(let index, let count):
            return "External signoff failed command index \(index) does not follow \(count) completed results."
        case .missingFailureReason:
            return "Failed external signoff evidence requires a sanitized failure reason."
        case .unexpectedFailureMetadata:
            return "Successful external signoff evidence cannot contain failure metadata."
        }
    }
}
