import Foundation

public enum ExternalSignoffCommandError: Error, LocalizedError, Equatable {
    case invalidExecutablePath(String)
    case invalidLogFileName(String)
    case artifactWriteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidExecutablePath(let path):
            return "Invalid external signoff executable path: \(path)"
        case .invalidLogFileName(let name):
            return "Invalid external signoff log file name: \(name)"
        case .artifactWriteFailed(let message):
            return "External signoff artifact write failed: \(message)"
        }
    }
}
