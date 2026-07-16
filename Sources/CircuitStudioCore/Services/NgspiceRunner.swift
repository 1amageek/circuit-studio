import Foundation
import CoreSpiceEvent
import SignoffToolSupport

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
        try validateInputPaths(
            netlistURL: netlistURL,
            rawURL: rawURL,
            workingDirectory: workingDirectory
        )
        try prepareOutputPath(rawURL)

        let configured = executablePath ?? ProcessInfo.processInfo.environment["NGSPICE_BIN"] ?? "ngspice"

        let process = Process()
        process.executableURL = try Self.resolveExecutable(configured)
        process.currentDirectoryURL = workingDirectory
        process.arguments = ["-b", Self.filePath(netlistURL)]

        let result: TimedProcessResult
        do {
            result = try await TimedProcessRunner(
                timeoutSeconds: timeoutSeconds,
                terminationGraceSeconds: terminationGraceSeconds
            ).run(process: process, cancellationCheck: { cancellation.isCancelled })
        } catch let error as TimedProcessError {
            switch error {
            case .invalidConfiguration(let message):
                throw StudioError.simulationFailure("ngspice process runner invalid configuration: \(message)")
            case .timedOut(_, let seconds, let standardOutput, let standardError):
                throw StudioError.simulationFailure("ngspice timed out after \(seconds)s: \(standardOutput)\(standardError)")
            case .launchFailed(_, let message):
                throw StudioError.simulationFailure("ngspice failed to launch: \(message)")
            case .cancellationCheckFailed(_, let message, _, _):
                throw StudioError.simulationFailure("ngspice cancellation check failed: \(message)")
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

        try validateProducedRaw(rawURL, combinedOutput: combined)

        return rawURL
    }

    private func validateInputPaths(
        netlistURL: URL,
        rawURL: URL,
        workingDirectory: URL
    ) throws {
        let fileManager = FileManager.default
        let netlistPath = Self.filePath(netlistURL)
        guard Self.isExistingFile(netlistPath, fileManager: fileManager) else {
            throw StudioError.simulationFailure("ngspice netlist input is not a file: \(netlistPath)")
        }

        let workingDirectoryPath = Self.filePath(workingDirectory)
        guard Self.isExistingDirectory(workingDirectoryPath, fileManager: fileManager) else {
            throw StudioError.simulationFailure("ngspice working directory is not a directory: \(workingDirectoryPath)")
        }

        let rawParentPath = Self.filePath(rawURL.deletingLastPathComponent())
        guard Self.isExistingDirectory(rawParentPath, fileManager: fileManager) else {
            throw StudioError.simulationFailure("ngspice RAW output parent is not a directory: \(rawParentPath)")
        }
    }

    private func prepareOutputPath(_ rawURL: URL) throws {
        let fileManager = FileManager.default
        let rawPath = Self.filePath(rawURL)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rawPath, isDirectory: &isDirectory) else {
            return
        }
        guard !isDirectory.boolValue else {
            throw StudioError.simulationFailure("ngspice RAW output path is a directory: \(rawPath)")
        }
        do {
            try fileManager.removeItem(at: rawURL)
        } catch {
            throw StudioError.simulationFailure("Failed to clear stale ngspice RAW output at \(rawPath): \(error.localizedDescription)")
        }
    }

    private func validateProducedRaw(_ rawURL: URL, combinedOutput: String) throws {
        let fileManager = FileManager.default
        let rawPath = Self.filePath(rawURL)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rawPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw StudioError.simulationFailure("ngspice did not produce RAW output: \(combinedOutput)")
        }
        do {
            let attributes = try fileManager.attributesOfItem(atPath: rawPath)
            guard let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
                throw StudioError.simulationFailure("ngspice produced empty RAW output: \(combinedOutput)")
            }
        } catch let error as StudioError {
            throw error
        } catch {
            throw StudioError.simulationFailure("Failed to inspect ngspice RAW output at \(rawPath): \(error.localizedDescription)")
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

    private static func isExistingFile(_ path: String, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private static func isExistingDirectory(_ path: String, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func filePath(_ url: URL) -> String {
        url.path(percentEncoded: false)
    }

}
