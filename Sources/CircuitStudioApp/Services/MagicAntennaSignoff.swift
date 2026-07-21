import CircuitSignoff
import Foundation

/// Builds a Magic-driven antenna signoff command for `ExternalSignoffCommandRunner`.
///
/// Magic's `antennacheck` is a real physical check the geometry checks (DRC/LVS)
/// cannot see: during fabrication, a long stretch of metal connected to a gate
/// before the gate's protection diode is placed collects plasma charge and can
/// rupture the thin gate oxide. The bundled `antenna.tcl` runs the check
/// headlessly against a profile-resolved PDK and normalizes Magic's output into lines
/// the `ExternalSignoffReportParser` understands.
public struct MagicAntennaSignoff: Sendable {

    /// Absolute path to the Magic launcher (the Tcl wrapper script).
    public let magicExecutableURL: URL
    /// PDK `.magicrc` that loads the technology (antenna ratios live in the techfile).
    public let rcFileURL: URL
    /// Value exported as `PDK_ROOT` for the `.magicrc` to resolve PDK paths.
    public let pdkRoot: String
    /// The normalizing antenna driver script (`antenna.tcl`).
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

    /// The antenna driver script shipped with this module.
    public static var bundledDriverScriptURL: URL? {
        Bundle.module.url(forResource: "antenna", withExtension: "tcl")
    }

    /// The report parser that matches the `antenna.tcl` driver's normalized output.
    public static var reportParser: ExternalSignoffReportParser {
        ExternalSignoffReportParser(style: .magicAntenna)
    }

    /// Builds an antenna command for `cell`, optionally reading `gds` first.
    public func command(
        cell: String,
        gds: URL? = nil,
        artifactDirectory: URL
    ) -> ExternalSignoffCommand {
        var environment = [
            "PDK_ROOT": pdkRoot,
            "ANTENNA_CELL": cell,
            "MAGTYPE": "mag",
        ]
        if let gds {
            environment["ANTENNA_GDS"] = gds.path(percentEncoded: false)
        }
        return ExternalSignoffCommand(
            kind: .antenna,
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
            logFileName: "antenna-magic.log"
        )
    }

    /// Discovers an installed Magic + profile-resolved PDK toolchain, or `nil` if unavailable.
    ///
    /// Returning `nil` — rather than substituting a mock — leaves the decision to
    /// the caller; there is no silent fallback to a fake result. Mirrors
    /// `MagicDRCAdapter.locate`.
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> MagicAntennaSignoff? {
        guard let driver = bundledDriverScriptURL else { return nil }

        let magicPath = environment["MAGIC_BIN"]
            ?? NSString(string: "~/.local/magic/bin/magic").expandingTildeInPath
        guard fileManager.isExecutableFile(atPath: magicPath) else { return nil }

        let context: SignoffPDKContext
        let rcFile: URL
        do {
            context = try SignoffPDKContext.resolve(
                requirementID: "magic",
                environment: environment,
                fileManager: fileManager
            )
            rcFile = try context.requiredFileURL(requirementID: "magic")
        } catch {
            return nil
        }
        guard fileManager.fileExists(atPath: rcFile.path(percentEncoded: false)) else {
            return nil
        }

        return MagicAntennaSignoff(
            magicExecutableURL: URL(filePath: magicPath),
            rcFileURL: rcFile,
            pdkRoot: context.pdkRoot,
            driverScriptURL: driver
        )
    }
}
