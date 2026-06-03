import Foundation
import CoreSpiceEvent

/// Executes ngspice in batch mode and returns the generated RAW output.
public struct NgspiceRunner: Sendable {
    public let timeoutSeconds: Double
    public let terminationGraceSeconds: Double
    public let executablePath: String?
    public let concurrencyGate: NgspiceConcurrencyGate?

    public init(
        timeoutSeconds: Double = 300,
        terminationGraceSeconds: Double = 2,
        executablePath: String? = nil,
        concurrencyGate: NgspiceConcurrencyGate? = .shared
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.terminationGraceSeconds = terminationGraceSeconds
        self.executablePath = executablePath
        self.concurrencyGate = concurrencyGate
    }

    public func run(
        netlistURL: URL,
        rawURL: URL,
        workingDirectory: URL,
        cancellation: CancellationToken
    ) async throws -> URL {
        // Cap concurrent ngspice processes so parallel callers don't thrash the CPU.
        guard let concurrencyGate else {
            return try await launch(
                netlistURL: netlistURL,
                rawURL: rawURL,
                workingDirectory: workingDirectory,
                cancellation: cancellation
            )
        }
        try await concurrencyGate.acquire()
        do {
            let result = try await launch(netlistURL: netlistURL, rawURL: rawURL,
                                          workingDirectory: workingDirectory, cancellation: cancellation)
            await concurrencyGate.release()
            return result
        } catch {
            await concurrencyGate.release()
            throw error
        }
    }

    private func launch(
        netlistURL: URL,
        rawURL: URL,
        workingDirectory: URL,
        cancellation: CancellationToken
    ) async throws -> URL {
        let configured = executablePath ?? ProcessInfo.processInfo.environment["NGSPICE_BIN"] ?? "ngspice"

        let process = Process()
        process.executableURL = try Self.resolveExecutable(configured)
        process.currentDirectoryURL = workingDirectory
        process.arguments = ["-b", netlistURL.path]

        let result: TimedProcessResult
        do {
            result = try await TimedProcessRunner(
                timeoutSeconds: timeoutSeconds,
                terminationGraceSeconds: terminationGraceSeconds
            ).run(process: process, shouldCancel: { cancellation.isCancelled })
        } catch let error as TimedProcessError {
            switch error {
            case .timedOut(_, let seconds, let standardOutput, let standardError):
                throw StudioError.simulationFailure("ngspice timed out after \(seconds)s: \(standardOutput)\(standardError)")
            case .launchFailed(_, let message):
                throw StudioError.simulationFailure("ngspice failed to launch: \(message)")
            case .cancelled:
                throw StudioError.cancelled
            }
        } catch {
            throw StudioError.simulationFailure("ngspice failed: \(error.localizedDescription)")
        }

        let combined = result.standardOutput + result.standardError

        guard result.exitCode == 0 else {
            throw StudioError.simulationFailure("ngspice failed: \(combined)")
        }

        guard FileManager.default.fileExists(atPath: rawURL.path) else {
            throw StudioError.simulationFailure("ngspice did not produce RAW output: \(combined)")
        }

        return rawURL
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
