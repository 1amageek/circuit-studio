import Foundation

/// Typed errors for invoking the standalone `pexengine` executable.
public enum PEXCommandError: Error, Sendable {
    case executableNotFound
    case invalidExecutablePath(String)
    case invalidConfiguration(String)
    case launchFailed(String)
    case cancelled(stdout: String, stderr: String)
    case timedOut(executablePath: String, timeoutSeconds: Double, stdout: String, stderr: String)
    case nonZeroExit(code: Int32, stdout: String, stderr: String)
}

extension PEXCommandError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "pexengine executable was not found. Set PEXENGINE_BIN or provide an explicit executable path."
        case .invalidExecutablePath(let path):
            return "Invalid pexengine executable path: \(path)"
        case .invalidConfiguration(let message):
            return "Invalid pexengine process runner configuration: \(message)"
        case .launchFailed(let message):
            return "Failed to launch pexengine: \(message)"
        case .cancelled:
            return "pexengine execution was cancelled."
        case .timedOut(let executablePath, let timeoutSeconds, _, _):
            return "pexengine timed out after \(timeoutSeconds)s: \(executablePath)"
        case .nonZeroExit(let code, let stdout, let stderr):
            if stderr.isEmpty {
                if stdout.isEmpty {
                    return "pexengine exited with code \(code)."
                }
                return "pexengine exited with code \(code): \(stdout)"
            }
            return "pexengine exited with code \(code): \(stderr)"
        }
    }
}
