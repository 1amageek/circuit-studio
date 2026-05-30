import Foundation

/// Produces an `ExternalSignoffReview` by running the REAL signoff tools (Magic
/// DRC + Magic LVS-extraction + Netgen LVS) on a layout, instead of replaying
/// golden logs. This is how the design flow gets a signoff review from live tools.
///
/// `locate()` returns nil when the toolchain is unavailable; callers that require
/// live signoff must treat nil as a hard error (no silent fallback to mock/replay).
public struct LiveSignoffService: Sendable {

    private let drc: MagicDRCSignoff
    private let lvs: NetgenLVSSignoff
    private let extractor: MagicLayoutExtractor

    public init(drc: MagicDRCSignoff, lvs: NetgenLVSSignoff, extractor: MagicLayoutExtractor) {
        self.drc = drc
        self.lvs = lvs
        self.extractor = extractor
    }

    /// Discovers the full DRC+LVS toolchain (Magic + Netgen + Sky130 PDK). Returns
    /// nil if any piece is missing — the caller decides how to handle that.
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> LiveSignoffService? {
        guard let drc = MagicDRCSignoff.locate(environment: environment, fileManager: fileManager),
              let lvs = NetgenLVSSignoff.locate(environment: environment, fileManager: fileManager),
              let driver = MagicLayoutExtractor.bundledDriverScriptURL else {
            return nil
        }
        // The LVS-netlist extractor reuses the DRC signoff's resolved Magic + PDK.
        let extractor = MagicLayoutExtractor(
            magicExecutableURL: drc.magicExecutableURL,
            rcFileURL: drc.rcFileURL,
            pdkRoot: drc.pdkRoot,
            driverScriptURL: driver
        )
        return LiveSignoffService(drc: drc, lvs: lvs, extractor: extractor)
    }

    /// Runs DRC then LVS on `layoutGDS` (top cell `topCell`) against
    /// `schematicNetlist`, returning a review whose `passed` is true only when
    /// both the DRC and LVS reports pass.
    public func run(
        layoutGDS: URL,
        topCell: String,
        schematicNetlist: URL,
        artifactDirectory: URL
    ) async throws -> ExternalSignoffReview {
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)

        let drcResult = try await ExternalSignoffCommandService(parser: MagicDRCSignoff.reportParser).run(
            command: drc.command(cell: topCell, gds: layoutGDS, artifactDirectory: artifactDirectory),
            artifactDirectory: artifactDirectory
        )

        let layoutNetlist = try extractor.extractLayoutNetlist(
            gds: layoutGDS, cell: topCell, into: artifactDirectory
        )

        let lvsResult = try await ExternalSignoffCommandService(parser: NetgenLVSSignoff.reportParser).run(
            command: lvs.command(
                layoutNetlist: layoutNetlist,
                schematicNetlist: schematicNetlist,
                topCell: topCell,
                artifactDirectory: artifactDirectory
            ),
            artifactDirectory: artifactDirectory
        )

        return ExternalSignoffReview(reports: [drcResult.report, lvsResult.report])
    }
}
