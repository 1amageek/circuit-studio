import Foundation

/// Executes the standalone `pexengine` command from CircuitStudio.
public struct PEXCommandService: Sendable {
    private let explicitExecutablePath: String?
    private let timeoutSeconds: Double

    public init(executablePath: String? = nil, timeoutSeconds: Double = 300) {
        self.explicitExecutablePath = executablePath
        self.timeoutSeconds = timeoutSeconds
    }

    public func extract(
        configURL: URL,
        workingDirectory: URL? = nil,
        additionalArguments: [String] = []
    ) async throws -> PEXCommandResult {
        var arguments: [String] = [
            "extract",
            "--config", configURL.path(percentEncoded: false)
        ]
        arguments.append(contentsOf: additionalArguments)
        return try await run(arguments: arguments, workingDirectory: workingDirectory)
    }

    public func run(arguments: [String], workingDirectory: URL? = nil) async throws -> PEXCommandResult {
        let executableURL = try resolveExecutableURL()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let processResult: TimedProcessResult
        do {
            processResult = try await TimedProcessRunner(timeoutSeconds: timeoutSeconds).run(process: process)
        } catch let error as TimedProcessError {
            switch error {
            case .invalidConfiguration(let message):
                throw PEXCommandError.invalidConfiguration(message)
            case .launchFailed(_, let message):
                throw PEXCommandError.launchFailed(message)
            case .cancelled(_, let standardOutput, let standardError):
                throw PEXCommandError.cancelled(stdout: standardOutput, stderr: standardError)
            case .timedOut(let executablePath, let timeoutSeconds, let standardOutput, let standardError):
                throw PEXCommandError.timedOut(
                    executablePath: executablePath,
                    timeoutSeconds: timeoutSeconds,
                    stdout: standardOutput,
                    stderr: standardError
                )
            }
        } catch {
            throw error
        }

        let commandLine = [executableURL.path(percentEncoded: false)] + arguments
        let result = PEXCommandResult(
            commandLine: commandLine,
            workingDirectory: workingDirectory,
            exitCode: processResult.exitCode,
            standardOutput: processResult.standardOutput,
            standardError: processResult.standardError
        )

        guard processResult.exitCode == 0 else {
            throw PEXCommandError.nonZeroExit(
                code: processResult.exitCode,
                stdout: processResult.standardOutput,
                stderr: processResult.standardError
            )
        }

        return result
    }

    private func resolveExecutableURL() throws -> URL {
        if let explicitExecutablePath,
           !explicitExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try validateExecutable(path: explicitExecutablePath)
        }

        if let envPath = ProcessInfo.processInfo.environment["PEXENGINE_BIN"],
           !envPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try validateExecutable(path: envPath)
        }

        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for path in searchPaths {
            let candidate = URL(filePath: path).appending(path: "pexengine")
            let candidatePath = candidate.path(percentEncoded: false)
            if FileManager.default.isExecutableFile(atPath: candidatePath) {
                return candidate
            }
        }

        let knownPaths = [
            "/opt/homebrew/bin/pexengine",
            "/usr/local/bin/pexengine",
            "/usr/bin/pexengine"
        ]
        for known in knownPaths {
            if FileManager.default.isExecutableFile(atPath: known) {
                return URL(filePath: known)
            }
        }

        throw PEXCommandError.executableNotFound
    }

    private func validateExecutable(path: String) throws -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: expanded) else {
            throw PEXCommandError.invalidExecutablePath(path)
        }
        return URL(filePath: expanded)
    }
}
