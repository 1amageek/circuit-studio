import Foundation

/// Builds a Magic-driven DRC signoff command for `ExternalSignoffCommandService`.
///
/// Magic runs headlessly (`-dnull -noconsole`) against a Sky130-class PDK, and
/// the bundled `drc.tcl` normalizes Magic's free-text DRC output into lines the
/// `ExternalSignoffReportParser` understands. This replaces the previous
/// golden-log replay / "magic-netgen-like" mock for DRC with a real tool.
public struct MagicDRCSignoff: Sendable {

    /// Absolute path to the Magic launcher (the Tcl wrapper script).
    public let magicExecutableURL: URL
    /// PDK `.magicrc` that loads the technology DRC rules.
    public let rcFileURL: URL
    /// Value exported as `PDK_ROOT` for the `.magicrc` to resolve PDK paths.
    public let pdkRoot: String
    /// The normalizing DRC driver script (`drc.tcl`).
    public let driverScriptURL: URL

    public init(
        magicExecutableURL: URL,
        rcFileURL: URL,
        pdkRoot: String,
        driverScriptURL: URL
    ) {
        self.magicExecutableURL = magicExecutableURL
        self.rcFileURL = rcFileURL
        self.pdkRoot = pdkRoot
        self.driverScriptURL = driverScriptURL
    }

    /// The DRC driver script shipped with this module.
    public static var bundledDriverScriptURL: URL? {
        Bundle.module.url(forResource: "drc", withExtension: "tcl")
    }

    /// The report parser that matches the `drc.tcl` driver's normalized output.
    /// Build the command service with this so Magic's incidental chatter is not
    /// misread as diagnostics.
    public static var reportParser: ExternalSignoffReportParser {
        ExternalSignoffReportParser(style: .magicDRC)
    }

    /// Builds a DRC command for `cell`, optionally reading `gdsPath` first.
    ///
    /// `DRC_GDS` is only set when a GDS is supplied so the driver loads an
    /// already-resolved cell (e.g. a foundry standard cell via the PDK search
    /// path) when no layout file is given.
    public func command(
        cell: String,
        gdsPath: String? = nil,
        artifactDirectory: URL
    ) -> ExternalSignoffCommand {
        var environment = [
            "PDK_ROOT": pdkRoot,
            "DRC_CELL": cell,
            "MAGTYPE": "mag",
        ]
        if let gdsPath {
            environment["DRC_GDS"] = gdsPath
        }
        return ExternalSignoffCommand(
            kind: .drc,
            toolName: "magic",
            executablePath: magicExecutableURL.path(percentEncoded: false),
            arguments: [
                "-dnull",
                "-noconsole",
                "-rcfile",
                rcFileURL.path(percentEncoded: false),
                driverScriptURL.path(percentEncoded: false),
            ],
            environment: environment,
            workingDirectory: artifactDirectory,
            logFileName: "drc-magic.log"
        )
    }

    /// Discovers an installed Magic + Sky130 toolchain, or `nil` if unavailable.
    ///
    /// Returning `nil` — rather than substituting a mock — leaves the decision
    /// to the caller; there is no silent fallback to a fake result.
    /// - `MAGIC_BIN` overrides the Magic launcher path (default
    ///   `~/.local/magic/bin/magic`).
    /// - `PDK_ROOT` overrides the PDK root; otherwise the single installed
    ///   volare Sky130 version is used (ambiguity returns `nil`).
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> MagicDRCSignoff? {
        guard let driver = bundledDriverScriptURL else { return nil }

        let magicPath = environment["MAGIC_BIN"]
            ?? NSString(string: "~/.local/magic/bin/magic").expandingTildeInPath
        guard fileManager.isExecutableFile(atPath: magicPath) else { return nil }

        guard let pdkRoot = resolvePDKRoot(environment: environment, fileManager: fileManager) else {
            return nil
        }
        let rcFile = URL(filePath: pdkRoot)
            .appending(path: "sky130A/libs.tech/magic/sky130A.magicrc")
        guard fileManager.fileExists(atPath: rcFile.path(percentEncoded: false)) else {
            return nil
        }

        return MagicDRCSignoff(
            magicExecutableURL: URL(filePath: magicPath),
            rcFileURL: rcFile,
            pdkRoot: pdkRoot,
            driverScriptURL: driver
        )
    }

    private static func resolvePDKRoot(
        environment: [String: String],
        fileManager: FileManager
    ) -> String? {
        if let root = environment["PDK_ROOT"],
           fileManager.fileExists(atPath: root) {
            return root
        }
        let versions = NSString(string: "~/.volare/volare/sky130/versions")
            .expandingTildeInPath
        guard let entries = try? fileManager.contentsOfDirectory(atPath: versions) else {
            return nil
        }
        let builds = entries.filter { !$0.hasPrefix(".") }
        // Only auto-select when there is exactly one installed build; ambiguity
        // must be resolved explicitly via PDK_ROOT.
        guard builds.count == 1 else { return nil }
        return versions + "/" + builds[0]
    }
}
