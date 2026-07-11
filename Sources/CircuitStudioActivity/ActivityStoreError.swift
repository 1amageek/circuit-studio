import Foundation

public enum ActivityStoreError: Error, LocalizedError, Equatable, Sendable {
    case immutableConflict(id: String)
    case invalidStoredRecord(id: String, reason: String)
    case invalidJSON(field: String, reason: String)
    case databaseUnavailable
    case databasePathCreationFailed(String)
    case databaseSizeUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .immutableConflict(let id):
            return "Activity record '\(id)' already exists with different content."
        case .invalidStoredRecord(let id, let reason):
            return "Activity record '\(id)' is invalid: \(reason)"
        case .invalidJSON(let field, let reason):
            return "Activity field '\(field)' contains invalid JSON: \(reason)"
        case .databaseUnavailable:
            return "Activity database is not prepared."
        case .databasePathCreationFailed(let reason):
            return "Could not prepare the Activity database directory: \(reason)"
        case .databaseSizeUnavailable(let reason):
            return "Could not read the Activity database size: \(reason)"
        }
    }
}
