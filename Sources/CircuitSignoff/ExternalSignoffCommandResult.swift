import Foundation
import CircuiteFoundation

public struct ExternalSignoffCommandResult: Sendable, Hashable, Codable {
    public let sanitizedCommandLine: [String]
    public let sanitizedSourceExecutablePath: String
    public let executableSnapshotURL: URL
    public let sanitizedWorkingDirectory: URL?
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let logURL: URL
    public let report: ExternalSignoffToolReport
    public let provenance: ExecutionProvenance

    public init(
        sanitizedCommandLine: [String],
        sanitizedSourceExecutablePath: String,
        executableSnapshotURL: URL,
        sanitizedWorkingDirectory: URL?,
        exitCode: Int32,
        standardOutput: String,
        standardError: String,
        logURL: URL,
        report: ExternalSignoffToolReport,
        provenance: ExecutionProvenance
    ) {
        self.sanitizedCommandLine = sanitizedCommandLine
        self.sanitizedSourceExecutablePath = sanitizedSourceExecutablePath
        self.executableSnapshotURL = executableSnapshotURL
        self.sanitizedWorkingDirectory = sanitizedWorkingDirectory
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.logURL = logURL
        self.report = report
        self.provenance = provenance
    }
}
