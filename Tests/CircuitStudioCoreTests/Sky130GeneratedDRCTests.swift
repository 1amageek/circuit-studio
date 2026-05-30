import Foundation
import Testing
import LayoutCore
import LayoutTech
import LayoutIO
@testable import CircuitStudioApp

/// Proves the generate → export → REAL Magic Sky130 DRC chain on GENERATED geometry
/// (not a fixture GDS): a layout built in the IR on the Sky130 tech is exported to
/// Sky130-layer GDS and checked by Magic's Sky130 techfile. Gated on the toolchain.
@Suite("Sky130 generated-geometry DRC (gated)")
struct Sky130GeneratedDRCTests {

    static let available = MagicDRCSignoff.locate() != nil

    private func runDRC(cell: String, document: LayoutDocument) async throws -> ExternalSignoffToolReport {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-gen-drc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gds = dir.appending(path: "\(cell).gds")
        try MaskDataFormatConverter(tech: Sky130LayoutTech.tech()).exportDocument(document, to: gds, format: .gds)

        let drc = try #require(MagicDRCSignoff.locate())
        let result = try await ExternalSignoffCommandService(parser: MagicDRCSignoff.reportParser).run(
            command: drc.command(cell: cell, gds: gds, artifactDirectory: dir),
            artifactDirectory: dir
        )
        return result.report
    }

    private func met1Rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> LayoutShape {
        LayoutShape(
            layer: Sky130LayoutTech.layer("met1"),
            geometry: .rect(LayoutRect(origin: LayoutPoint(x: x, y: y), size: LayoutSize(width: w, height: h)))
        )
    }

    private func document(cell: String, shapes: [LayoutShape]) -> LayoutDocument {
        let cellIR = LayoutCell(name: cell, shapes: shapes)
        return LayoutDocument(name: cell, cells: [cellIR], topCellID: cellIR.id)
    }

    /// A single legal met1 wire (0.20 µm wide >= met1 minimum width 0.14 µm).
    private func met1Wire(cell: String, width: Double) -> LayoutDocument {
        document(cell: cell, shapes: [met1Rect(0, 0, 2.0, width)])
    }

    @Test("A legal-width met1 wire generated on Sky130 layers passes real Magic DRC",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func legalMet1Clean() async throws {
        // 0.20 µm >= met1 minimum width 0.14 µm.
        let report = try await runDRC(cell: "gen_met1_clean", document: met1Wire(cell: "gen_met1_clean", width: 0.20))
        #expect(report.passed,
                "expected clean; diagnostics: \(report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    @Test("A met1 spacing violation in generated geometry is caught AND named (met1.2)",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func illegalMet1SpacingNamed() async throws {
        // Two legal-width met1 wires 0.10 µm apart (< met1 minimum spacing 0.14 µm).
        let doc = document(cell: "gen_met1_space", shapes: [
            met1Rect(0, 0.0, 2.0, 0.20),
            met1Rect(0, 0.30, 2.0, 0.20),   // gap = 0.30 - 0.20 = 0.10 µm
        ])
        let report = try await runDRC(cell: "gen_met1_space", document: doc)
        #expect(!report.passed, "the spacing violation must be rejected")
        // Named (met1.2), not just counted — the physical loop needs the rule code.
        #expect(report.diagnostics.contains { ($0.ruleID ?? "").lowercased().contains("met1") },
                "expected a named met1 rule; got \(report.diagnostics.map { $0.ruleID ?? "?" })")
    }
}
