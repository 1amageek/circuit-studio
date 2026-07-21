import Foundation

public enum ExternalSignoffExecutionFailure: Error, LocalizedError, Equatable, Codable {
    case invalidRunnerConfiguration(String)
    case launchFailed(message: String)
    case cancellationCheckFailed(message: String, standardOutput: String, standardError: String)
    case cancelled(standardOutput: String, standardError: String)
    case timedOut(timeoutSeconds: Double, standardOutput: String, standardError: String)

    public var errorDescription: String? {
        switch self {
        case .invalidRunnerConfiguration(let message):
            return "Invalid external signoff runner configuration: \(message)"
        case .launchFailed(let message):
            return "External signoff process failed to launch: \(message)"
        case .cancellationCheckFailed(let message, _, _):
            return "External signoff cancellation check failed: \(message)"
        case .cancelled:
            return "External signoff process was cancelled."
        case .timedOut(let timeoutSeconds, _, _):
            return "External signoff process timed out after \(timeoutSeconds)s."
        }
    }
}
