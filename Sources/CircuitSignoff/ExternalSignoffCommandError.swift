import CircuiteFoundation
import Foundation

public enum ExternalSignoffCommandError: Error, LocalizedError, Equatable {
    case invalidExecutablePath(String)
    case executableIsNotARegularFile(String)
    case sourceExecutableDigestMismatch(producer: ProducerIdentity, path: String)
    case invalidSensitiveArgumentIndex(index: Int, argumentCount: Int)
    case duplicateSensitiveArgumentIndex(Int)
    case unknownSensitiveEnvironmentKey(String)
    case invalidLogFileName(String)
    case invalidMetadata(String)
    case immutableArtifactConflict(String)
    case artifactWriteFailed(String)
    case executionFailed(producer: ProducerIdentity, failure: ExternalSignoffExecutionFailure)

    public var errorDescription: String? {
        switch self {
        case .invalidExecutablePath(let path):
            return "Invalid external signoff executable path: \(path)"
        case .executableIsNotARegularFile(let path):
            return "External signoff executable is not a regular file: \(path)"
        case .sourceExecutableDigestMismatch(_, let path):
            return "External signoff source executable no longer matches its measured digest: \(path)"
        case .invalidSensitiveArgumentIndex(let index, let argumentCount):
            return "Sensitive external signoff argument index \(index) is outside 0..<\(argumentCount)."
        case .duplicateSensitiveArgumentIndex(let index):
            return "Sensitive external signoff argument index \(index) is duplicated."
        case .unknownSensitiveEnvironmentKey(let key):
            return "Sensitive external signoff environment key is not present in the supplied environment: \(key)"
        case .invalidLogFileName(let name):
            return "Invalid external signoff log file name: \(name)"
        case .invalidMetadata(let message):
            return "Invalid external signoff metadata: \(message)"
        case .immutableArtifactConflict(let path):
            return "External signoff artifact is immutable and already contains different content: \(path)"
        case .artifactWriteFailed(let message):
            return "External signoff artifact write failed: \(message)"
        case .executionFailed(_, let failure):
            return failure.errorDescription
        }
    }
}
