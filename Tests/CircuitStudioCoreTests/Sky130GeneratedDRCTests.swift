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

    /// A CMOS inverter core: NMOS (bottom, n+) and PMOS (top, p+ in n-well) sharing a
    /// vertical poly gate (input), with the two drains joined by a li1 strip (output)
    /// and separate li1 source landings. Built from the proven transistor blocks.
    private func inverterCore(cell: String) -> LayoutDocument {
        document(cell: cell, shapes: [
            // NMOS active + n+ implant (bottom)
            rect("diff", 0.00, 0.00, 1.00, 0.42),
            rect("nsdm", -0.125, -0.125, 1.25, 0.67),
            // PMOS active + p+ implant + n-well (top)
            rect("diff", 0.00, 1.40, 1.00, 0.42),
            rect("psdm", -0.125, 1.275, 1.25, 0.67),
            rect("nwell", -0.21, 1.19, 1.42, 0.84),
            // shared poly gate (input), endcaps 0.13 beyond both actives
            rect("poly", 0.42, -0.13, 0.16, 2.08),
            // source/drain contacts (NMOS y~0.125, PMOS y~1.525), sources left, drains right
            rect("licon1", 0.10, 0.125, 0.17, 0.17),
            rect("licon1", 0.73, 0.125, 0.17, 0.17),
            rect("licon1", 0.10, 1.525, 0.17, 0.17),
            rect("licon1", 0.73, 1.525, 0.17, 0.17),
            // li1: separate source landings (left) + a tall output strip joining both
            // drains (right) = node Y
            rect("li1", 0.02, 0.045, 0.33, 0.33),
            rect("li1", 0.02, 1.445, 0.33, 0.33),
            rect("li1", 0.65, 0.045, 0.33, 1.81),
        ])
    }

    @Test("A generated CMOS inverter core passes real Magic Sky130 DRC",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func inverterCoreClean() async throws {
        let report = try await runDRC(cell: "gen_inverter", document: inverterCore(cell: "gen_inverter"))
        #expect(report.passed,
                "diagnostics: \(report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    private func label(_ text: String, _ layer: String, _ x: Double, _ y: Double) -> LayoutLabel {
        LayoutLabel(text: text, position: LayoutPoint(x: x, y: y), layer: Sky130LayoutTech.layer(layer))
    }

    /// The inverter core with port net labels (A on the poly gate, Y on the output
    /// strip, VPWR/VGND on the source landings) so the extracted netlist names match.
    private func labeledInverter(cell: String) -> LayoutDocument {
        var doc = inverterCore(cell: cell)
        var c = doc.cells[0]
        c.labels = [
            label("A", "poly", 0.50, 0.90),
            label("Y", "li1", 0.81, 0.95),
            label("VPWR", "li1", 0.18, 1.60),
            label("VGND", "li1", 0.18, 0.20),
        ]
        doc.cells[0] = c
        return doc
    }

    /// The inverter with well/substrate taps so both FET bulks become named rails:
    /// an n+ tap in the n-well tied to VPWR, a p+ tap in the substrate tied to VGND.
    private func tappedInverter(cell: String) -> LayoutDocument {
        let shapes: [LayoutShape] = [
            // NMOS active + n+ implant
            rect("diff", 0.00, 0.00, 1.00, 0.42),
            rect("nsdm", -0.125, -0.125, 1.25, 0.67),
            // PMOS active + p+ implant + n-well (extended up to hold the n-well tap)
            rect("diff", 0.00, 1.40, 1.00, 0.42),
            rect("psdm", -0.125, 1.275, 1.25, 0.67),
            rect("nwell", -0.21, 1.19, 1.42, 1.57),    // extended up to enclose the n-well tap by 0.18
            // shared poly gate
            rect("poly", 0.42, -0.13, 0.16, 2.08),
            // source/drain contacts
            rect("licon1", 0.10, 0.125, 0.17, 0.17),
            rect("licon1", 0.73, 0.125, 0.17, 0.17),
            rect("licon1", 0.10, 1.525, 0.17, 0.17),
            rect("licon1", 0.73, 1.525, 0.17, 0.17),
            // output li1 joining the two drains (Y)
            rect("li1", 0.65, 0.045, 0.33, 1.81),
            // p+ substrate tap (-> VGND): tap encloses its licon1 by 0.12 (licon.7)
            rect("diff", 0.045, -0.785, 0.41, 0.41),
            rect("psdm", -0.08, -0.91, 0.66, 0.66),
            rect("licon1", 0.165, -0.665, 0.17, 0.17),
            rect("li1", 0.02, -0.81, 0.41, 1.185),      // VGND: NMOS source + substrate tap (enclose by 0.08)
            // n+ n-well tap (-> VPWR): tap encloses its licon1 by 0.12, n-well by 0.18
            rect("diff", 0.045, 2.17, 0.41, 0.41),
            rect("nsdm", -0.08, 2.045, 0.66, 0.66),
            rect("licon1", 0.165, 2.29, 0.17, 0.17),
            rect("li1", 0.02, 1.445, 0.41, 1.105),      // VPWR: PMOS source + n-well tap
        ]
        var c = LayoutCell(name: cell, shapes: shapes)
        c.labels = [
            label("A", "poly", 0.50, 0.90),
            label("Y", "li1", 0.81, 0.95),
            label("VPWR", "li1", 0.18, 2.00),
            label("VGND", "li1", 0.18, 0.20),
        ]
        return LayoutDocument(name: cell, cells: [c], topCellID: c.id)
    }

    @Test("A generated inverter with well/substrate taps passes real Magic Sky130 DRC",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func tappedInverterClean() async throws {
        let report = try await runDRC(cell: "gen_inv_tapped", document: tappedInverter(cell: "gen_inv_tapped"))
        #expect(report.passed,
                "diagnostics: \(report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    @Test("The generated inverter matches its schematic under real Netgen LVS",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func inverterMatchesSchematicLVS() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-lvs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gds = dir.appending(path: "gen_inv_tapped.gds")
        try MaskDataFormatConverter(tech: Sky130LayoutTech.tech())
            .exportDocument(tappedInverter(cell: "gen_inv_tapped"), to: gds, format: .gds)

        // The matching schematic: NMOS (VGND<->Y) and PMOS (VPWR<->Y), shared gate A,
        // bulks tied to their rails (as the taps do in the layout). No port list — the
        // extracted layout cell has none (its labels are nets), so Netgen matches the
        // named nets directly instead of failing on port declarations.
        let schematic = """
        * generated inverter reference
        .subckt gen_inv_tapped
        X0 Y A VPWR VPWR sky130_fd_pr__pfet_01v8 w=0.42 l=0.16
        X1 Y A VGND VGND sky130_fd_pr__nfet_01v8 w=0.42 l=0.16
        .ends
        """
        let schematicURL = dir.appending(path: "gen_inv_tapped.spice")
        try schematic.write(to: schematicURL, atomically: true, encoding: .utf8)

        let signoff = try #require(LiveSignoffService.locate())
        let review = try await signoff.run(
            layoutGDS: gds, topCell: "gen_inv_tapped",
            schematicNetlist: schematicURL, artifactDirectory: dir
        )
        let lvs = try #require(review.reports.first { $0.kind == .lvs })
        #expect(lvs.passed, "LVS: \(lvs.diagnostics.map { ($0.ruleID ?? "?", $0.message) }); netlist at \(dir.path)")
    }

    @Test("The generated inverter extracts as two FETs (an nfet and a pfet)",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func inverterExtractsTwoFETs() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gds = dir.appending(path: "gen_inverter.gds")
        try MaskDataFormatConverter(tech: Sky130LayoutTech.tech())
            .exportDocument(labeledInverter(cell: "gen_inverter"), to: gds, format: .gds)

        let drc = try #require(MagicDRCSignoff.locate())
        let extractor = MagicLayoutExtractor(
            magicExecutableURL: drc.magicExecutableURL, rcFileURL: drc.rcFileURL,
            pdkRoot: drc.pdkRoot, driverScriptURL: try #require(MagicLayoutExtractor.bundledDriverScriptURL)
        )
        let netlistURL = try extractor.extractLayoutNetlist(gds: gds, cell: "gen_inverter", into: dir)
        let netlist = try String(contentsOf: netlistURL, encoding: .utf8)

        let devices = netlist.split(whereSeparator: \.isNewline).filter { $0.first == "X" || $0.first == "M" }
        let nfets = netlist.lowercased().components(separatedBy: "nfet").count - 1
        let pfets = netlist.lowercased().components(separatedBy: "pfet").count - 1
        #expect(devices.count == 2, "expected 2 devices; netlist:\n\(netlist)")
        #expect(nfets >= 1 && pfets >= 1, "expected an nfet and a pfet; netlist:\n\(netlist)")
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
