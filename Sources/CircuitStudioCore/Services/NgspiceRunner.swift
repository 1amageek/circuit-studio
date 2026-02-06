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
        let ngspicePath = ProcessInfo.processInfo.environment["NGSPICE_BIN"] ?? "ngspice"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ngspicePath)
        process.currentDirectoryURL = workingDirectory
        process.arguments = ["-b", netlistURL.path]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let monitor = Task {
            while !Task.isCancelled {
                if cancellation.isCancelled {
                    process.terminate()
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        await waitForTermination(process)
        monitor.cancel()

        if cancellation.isCancelled {
            throw StudioError.cancelled
        }

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
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
}
