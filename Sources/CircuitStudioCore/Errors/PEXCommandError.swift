import Foundation

/// Typed errors for invoking the standalone `pexengine` executable.
public enum PEXCommandError: Error, Sendable {
    case executableNotFound
    case invalidExecutablePath(String)
    case launchFailed(String)
    case nonZeroExit(code: Int32, stderr: String)
}

extension PEXCommandError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "pexengine executable was not found. Set PEXENGINE_BIN or provide an explicit executable path."
        case .invalidExecutablePath(let path):
            return "Invalid pexengine executable path: \(path)"
        case .launchFailed(let message):
            return "Failed to launch pexengine: \(message)"
        case .nonZeroExit(let code, let stderr):
            if stderr.isEmpty {
                return "pexengine exited with code \(code)."
            }
            return "pexengine exited with code \(code): \(stderr)"
        }
    }
}
