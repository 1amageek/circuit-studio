import Foundation
import LayoutCore
import LayoutTech
import LayoutIO

/// The agent-callable physical flow for a Sky130 cell: synthesize the layout, export
/// it to GDS, and sign it off with the real tools (Magic DRC + Netgen LVS). Returns
/// the GDS and the signoff review — a tapeout-relevant artifact plus its evidence.
///
/// `locate()` returns nil when the toolchain is unavailable; the caller treats nil as
/// a hard error (no silent fallback to a fake result).
public struct Sky130CellSignoffService: Sendable {

    public struct Output: Sendable {
        public let cellName: String
        public let gdsURL: URL
        public let schematicURL: URL
        public let review: ExternalSignoffReview
        public var passed: Bool { review.passed }
    }

    private let signoff: LiveSignoffService

    public init(signoff: LiveSignoffService) {
        self.signoff = signoff
    }

    /// Available only with the real Magic + Netgen + Sky130 toolchain.
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> Sky130CellSignoffService? {
        LiveSignoffService.locate(environment: environment, fileManager: fileManager)
            .map(Sky130CellSignoffService.init(signoff:))
    }

    /// Synthesizes ANY `Sky130CellGenerator` cell: writes its GDS + reference schematic
    /// under `directory`, runs real DRC + LVS, and returns the artifacts and review.
    /// This is the cell-agnostic agent entry point — a new cell type needs only a new
    /// generator, no change here.
    public func synthesize(
        _ generator: some Sky130CellGenerator,
        name: String,
        into directory: URL
    ) async throws -> Output {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let gdsURL = directory.appending(path: "\(name).gds")
        try MaskDataFormatConverter(tech: Sky130LayoutTech.tech())
            .exportDocument(generator.generate(name: name), to: gdsURL, format: .gds)

        let schematicURL = directory.appending(path: "\(name).spice")
        try generator.schematic(name: name).write(to: schematicURL, atomically: true, encoding: .utf8)

        let review = try await signoff.run(
            layoutGDS: gdsURL, topCell: name,
            schematicNetlist: schematicURL, artifactDirectory: directory
        )
        return Output(cellName: name, gdsURL: gdsURL, schematicURL: schematicURL, review: review)
    }

    /// Synthesizes the inverter, writes its GDS + reference schematic under
    /// `directory`, runs real DRC + LVS, and returns the artifacts and review.
    public func synthesizeInverter(
        name: String = "sky130_inverter",
        width: Double = 0.42,
        into directory: URL,
        generator: Sky130InverterGenerator = Sky130InverterGenerator()
    ) async throws -> Output {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let gdsURL = directory.appending(path: "\(name).gds")
        try MaskDataFormatConverter(tech: Sky130LayoutTech.tech())
            .exportDocument(generator.generate(name: name, width: width), to: gdsURL, format: .gds)

        let schematicURL = directory.appending(path: "\(name).spice")
        try generator.schematic(name: name, width: width).write(to: schematicURL, atomically: true, encoding: .utf8)

        let review = try await signoff.run(
            layoutGDS: gdsURL, topCell: name,
            schematicNetlist: schematicURL, artifactDirectory: directory
        )
        return Output(cellName: name, gdsURL: gdsURL, schematicURL: schematicURL, review: review)
    }
}
