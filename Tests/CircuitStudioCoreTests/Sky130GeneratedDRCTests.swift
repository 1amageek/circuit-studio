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

    private func rect(_ layer: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> LayoutShape {
        LayoutShape(
            layer: Sky130LayoutTech.layer(layer),
            geometry: .rect(LayoutRect(origin: LayoutPoint(x: x, y: y), size: LayoutSize(width: w, height: h)))
        )
    }

    private func met1Rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> LayoutShape {
        rect("met1", x, y, w, h)
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

    /// A minimal NMOS: an n+ active strip with a poly gate across it (endcaps beyond
    /// diff), nsdm implant enclosing the active, and licon1+li1 contacts on the
    /// source/drain. Dimensions follow Sky130 minimums (poly.8 endcap 0.13, licon1
    /// diff enclosure 0.06, li1 enclosure 0.08, licon1-poly spacing 0.055).
    private func nmosTransistor(cell: String) -> LayoutDocument {
        document(cell: cell, shapes: [
            // n+ active (difftap = 65/20), 1.0 x 0.42
            rect("diff", 0.00, 0.00, 1.00, 0.42),
            // poly gate, length 0.16, extends 0.13 beyond diff top/bottom
            rect("poly", 0.42, -0.13, 0.16, 0.68),
            // nsdm implant enclosing the active by 0.125
            rect("nsdm", -0.125, -0.125, 1.25, 0.67),
            // source / drain licon1 contacts (0.17), >= 0.06 from poly, in diff
            rect("licon1", 0.10, 0.125, 0.17, 0.17),
            rect("licon1", 0.73, 0.125, 0.17, 0.17),
            // li1 over each contact, enclosing it by 0.08
            rect("li1", 0.02, 0.045, 0.33, 0.33),
            rect("li1", 0.65, 0.045, 0.33, 0.33),
        ])
    }

    @Test("A generated minimal NMOS passes real Magic Sky130 DRC",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func nmosTransistorClean() async throws {
        let report = try await runDRC(cell: "gen_nmos", document: nmosTransistor(cell: "gen_nmos"))
        #expect(report.passed,
                "diagnostics: \(report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    /// A minimal PMOS: like the NMOS but the active is p+ (psdm) inside an n-well that
    /// encloses the p-diff by >= 0.18 (diff/tap.8) and is itself >= 0.84 wide (nwell.1).
    private func pmosTransistor(cell: String) -> LayoutDocument {
        document(cell: cell, shapes: [
            rect("diff", 0.00, 0.00, 1.00, 0.42),
            rect("poly", 0.42, -0.13, 0.16, 0.68),
            rect("psdm", -0.125, -0.125, 1.25, 0.67),
            // n-well enclosing the p-diff by 0.21 (>= 0.18) and 0.84 tall (>= nwell.1).
            rect("nwell", -0.21, -0.21, 1.42, 0.84),
            rect("licon1", 0.10, 0.125, 0.17, 0.17),
            rect("licon1", 0.73, 0.125, 0.17, 0.17),
            rect("li1", 0.02, 0.045, 0.33, 0.33),
            rect("li1", 0.65, 0.045, 0.33, 0.33),
        ])
    }

    @Test("A generated minimal PMOS (p-diff in n-well) passes real Magic Sky130 DRC",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func pmosTransistorClean() async throws {
        let report = try await runDRC(cell: "gen_pmos", document: pmosTransistor(cell: "gen_pmos"))
        #expect(report.passed,
                "diagnostics: \(report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    @Test("A generated li1-mcon-met1 via stack passes real Magic DRC",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func viaStackClean() async throws {
        // li1 and met1 plates (0.40 µm) generously enclosing a single 0.17 µm mcon
        // cut centred between them — the building block that connects layers.
        let doc = document(cell: "gen_via_stack", shapes: [
            rect("li1", 0, 0, 0.40, 0.40),
            rect("mcon", 0.115, 0.115, 0.17, 0.17),
            rect("met1", 0, 0, 0.40, 0.40),
        ])
        let report = try await runDRC(cell: "gen_via_stack", document: doc)
        #expect(report.passed,
                "expected clean; diagnostics: \(report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }
}
