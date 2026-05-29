import Foundation

/// Builds a Netgen-driven LVS signoff command for `ExternalSignoffCommandService`.
///
/// Netgen runs headlessly (`-batch source lvs.tcl`) and compares a
/// layout-extracted SPICE netlist against a schematic netlist using the Sky130
/// device-matching setup. The bundled `lvs.tcl` reads Netgen's comparison report
/// (whose authoritative "Final result:" line is not printed to stdout) and emits
/// a single normalized line the `ExternalSignoffReportParser` understands. This
/// replaces the golden-log replay / "magic-netgen-like" mock for LVS with a real
/// tool.
public struct NetgenLVSSignoff: Sendable {

    /// Absolute path to the Netgen launcher (the Tcl wrapper script).
    public let netgenExecutableURL: URL
    /// PDK Netgen setup file (`sky130A_setup.tcl`) with device-class rules.
    public let setupFileURL: URL
    /// Value exported as `PDK_ROOT` for tools that resolve PDK paths.
    public let pdkRoot: String
    /// The normalizing LVS driver script (`lvs.tcl`).
    public let driverScriptURL: URL

    public init(
        netgenExecutableURL: URL,
        setupFileURL: URL,
        pdkRoot: String,
        driverScriptURL: URL
    ) {
        self.netgenExecutableURL = netgenExecutableURL
        self.setupFileURL = setupFileURL
        self.pdkRoot = pdkRoot
        self.driverScriptURL = driverScriptURL
    }

    /// The LVS driver script shipped with this module.
    public static var bundledDriverScriptURL: URL? {
        Bundle.module.url(forResource: "lvs", withExtension: "tcl")
    }

    /// The report parser that matches the `lvs.tcl` driver's normalized output.
    public static var reportParser: ExternalSignoffReportParser {
        ExternalSignoffReportParser(style: .netgenLVS)
    }

    /// Builds an LVS command comparing `layoutNetlistPath` against
    /// `schematicNetlistPath` for `topCell`.
    public func command(
        layoutNetlistPath: String,
        schematicNetlistPath: String,
        topCell: String,
        artifactDirectory: URL
    ) -> ExternalSignoffCommand {
        let reportURL = artifactDirectory.appending(path: "lvs-compare.out")
        let environment = [
            "PDK_ROOT": pdkRoot,
            "LVS_LAYOUT": layoutNetlistPath,
            "LVS_SCHEM": schematicNetlistPath,
            "LVS_TOP": topCell,
            "LVS_SETUP": setupFileURL.path(percentEncoded: false),
            "LVS_OUT": reportURL.path(percentEncoded: false),
        ]
        return ExternalSignoffCommand(
            kind: .lvs,
            toolName: "netgen",
            executablePath: netgenExecutableURL.path(percentEncoded: false),
            arguments: [
                "-batch",
                "source",
                driverScriptURL.path(percentEncoded: false),
            ],
            environment: environment,
            workingDirectory: artifactDirectory,
            logFileName: "lvs-netgen.log"
        )
    }

    /// Discovers an installed Netgen + Sky130 toolchain, or `nil` if unavailable.
    /// Returning `nil` — rather than substituting a mock — leaves the decision to
    /// the caller; there is no silent fallback to a fake result.
    /// - `NETGEN_BIN` overrides the Netgen launcher path (default
    ///   `~/.local/netgen/bin/netgen`).
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> NetgenLVSSignoff? {
        guard let driver = bundledDriverScriptURL else { return nil }

        let netgenPath = environment["NETGEN_BIN"]
            ?? NSString(string: "~/.local/netgen/bin/netgen").expandingTildeInPath
        guard fileManager.isExecutableFile(atPath: netgenPath) else { return nil }

        guard let pdkRoot = Sky130PDK.root(environment: environment, fileManager: fileManager) else {
            return nil
        }
        let setupFile = URL(filePath: pdkRoot)
            .appending(path: "sky130A/libs.tech/netgen/sky130A_setup.tcl")
        guard fileManager.fileExists(atPath: setupFile.path(percentEncoded: false)) else {
            return nil
        }

        return NetgenLVSSignoff(
            netgenExecutableURL: URL(filePath: netgenPath),
            setupFileURL: setupFile,
            pdkRoot: pdkRoot,
            driverScriptURL: driver
        )
    }
}
