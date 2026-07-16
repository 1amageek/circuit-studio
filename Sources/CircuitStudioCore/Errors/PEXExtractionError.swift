import Foundation

public enum PEXExtractionError: Error, LocalizedError, Equatable {
    case configurationReadFailed(String)
    case configurationDecodeFailed(String)
    case disabledConfiguration
    case missingCorner(String)

    public var errorDescription: String? {
        switch self {
        case .configurationReadFailed(let message):
            return "Failed to read PEX configuration: \(message)"
        case .configurationDecodeFailed(let message):
            return "Failed to decode PEX configuration: \(message)"
        case .disabledConfiguration:
            return "PEX configuration is disabled."
        case .missingCorner(let cornerID):
            return "PEX run did not produce corner '\(cornerID)'."
        }
    }
}
