import Foundation
import LayoutCore
import LayoutTech
import LayoutIO

/// A `LayoutDRCChecking` backed by the real Magic + Sky130 toolchain: it exports the
/// document to Sky130-layer GDS and runs Magic's Sky130 DRC, returning the parsed
/// report. `locate()` returns nil when the toolchain is absent (no silent fallback).
public struct Sky130LayoutDRC: LayoutDRCChecking {

    private let drc: MagicDRCSignoff

    public init(drc: MagicDRCSignoff) {
        self.drc = drc
    }

    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> Sky130LayoutDRC? {
        MagicDRCSignoff.locate(environment: environment, fileManager: fileManager).map(Sky130LayoutDRC.init(drc:))
    }

    public func check(_ document: LayoutDocument, cell: String, in directory: URL) async throws -> ExternalSignoffToolReport {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let gds = directory.appending(path: "\(cell).gds")
        try MaskDataFormatConverter(tech: Sky130LayoutTech.tech()).exportDocument(document, to: gds, format: .gds)

        let result = try await ExternalSignoffCommandService(parser: MagicDRCSignoff.reportParser).run(
            command: drc.command(cell: cell, gds: gds, artifactDirectory: directory),
            artifactDirectory: directory
        )
        return result.report
    }
}
