import Foundation

public struct ExternalSignoffCommandResult: Sendable, Hashable {
    public let commandLine: [String]
    public let workingDirectory: URL?
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let logURL: URL
    public let report: ExternalSignoffToolReport

    public init(
        commandLine: [String],
        workingDirectory: URL?,
        exitCode: Int32,
        standardOutput: String,
        standardError: String,
        logURL: URL,
        report: ExternalSignoffToolReport
    ) {
        self.commandLine = commandLine
        self.workingDirectory = workingDirectory
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.logURL = logURL
        self.report = report
    }
}
