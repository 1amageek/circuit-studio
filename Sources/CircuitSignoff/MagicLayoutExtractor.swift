import Foundation
import SignoffToolSupport

/// Extracts an LVS-mode SPICE netlist (device-level, no parasitics) from a layout
/// GDS using Magic, so Netgen can compare it against the schematic. Distinct from
/// PEX extraction (which keeps parasitics): LVS needs the clean device netlist.
public struct MagicLayoutExtractor: Sendable {

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

    /// The bundled extraction driver shipped with this module.
    public static var bundledDriverScriptURL: URL? {
        Bundle.module.url(forResource: "extract_lvs", withExtension: "tcl")
    }

    public enum ExtractionError: Error, LocalizedError, Equatable {
        case toolFailed(exitCode: Int32, output: String)
        case outputMissing(URL)

        public var errorDescription: String? {
            switch self {
            case .toolFailed(let code, let output):
                return "Magic layout extraction failed (exit \(code)): \(output)"
            case .outputMissing(let url):
                return "Magic layout extraction produced no netlist at \(url.path(percentEncoded: false))"
            }
        }
    }

    /// Extracts `cell` from `gds` into a SPICE netlist under `directory`, returning
    /// the netlist URL. Fails loudly (throws) on any tool error — never returns a
    /// stale/empty netlist silently.
    public func extractLayoutNetlist(gds: URL, cell: String, into directory: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appending(path: "\(cell).lvs.spice")
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
            "EXT_GDS": gds.path(percentEncoded: false),
            "EXT_CELL": cell,
            "EXT_OUT": outputURL.path(percentEncoded: false),
            "MAGTYPE": "mag",
        ]) { _, new in new }

        let result = try await TimedProcessRunner(timeoutSeconds: timeoutSeconds).run(process: process)
        let output = [result.standardOutput, result.standardError].joined(separator: "\n")

        guard result.exitCode == 0, !output.contains("EXT_ERROR") else {
            throw ExtractionError.toolFailed(exitCode: result.exitCode, output: output)
        }
        guard FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)) else {
            throw ExtractionError.outputMissing(outputURL)
        }
        return outputURL
    }
}
