import Foundation
import Synchronization

public struct ExternalSignoffCommand: Sendable, Hashable, Codable {
    public let kind: ExternalSignoffToolReport.Kind
    public let toolName: String
    public let executablePath: String
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: URL?
    public let logFileName: String?

    public init(
        kind: ExternalSignoffToolReport.Kind,
        toolName: String,
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil,
        logFileName: String? = nil
    ) {
        self.kind = kind
        self.toolName = toolName
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.logFileName = logFileName
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
    case launchFailed(String)
    case artifactWriteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidExecutablePath(let path):
            return "Invalid external signoff executable path: \(path)"
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

        let capture = try await capture(process: process)
        let stdout = capture.stdout
        let stderr = capture.stderr
        let exitCode = capture.exitCode

        let commandLine = [executableURL.path(percentEncoded: false)] + command.arguments
        let logURL = artifactDirectory.appending(path: logFileName(for: command))
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

        let report = parser.parse(
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

    private struct Capture: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Launches `process` and drains stdout/stderr CONCURRENTLY while it runs, then
    /// takes its exit code. Never `waitUntilExit()` before reading: a tool that
    /// fills a pipe buffer (>~64KB) before exiting would block on the write and
    /// hang the wait forever. Mirrors PEXEngine's `ProcessRunner`.
    private func capture(process: Process) async throws -> Capture {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Capture, Error>) in
            let stdoutBuf = Mutex(Data())
            let stderrBuf = Mutex(Data())
            let exitCodeBuf = Mutex<Int32>(0)
            let remaining = Mutex(3)   // stdout EOF + stderr EOF + process exit

            let finish: @Sendable () -> Void = {
                let count = remaining.withLock { value -> Int in
                    value -= 1
                    return value
                }
                guard count == 0 else { return }
                let out = stdoutBuf.withLock { $0 }
                let err = stderrBuf.withLock { $0 }
                let code = exitCodeBuf.withLock { $0 }
                continuation.resume(returning: Capture(
                    exitCode: code,
                    stdout: String(data: out, encoding: .utf8) ?? "",
                    stderr: String(data: err, encoding: .utf8) ?? ""
                ))
            }

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    finish()
                } else {
                    stdoutBuf.withLock { $0.append(data) }
                }
            }
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    finish()
                } else {
                    stderrBuf.withLock { $0.append(data) }
                }
            }
            process.terminationHandler = { @Sendable proc in
                exitCodeBuf.withLock { $0 = proc.terminationStatus }
                finish()
            }

            do {
                try process.run()
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: ExternalSignoffCommandError.launchFailed(error.localizedDescription))
            }
        }
    }

    private func validateExecutable(path: String) throws -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: expanded) else {
            throw ExternalSignoffCommandError.invalidExecutablePath(path)
        }
        return URL(filePath: expanded)
    }

    private func logFileName(for command: ExternalSignoffCommand) -> String {
        if let logFileName = command.logFileName,
           !logFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return logFileName
        }
        let safeToolName = command.toolName.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
        }
        return "\(command.kind.rawValue)-\(String(safeToolName)).log"
    }

    private func renderLog(
        command: ExternalSignoffCommand,
        commandLine: [String],
        exitCode: Int32,
        stdout: String,
        stderr: String
    ) -> String {
        """
        tool=\(command.toolName)
        kind=\(command.kind.rawValue)
        command=\(commandLine.joined(separator: " "))
        working_directory=\(command.workingDirectory?.path(percentEncoded: false) ?? "")
        exit_code=\(exitCode)

        [stdout]
        \(stdout)
        [stderr]
        \(stderr)
        """
    }
}
