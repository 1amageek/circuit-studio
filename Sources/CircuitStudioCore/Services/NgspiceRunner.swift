import Foundation
import CoreSpiceEvent

/// Executes ngspice in batch mode and returns the generated RAW output.
public struct NgspiceRunner: Sendable {
    public init() {}

    public func run(
        netlistURL: URL,
        rawURL: URL,
        workingDirectory: URL,
        cancellation: CancellationToken
    ) async throws -> URL {
        let configured = ProcessInfo.processInfo.environment["NGSPICE_BIN"] ?? "ngspice"

        let process = Process()
        process.executableURL = try Self.resolveExecutable(configured)
        process.currentDirectoryURL = workingDirectory
        process.arguments = ["-b", netlistURL.path]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        // Drain both pipes concurrently while the process runs: never read after
        // waitUntilExit, which deadlocks when ngspice fills a pipe buffer (verbose
        // batch logs on a large circuit) before exiting.
        let outTask = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }
        let errTask = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }

        let monitor = Task {
            while !Task.isCancelled {
                if cancellation.isCancelled {
                    process.terminate()
                    break
                }
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    break
                }
            }
        }

        await waitForTermination(process)
        monitor.cancel()

        let output = await outTask.value
        let errorOutput = await errTask.value

        if cancellation.isCancelled {
            throw StudioError.cancelled
        }

        let combined = (String(data: output, encoding: .utf8) ?? "")
            + (String(data: errorOutput, encoding: .utf8) ?? "")

        guard process.terminationStatus == 0 else {
            throw StudioError.simulationFailure("ngspice failed: \(combined)")
        }

        guard FileManager.default.fileExists(atPath: rawURL.path) else {
            throw StudioError.simulationFailure("ngspice did not produce RAW output: \(combined)")
        }

        return rawURL
    }

    private func waitForTermination(_ process: Process) async {
        await Task.detached {
            process.waitUntilExit()
        }.value
    }

    /// Resolves the ngspice executable. An absolute/relative path (containing `/`)
    /// is used as-is; a bare name is looked up on `PATH` — `Process` does not search
    /// `PATH` for a bare `executableURL`, so a bare name would otherwise never launch.
    private static func resolveExecutable(_ configured: String) throws -> URL {
        let fileManager = FileManager.default
        if configured.contains("/") {
            guard fileManager.isExecutableFile(atPath: configured) else {
                throw StudioError.simulationFailure("ngspice is not executable at \(configured)")
            }
            return URL(fileURLWithPath: configured)
        }
        for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let candidate = "\(directory)/\(configured)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        throw StudioError.simulationFailure("ngspice not found on PATH (set NGSPICE_BIN to its path)")
    }
}
