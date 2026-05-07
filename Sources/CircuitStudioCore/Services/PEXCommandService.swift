import Foundation

/// Executes the standalone `pexengine` command from CircuitStudio.
public struct PEXCommandService: Sendable {
    private let explicitExecutablePath: String?

    public init(executablePath: String? = nil) {
        self.explicitExecutablePath = executablePath
    }

    public func extract(
        configURL: URL,
        workingDirectory: URL? = nil,
        additionalArguments: [String] = []
    ) throws -> PEXCommandResult {
        var arguments: [String] = [
            "extract",
            "--config", configURL.path(percentEncoded: false)
        ]
        arguments.append(contentsOf: additionalArguments)
        return try run(arguments: arguments, workingDirectory: workingDirectory)
    }

    public func run(arguments: [String], workingDirectory: URL? = nil) throws -> PEXCommandResult {
        let executableURL = try resolveExecutableURL()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw PEXCommandError.launchFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        let commandLine = [executableURL.path(percentEncoded: false)] + arguments
        let result = PEXCommandResult(
            commandLine: commandLine,
            workingDirectory: workingDirectory,
            exitCode: process.terminationStatus,
            standardOutput: stdout,
            standardError: stderr
        )

        guard process.terminationStatus == 0 else {
            throw PEXCommandError.nonZeroExit(code: process.terminationStatus, stderr: stderr)
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
