import Foundation
import CircuitStudioCore
import SignoffToolSupport

public struct ExternalSignoffCommand: Sendable, Hashable, Codable {
    public let kind: ExternalSignoffToolReport.Kind
    public let toolName: String
    public let executablePath: String
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: URL?
    public let logFileName: String?
    public let timeoutSeconds: Double
    public let parserStyle: ExternalSignoffReportParser.Style?

    public init(
        kind: ExternalSignoffToolReport.Kind,
        toolName: String,
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil,
        logFileName: String? = nil,
        timeoutSeconds: Double = 300,
        parserStyle: ExternalSignoffReportParser.Style? = nil
    ) {
        self.kind = kind
        self.toolName = toolName
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.logFileName = logFileName
        self.timeoutSeconds = timeoutSeconds
        self.parserStyle = parserStyle
    }
}

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

public enum ExternalSignoffCommandError: Error, LocalizedError, Equatable {
    case invalidExecutablePath(String)
    case invalidLogFileName(String)
    case launchFailed(String)
    case artifactWriteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidExecutablePath(let path):
            return "Invalid external signoff executable path: \(path)"
        case .invalidLogFileName(let name):
            return "Invalid external signoff log file name: \(name)"
        case .launchFailed(let message):
            return "External signoff command failed to launch: \(message)"
        case .artifactWriteFailed(let message):
            return "External signoff artifact write failed: \(message)"
        }
    }
}

public struct ExternalSignoffCommandService: Sendable {
    private let parser: ExternalSignoffReportParser

    public init(parser: ExternalSignoffReportParser = ExternalSignoffReportParser()) {
        self.parser = parser
    }

    public func run(
        command: ExternalSignoffCommand,
        artifactDirectory: URL
    ) async throws -> ExternalSignoffCommandResult {
        let executableURL = try validateExecutable(path: command.executablePath)

        do {
            try FileManager.default.createDirectory(
                at: artifactDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw ExternalSignoffCommandError.artifactWriteFailed(error.localizedDescription)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectory
        if !command.environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { _, new in new }
        }

        let processResult = try await TimedProcessRunner(timeoutSeconds: command.timeoutSeconds).run(process: process)
        let stdout = processResult.standardOutput
        let stderr = processResult.standardError
        let exitCode = processResult.exitCode

        let commandLine = [executableURL.path(percentEncoded: false)] + command.arguments
        let logURL = try logURL(for: command, artifactDirectory: artifactDirectory)
        let logContents = renderLog(
            command: command,
            commandLine: commandLine,
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr
        )

        do {
            try logContents.write(to: logURL, atomically: true, encoding: .utf8)
        } catch {
            throw ExternalSignoffCommandError.artifactWriteFailed(error.localizedDescription)
        }

        let report = parser(for: command.parserStyle).parse(
            kind: command.kind,
            toolName: command.toolName,
            logPath: logURL.path(percentEncoded: false),
            rawOutput: [stdout, stderr].joined(separator: "\n"),
            success: exitCode == 0
        )

        return ExternalSignoffCommandResult(
            commandLine: commandLine,
            workingDirectory: command.workingDirectory,
            exitCode: exitCode,
            standardOutput: stdout,
            standardError: stderr,
            logURL: logURL,
            report: report
        )
    }

    public func run(
        commands: [ExternalSignoffCommand],
        artifactDirectory: URL
    ) async throws -> ExternalSignoffReview {
        var reports: [ExternalSignoffToolReport] = []
        for command in commands {
            let result = try await run(command: command, artifactDirectory: artifactDirectory)
            reports.append(result.report)
        }
        return ExternalSignoffReview(reports: reports)
    }

    private func validateExecutable(path: String) throws -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: expanded) else {
            throw ExternalSignoffCommandError.invalidExecutablePath(path)
        }
        return URL(filePath: expanded)
    }

    private func logURL(for command: ExternalSignoffCommand, artifactDirectory: URL) throws -> URL {
        let fileName = try logFileName(for: command)
        let url = artifactDirectory.appending(path: fileName, directoryHint: .notDirectory)
        let parent = url.deletingLastPathComponent().standardizedFileURL
        let artifactRoot = artifactDirectory.standardizedFileURL
        guard parent.path(percentEncoded: false) == artifactRoot.path(percentEncoded: false) else {
            throw ExternalSignoffCommandError.invalidLogFileName(fileName)
        }
        return url
    }

    private func logFileName(for command: ExternalSignoffCommand) throws -> String {
        if let logFileName = command.logFileName,
           !logFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = logFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isSafeLogFileName(trimmed) else {
                throw ExternalSignoffCommandError.invalidLogFileName(logFileName)
            }
            return trimmed
        }
        let safeToolName = command.toolName.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
        }
        return "\(command.kind.rawValue)-\(String(safeToolName)).log"
    }

    private func isSafeLogFileName(_ fileName: String) -> Bool {
        guard !fileName.isEmpty, fileName != ".", fileName != ".." else {
            return false
        }
        guard !fileName.contains("/"), !fileName.contains("\\") else {
            return false
        }
        return URL(filePath: fileName).lastPathComponent == fileName
    }

    private func parser(for override: ExternalSignoffReportParser.Style?) -> ExternalSignoffReportParser {
        if let override {
            return ExternalSignoffReportParser(style: override)
        }
        return parser
    }

    private func renderLog(
        command: ExternalSignoffCommand,
        commandLine: [String],
        exitCode: Int32,
        stdout: String,
        stderr: String
    ) -> String {
        """
        tool=\(Self.logScalar(command.toolName))
        kind=\(Self.logScalar(command.kind.rawValue))
        command=\(commandLine.map(Self.logScalar).joined(separator: " "))
        working_directory=\(Self.logScalar(command.workingDirectory?.path(percentEncoded: false) ?? ""))
        exit_code=\(exitCode)

        [stdout]
        \(stdout)
        [stderr]
        \(stderr)
        """
    }

    private static func logScalar(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
