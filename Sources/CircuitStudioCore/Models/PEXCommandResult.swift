import Foundation

/// Result returned by a `pexengine` command invocation.
public struct PEXCommandResult: Sendable, Hashable {
    public let commandLine: [String]
    public let workingDirectory: URL?
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(
        commandLine: [String],
        workingDirectory: URL?,
        exitCode: Int32,
        standardOutput: String,
        standardError: String
    ) {
        self.commandLine = commandLine
        self.workingDirectory = workingDirectory
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}
