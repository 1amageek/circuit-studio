import Foundation

public enum WaveformArtifactError: Error, LocalizedError, Equatable {
    case invalidPayload(String)
    case requiresLocalFileURL(String)
    case inputMissing(path: String)
    case inputIsDirectory(path: String)
    case decodeFailed(format: WaveformArtifactFormat, path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidPayload(let payload):
            return "Waveform artifact payload is not a valid URL: \(payload)"
        case .requiresLocalFileURL(let payload):
            return "Waveform artifact requires a local file URL: \(payload)"
        case .inputMissing(let path):
            return "Waveform artifact is missing: \(path)"
        case .inputIsDirectory(let path):
            return "Waveform artifact points to a directory: \(path)"
        case .decodeFailed(let format, let path, let reason):
            return "Failed to decode \(format.rawValue) waveform at \(path): \(reason)"
        }
    }
}
