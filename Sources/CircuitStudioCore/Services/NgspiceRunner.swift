import Foundation
import Synchronization
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
        // Cap concurrent ngspice processes so parallel callers don't thrash the CPU.
        await NgspiceConcurrencyGate.shared.acquire()
        do {
            let result = try await launch(netlistURL: netlistURL, rawURL: rawURL,
                                          workingDirectory: workingDirectory, cancellation: cancellation)
            await NgspiceConcurrencyGate.shared.release()
            return result
        } catch {
            await NgspiceConcurrencyGate.shared.release()
            throw error
        }
    }

    private func launch(
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

    /// Await the child's termination via its `terminationHandler` (the process-monitoring
    /// dispatch source) rather than `waitUntilExit()`. On a detached task with no run loop,
    /// `waitUntilExit()` can hang indefinitely even after the child has already been
    /// reaped — its internal wait misses the termination signal. The handler fires reliably;
    /// an `isRunning` check covers the race where the child exited before it was installed,
    /// and a resume-once latch guarantees the continuation resumes exactly one time.
    private func waitForTermination(_ process: Process) async {
        let hasResumed = Mutex(false)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeOnce: @Sendable () -> Void = {
                let shouldResume = hasResumed.withLock { resumed -> Bool in
                    if resumed { return false }
                    resumed = true
                    return true
                }
                if shouldResume { continuation.resume() }
            }
            process.terminationHandler = { _ in resumeOnce() }
            // terminationHandler only fires on the running -> terminated transition; if the
            // child already exited, fire it ourselves.
            if !process.isRunning { resumeOnce() }
        }
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
