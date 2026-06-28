import Foundation
import LayoutCore
import LayoutIO
import LayoutTech

public struct MagicLayoutDRCChecker: LayoutDRCChecking {
    private let drc: MagicDRCSignoff
    private let layoutTechnology: LayoutTechDatabase

    public init(drc: MagicDRCSignoff, layoutTechnology: LayoutTechDatabase) {
        self.drc = drc
        self.layoutTechnology = layoutTechnology
    }

    public static func locate(
        layoutTechnology: LayoutTechDatabase? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> MagicLayoutDRCChecker? {
        guard let drc = MagicDRCSignoff.locate(environment: environment, fileManager: fileManager) else {
            return nil
        }
        do {
            let technology: LayoutTechDatabase
            if let layoutTechnology {
                technology = layoutTechnology
            } else {
                technology = try LayoutTechnologyCatalog.loadDefaultTechnology()
            }
            return MagicLayoutDRCChecker(drc: drc, layoutTechnology: technology)
        } catch {
            return nil
        }
    }

    public func check(
        _ document: LayoutDocument,
        cell: String,
        in directory: URL
    ) async throws -> ExternalSignoffToolReport {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let gds = directory.appending(path: "\(cell).gds")
        try MaskDataFormatConverter(tech: layoutTechnology).exportDocument(document, to: gds, format: .gds)

        let result = try await ExternalSignoffCommandService(parser: MagicDRCSignoff.reportParser).run(
            command: drc.command(cell: cell, gds: gds, artifactDirectory: directory),
            artifactDirectory: directory
        )
        return result.report
    }
}
