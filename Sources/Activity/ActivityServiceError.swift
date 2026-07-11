import Foundation

public enum ActivityServiceError: Error, LocalizedError, Equatable, Sendable {
    case projectManifestUnavailable(path: String)

    public var errorDescription: String? {
        switch self {
        case .projectManifestUnavailable(let path):
            return "Activity requires a valid .xcircuite project manifest at '\(path)'."
        }
    }
}
