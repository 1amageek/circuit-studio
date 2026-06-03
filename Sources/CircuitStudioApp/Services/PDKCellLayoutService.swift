import Foundation
import CircuitStudioCore

/// Materializes a real PDK cell (or composed block) layout to a GDS file via
/// Magic, so a design referenced by cell name flows into signoff without a
/// hand-supplied GDS. The materialized layout is the foundry cell's own polygons
/// (DRC-clean), unlike transistor-level auto-layout.
public struct PDKCellLayoutService: Sendable {

    public let magicExecutableURL: URL
    public let rcFileURL: URL
    public let pdkRoot: String
    public let driverScriptURL: URL
    public let timeoutSeconds: Double

    public init(
        magicExecutableURL: URL,
        rcFileURL: URL,
        pdkRoot: String,
        driverScriptURL: URL,
        timeoutSeconds: Double = 300
    ) {
        self.magicExecutableURL = magicExecutableURL
        self.rcFileURL = rcFileURL
        self.pdkRoot = pdkRoot
        self.driverScriptURL = driverScriptURL
        self.timeoutSeconds = timeoutSeconds
    }

    public static var bundledDriverScriptURL: URL? {
        Bundle.module.url(forResource: "materialize_cell", withExtension: "tcl")
    }

    /// Available only with the Magic + Sky130 toolchain (reuses the DRC signoff's
    /// resolved Magic + PDK so discovery is consistent).
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> PDKCellLayoutService? {
        guard let drc = MagicDRCSignoff.locate(environment: environment, fileManager: fileManager),
              let driver = bundledDriverScriptURL else {
            return nil
        }
        return PDKCellLayoutService(
            magicExecutableURL: drc.magicExecutableURL,
            rcFileURL: drc.rcFileURL,
            pdkRoot: drc.pdkRoot,
            driverScriptURL: driver
        )
    }

    public enum LayoutError: Error, LocalizedError, Equatable {
        case toolFailed(exitCode: Int32, output: String)
        case outputMissing(URL)

        public var errorDescription: String? {
            switch self {
            case .toolFailed(let code, let output):
                return "Magic cell materialization failed (exit \(code)): \(output)"
            case .outputMissing(let url):
                return "Magic produced no GDS at \(url.path(percentEncoded: false))"
            }
        }
    }

    /// Writes `cell`'s layout to a GDS under `directory`, returning the GDS URL.
    /// Fails loudly on any tool error.
    public func materialize(cell: String, into directory: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appending(path: "\(cell).gds")
        if FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = magicExecutableURL
        process.arguments = [
            "-dnull", "-noconsole",
            "-rcfile", rcFileURL.path(percentEncoded: false),
            driverScriptURL.path(percentEncoded: false),
        ]
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PDK_ROOT": pdkRoot,
            "MAT_CELL": cell,
            "MAT_OUT": outputURL.path(percentEncoded: false),
            "MAGTYPE": "mag",
        ]) { _, new in new }

        let result = try await TimedProcessRunner(timeoutSeconds: timeoutSeconds).run(process: process)
        let output = [result.standardOutput, result.standardError].joined(separator: "\n")

        guard result.exitCode == 0, !output.contains("MAT_ERROR") else {
            throw LayoutError.toolFailed(exitCode: result.exitCode, output: output)
        }
        guard FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)) else {
            throw LayoutError.outputMissing(outputURL)
        }
        return outputURL
    }
}
