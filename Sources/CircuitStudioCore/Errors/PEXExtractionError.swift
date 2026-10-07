import Foundation
import PEXEngine

public enum PEXExtractionError: Error, LocalizedError, Equatable {
    case configurationReadFailed(String)
    case configurationDecodeFailed(String)
    case disabledConfiguration
    case executionFailed(PEXRunResult)
    case missingCorner(String)

    public var errorDescription: String? {
        switch self {
        case .configurationReadFailed(let message):
            return "Failed to read PEX configuration: \(message)"
        case .configurationDecodeFailed(let message):
            return "Failed to decode PEX configuration: \(message)"
        case .disabledConfiguration:
            return "PEX configuration is disabled."
        case .executionFailed(let result):
            return "PEX run '\(result.runID)' ended with \(result.status); evidence: \(result.manifestURL.path(percentEncoded: false))"
        case .missingCorner(let cornerID):
            return "PEX run did not produce corner '\(cornerID)'."
        }
    }
}
