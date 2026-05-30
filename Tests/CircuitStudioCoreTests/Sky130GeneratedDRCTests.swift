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

    /// A full via stack li1 -> mcon -> met1 -> via -> met2: the vertical transition the
    /// 2-layer channel router uses to lift a signal from in-cell li1 up to a met2 track.
    private func viaStack(cell: String) -> LayoutDocument {
        document(cell: cell, shapes: [
            // li1 -> mcon -> met1 (left), then a met1 wire across to via -> met2 (right),
            // so the two vias are not stacked (each cut generously enclosed by 0.09).
            rect("li1", 0.00, 0.00, 0.34, 0.34),
            rect("mcon", 0.085, 0.085, 0.17, 0.17),
            rect("met1", 0.00, 0.00, 0.90, 0.34),
            rect("via", 0.60, 0.095, 0.15, 0.15),
            rect("met2", 0.51, 0.005, 0.33, 0.33),
        ])
    }

    @Test("A generated li1-mcon-met1-via-met2 stack passes real Magic Sky130 DRC",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func viaStackMet2Clean() async throws {
        let report = try await runDRC(cell: "gen_via_stack2", document: viaStack(cell: "gen_via_stack2"))
        #expect(report.passed,
                "diagnostics: \(report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    /// A poly contact (gate-input tap): a widened poly pad with a licon1 to li1, the
    /// nitride-poly-cut (npc) enclosing the contact. This is the primitive that lets a
    /// wire DRIVE a gate — the enabling piece for connecting one cell's output to the
    /// next cell's input. Sky130: poly encloses licon by >=0.05, npc encloses licon by
    /// >=0.10, li1 encloses licon by 0.08.
    private func polyContact(cell: String) -> LayoutDocument {
        document(cell: cell, shapes: [
            rect("poly", 0.40, 0.40, 0.33, 0.33),     // poly pad (>= 0.17 + 2*0.05)
            rect("licon1", 0.48, 0.48, 0.17, 0.17),   // contact, poly enclosure 0.08
            rect("npc", 0.38, 0.38, 0.37, 0.37),      // npc enclosing licon by 0.10
            rect("li1", 0.40, 0.40, 0.33, 0.33),      // li1 enclosing licon by 0.08
        ])
    }

    /// Synthesize a netlist into a layout + schematic, export, and sign off (DRC + LVS).
    private func signoffSynthesized(_ netlist: CMOSGateNetlist) async throws -> ExternalSignoffReview {
        let synth = Sky130StandardCellSynthesizer()
        let doc = try synth.synthesize(netlist)
        let schematic = synth.schematic(netlist)
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-synth-\(netlist.name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gds = dir.appending(path: "\(netlist.name).gds")
        try MaskDataFormatConverter(tech: Sky130LayoutTech.tech()).exportDocument(doc, to: gds, format: .gds)
        let schematicURL = dir.appending(path: "\(netlist.name).spice")
        try schematic.write(to: schematicURL, atomically: true, encoding: .utf8)
        let signoff = try #require(LiveSignoffService.locate())
        return try await signoff.run(layoutGDS: gds, topCell: netlist.name,
                                     schematicNetlist: schematicURL, artifactDirectory: dir)
    }

    @Test("The standard-cell synthesizer auto-lays-out a netlist DRC + LVS clean",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)),
          arguments: [
            CMOSGateNetlist.inverter(name: "synth_inv"),
            CMOSGateNetlist.nand(name: "synth_nand2", inputs: ["A", "B"]),
            CMOSGateNetlist.nor(name: "synth_nor2", inputs: ["A", "B"]),
            CMOSGateNetlist.nand(name: "synth_nand3", inputs: ["A", "B", "C"]),
            CMOSGateNetlist.nor(name: "synth_nor3", inputs: ["A", "B", "C"]),
          ])
    func synthesizerSignsOff(netlist: CMOSGateNetlist) async throws {
        // Place + route is done by the SYSTEM from the netlist topology — nand3/nor3 were
        // never hand-laid, proving automatic layout synthesis (not a golden fixture).
        let review = try await signoffSynthesized(netlist)
        let drc = try #require(review.reports.first { $0.kind == .drc })
        let lvs = try #require(review.reports.first { $0.kind == .lvs })
        #expect(drc.passed, "\(netlist.name) DRC: \(drc.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
        #expect(lvs.passed, "\(netlist.name) LVS: \(lvs.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    /// Auto place & route a gate-level netlist, export, and sign off (DRC + LVS).
    private func signoffCircuit(_ netlist: GateLevelNetlist) async throws -> ExternalSignoffReview {
        let synth = Sky130CircuitSynthesizer()
        let doc = try synth.synthesize(netlist)
        let spice = synth.referenceSPICE(netlist)
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-circuit-\(netlist.name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gds = dir.appending(path: "\(netlist.name).gds")
        try MaskDataFormatConverter(tech: Sky130LayoutTech.tech()).exportDocument(doc, to: gds, format: .gds)
        let spiceURL = dir.appending(path: "\(netlist.name).spice")
        try spice.write(to: spiceURL, atomically: true, encoding: .utf8)
        let signoff = try #require(LiveSignoffService.locate())
        return try await signoff.run(layoutGDS: gds, topCell: netlist.name,
                                     schematicNetlist: spiceURL, artifactDirectory: dir)
    }

    @Test("Auto place & route: a gate-level netlist becomes a DRC + LVS clean circuit",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)),
          arguments: [
            GateLevelNetlist.and2(name: "circ_and2"),
            GateLevelNetlist.or2(name: "circ_or2"),
            GateLevelNetlist.inverterChain(name: "circ_invchain3", stages: 3),
          ])
    func circuitPlaceAndRouteSignsOff(netlist: GateLevelNetlist) async throws {
        // Multiple cells placed in a row + inter-cell li1 routing, done by the SYSTEM.
        let review = try await signoffCircuit(netlist)
        let drc = try #require(review.reports.first { $0.kind == .drc })
        let lvs = try #require(review.reports.first { $0.kind == .lvs })
        #expect(drc.passed, "\(netlist.name) DRC: \(drc.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
        #expect(lvs.passed, "\(netlist.name) LVS: \(lvs.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    @Test("The router handles multi-fanout and feedback (DRC + LVS clean)",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func routerHandlesFanoutAndFeedback() async throws {
        let fanout = GateLevelNetlist(name: "circ_fanout", instances: [
            .init(name: "g0", cell: .inverter(name: "inv"), netMap: ["A": "a", "Y": "m"]),
            .init(name: "g1", cell: .inverter(name: "inv"), netMap: ["A": "m", "Y": "p"]),
            .init(name: "g2", cell: .inverter(name: "inv"), netMap: ["A": "m", "Y": "q"]),
            .init(name: "g3", cell: .nand(name: "nand2", inputs: ["A", "B"]), netMap: ["A": "p", "B": "q", "Y": "r"]),
            .init(name: "g4", cell: .inverter(name: "inv"), netMap: ["A": "r", "Y": "y"]),
        ], inputs: ["a"], output: "y")
        let srLatch = GateLevelNetlist(name: "circ_srlatch", instances: [
            .init(name: "g0", cell: .nor(name: "nor2", inputs: ["A", "B"]), netMap: ["A": "s", "B": "qn", "Y": "q"]),
            .init(name: "g1", cell: .nor(name: "nor2", inputs: ["A", "B"]), netMap: ["A": "r", "B": "q", "Y": "qn"]),
        ], inputs: ["s", "r"], output: "q")
        for netlist in [fanout, srLatch] {
            let review = try await signoffCircuit(netlist)
            let drc = try #require(review.reports.first { $0.kind == .drc })
            let lvs = try #require(review.reports.first { $0.kind == .lvs })
            #expect(drc.passed, "\(netlist.name) DRC: \(drc.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
            #expect(lvs.passed, "\(netlist.name) LVS: \(lvs.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
        }
    }

    @Test("A circuit LOADED from a structural Verilog file is synthesized DRC + LVS clean",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func verilogFileSignsOff() async throws {
        // The circuit is DATA on disk, not hardcoded in Swift: write a Verilog netlist to
        // a file, load + parse it, then place & route + sign it off.
        let verilog = """
        // AND2 = NAND2 -> INV
        module and2gate (a, b, y);
          input a, b;
          output y;
          nand2 g0 ( .A(a), .B(b), .Y(n) );
          inv   g1 ( .A(n), .Y(y) );
        endmodule
        """
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-verilog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let vURL = dir.appending(path: "and2gate.v")
        try verilog.write(to: vURL, atomically: true, encoding: .utf8)

        let loaded = try String(contentsOf: vURL, encoding: .utf8)
        let netlist = try VerilogStructuralParser().parse(loaded)
        #expect(netlist.name == "and2gate")
        #expect(netlist.inputs.sorted() == ["a", "b"])
        #expect(netlist.instances.count == 2)

        let review = try await signoffCircuit(netlist)
        let drc = try #require(review.reports.first { $0.kind == .drc })
        let lvs = try #require(review.reports.first { $0.kind == .lvs })
        #expect(drc.passed, "DRC: \(drc.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
        #expect(lvs.passed, "LVS: \(lvs.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    @Test("A Boolean expression LOADED from text is parsed, mapped, and synthesized DRC + LVS clean",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func booleanExpressionFromTextSignsOff() async throws {
        // Logic intent is a string (loadable from a file), not a Swift AST literal.
        let netlist = try BooleanExpressionParser().netlist("y = (a & b) | c", name: "circ_expr", output: "y")
        #expect(netlist.inputs.sorted() == ["a", "b", "c"])
        let review = try await signoffCircuit(netlist)
        let drc = try #require(review.reports.first { $0.kind == .drc })
        let lvs = try #require(review.reports.first { $0.kind == .lvs })
        #expect(drc.passed, "DRC: \(drc.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
        #expect(lvs.passed, "LVS: \(lvs.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    @Test("Logic intent -> GDS: a Boolean expression is mapped, placed, routed, DRC + LVS clean",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func booleanExpressionSignsOff() async throws {
        // Y = (A AND B) OR C — intent only; the system maps it to gates and lays it out.
        let expr = BooleanGateMapper.Expr.or(.and(.input("A"), .input("B")), .input("C"))
        let netlist = BooleanGateMapper().map(expr, name: "circ_aoi", output: "y")
        let review = try await signoffCircuit(netlist)
        let drc = try #require(review.reports.first { $0.kind == .drc })
        let lvs = try #require(review.reports.first { $0.kind == .lvs })
        #expect(drc.passed, "DRC: \(drc.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
        #expect(lvs.passed, "LVS: \(lvs.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    @Test("A generated poly contact (npc + poly licon) passes real Magic Sky130 DRC",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func polyContactClean() async throws {
        let report = try await runDRC(cell: "gen_poly_contact", document: polyContact(cell: "gen_poly_contact"))
        #expect(report.passed,
                "diagnostics: \(report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    /// A two-stage CMOS buffer = two inverter slices in one cell (continuous n-well +
    /// shared VPWR/VGND rails + p/n taps), with stage-1 output (mid) routed to stage-2
    /// input via a poly contact. This is the first multi-cell COMPOSITION — a circuit,
    /// not a single cell. Y = A.
    private func bufferComposite(cell: String) -> LayoutDocument {
        var c = LayoutCell(name: cell, shapes: [
            // --- NMOS slice 1 (stage 1) / slice 2 (stage 2), 0.40 gap ---
            rect("diff", 0.00, 0.00, 1.00, 0.42),
            rect("licon1", 0.10, 0.125, 0.17, 0.17),    // VGND (stage1 source)
            rect("licon1", 0.73, 0.125, 0.17, 0.17),    // mid  (stage1 NMOS drain)
            rect("diff", 1.40, 0.00, 1.00, 0.42),
            rect("licon1", 1.50, 0.125, 0.17, 0.17),    // VGND (stage2 source)
            rect("licon1", 2.13, 0.125, 0.17, 0.17),    // Y    (stage2 NMOS drain)
            rect("nsdm", -0.125, -0.125, 2.65, 0.67),
            // --- PMOS slice 1 / slice 2 ---
            rect("diff", 0.00, 1.40, 1.00, 0.42),
            rect("licon1", 0.10, 1.525, 0.17, 0.17),    // VPWR (stage1 source)
            rect("licon1", 0.73, 1.525, 0.17, 0.17),    // mid  (stage1 PMOS drain)
            rect("diff", 1.40, 1.40, 1.00, 0.42),
            rect("licon1", 1.50, 1.525, 0.17, 0.17),    // VPWR (stage2 source)
            rect("licon1", 2.13, 1.525, 0.17, 0.17),    // Y    (stage2 PMOS drain)
            rect("psdm", -0.125, 1.275, 2.65, 0.67),
            rect("nwell", -0.21, 1.19, 2.82, 1.60),
            // --- gates ---
            rect("poly", 0.42, -0.13, 0.16, 2.08),      // A (stage1 gate)
            rect("poly", 1.82, -0.13, 0.16, 2.08),      // mid (stage2 gate)
            // --- drains joined into output li1 per stage ---
            rect("li1", 0.65, 0.045, 0.33, 1.81),       // mid (stage1 output)
            rect("li1", 2.05, 0.045, 0.33, 1.81),       // Y   (stage2 output)
            // --- A: buffer input poly contact (left of gate A, in the field) ---
            rect("poly", 0.09, 0.74, 0.43, 0.33),
            rect("npc", 0.07, 0.72, 0.37, 0.37),
            rect("licon1", 0.17, 0.82, 0.17, 0.17),
            rect("li1", 0.09, 0.74, 0.33, 0.33),        // input pin A
            // --- stage2 gate input poly contact + route from mid ---
            rect("poly", 1.55, 0.74, 0.43, 0.33),
            rect("npc", 1.53, 0.72, 0.37, 0.37),
            rect("licon1", 1.63, 0.82, 0.17, 0.17),
            rect("li1", 1.55, 0.74, 0.33, 0.33),
            rect("li1", 0.65, 0.82, 0.90, 0.25),        // mid route: stage1 out -> stage2 in
            // --- VPWR rail (top): both PMOS sources + n-well tap ---
            rect("li1", 0.02, 1.445, 0.33, 1.105),      // VPWR stage1 up to rail
            rect("li1", 1.42, 1.445, 0.33, 1.105),      // VPWR stage2 up to rail
            rect("li1", 0.02, 2.10, 2.53, 0.45),        // VPWR rail
            rect("diff", 1.10, 2.20, 0.41, 0.41),       // n+ n-well tap
            rect("nsdm", 0.975, 2.075, 0.66, 0.66),
            rect("licon1", 1.22, 2.32, 0.17, 0.17),
            // --- VGND rail (bottom): both NMOS sources + p+ substrate tap ---
            rect("li1", 0.02, -1.08, 0.33, 1.455),      // VGND stage1 down to rail
            rect("li1", 1.42, -1.08, 0.33, 1.455),      // VGND stage2 down to rail
            rect("li1", 0.02, -1.08, 2.53, 0.62),       // VGND rail
            rect("diff", 1.10, -1.20, 0.41, 0.41),      // p+ substrate tap
            rect("psdm", 0.975, -1.325, 0.66, 0.66),
            rect("licon1", 1.22, -1.08, 0.17, 0.17),
        ])
        c.labels = [
            label("A", "li1", 0.20, 0.90),
            label("Y", "li1", 2.21, 0.95),
            label("VPWR", "li1", 1.20, 2.30),
            label("VGND", "li1", 1.20, -0.70),
        ]
        return LayoutDocument(name: cell, cells: [c], topCellID: c.id)
    }

    @Test("A generated two-stage buffer (two abutted inverters) passes real Magic Sky130 DRC",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func bufferCompositeClean() async throws {
        let report = try await runDRC(cell: "gen_buffer", document: bufferComposite(cell: "gen_buffer"))
        #expect(report.passed,
                "diagnostics: \(report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    @Test("The generated buffer matches its two-inverter schematic under real Netgen LVS",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func bufferMatchesSchematicLVS() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-buf-lvs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gds = dir.appending(path: "gen_buffer.gds")
        try MaskDataFormatConverter(tech: Sky130LayoutTech.tech())
            .exportDocument(bufferComposite(cell: "gen_buffer"), to: gds, format: .gds)

        // Two cascaded inverters: stage 1 (A -> mid), stage 2 (mid -> Y). `mid` is the
        // internal net (stage-1 output li1 + route + stage-2 gate contact), matched by
        // topology. Ports A, Y, VPWR, VGND match the layout's labeled-net ports by name.
        let schematic = """
        * generated two-stage buffer reference
        .subckt gen_buffer A Y VPWR VGND
        X0 mid A VPWR VPWR sky130_fd_pr__pfet_01v8 w=0.42 l=0.16
        X1 mid A VGND VGND sky130_fd_pr__nfet_01v8 w=0.42 l=0.16
        X2 Y mid VPWR VPWR sky130_fd_pr__pfet_01v8 w=0.42 l=0.16
        X3 Y mid VGND VGND sky130_fd_pr__nfet_01v8 w=0.42 l=0.16
        .ends
        """
        let schematicURL = dir.appending(path: "gen_buffer.spice")
        try schematic.write(to: schematicURL, atomically: true, encoding: .utf8)

        let signoff = try #require(LiveSignoffService.locate())
        let review = try await signoff.run(
            layoutGDS: gds, topCell: "gen_buffer",
            schematicNetlist: schematicURL, artifactDirectory: dir
        )
        let lvs = try #require(review.reports.first { $0.kind == .lvs })
        #expect(lvs.passed, "LVS: \(lvs.diagnostics.map { ($0.ruleID ?? "?", $0.message) }); netlist at \(dir.path)")
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

    /// A series NMOS pair on ONE diff strip: two poly gates (A, B) cross a single n+
    /// active, with contacts only at the two ENDS (GND, Y); the middle node between the
    /// gates is shared diffusion (no contact) — the NAND2 pull-down stack. This is the
    /// new pattern a multi-input cell needs: more than one gate over one diffusion.
    private func nmosSeriesStack(cell: String) -> LayoutDocument {
        document(cell: cell, shapes: [
            // single n+ active spanning both gates + both end contacts
            rect("diff", 0.00, 0.00, 1.58, 0.42),
            rect("nsdm", -0.125, -0.125, 1.83, 0.67),
            // two poly gates, 0.42 µm apart (gap 0.42 >= poly.2 0.21)
            rect("poly", 0.42, -0.13, 0.16, 0.68),
            rect("poly", 1.00, -0.13, 0.16, 0.68),
            // end contacts only (the middle node is contact-less shared diffusion)
            rect("licon1", 0.10, 0.125, 0.17, 0.17),
            rect("licon1", 1.31, 0.125, 0.17, 0.17),
            rect("li1", 0.02, 0.045, 0.33, 0.33),
            rect("li1", 1.23, 0.045, 0.33, 0.33),
        ])
    }

    @Test("A generated series-NMOS pair (two gates on one diff) passes real Magic Sky130 DRC",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func nmosSeriesStackClean() async throws {
        let report = try await runDRC(cell: "gen_nmos_series", document: nmosSeriesStack(cell: "gen_nmos_series"))
        #expect(report.passed,
                "diagnostics: \(report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    /// A parallel PMOS pair on ONE p-diff strip in n-well: two poly gates (A, B) cross a
    /// single p+ active, with VDD contacts at the two ENDS and a shared Y contact in the
    /// MIDDLE — the NAND2 pull-up. Both drains tie to the middle (Y), both sources to
    /// the ends (VDD): the two devices are in parallel.
    private func pmosParallelPair(cell: String) -> LayoutDocument {
        document(cell: cell, shapes: [
            rect("diff", 0.00, 0.00, 1.58, 0.42),
            rect("psdm", -0.125, -0.125, 1.83, 0.67),
            // n-well enclosing the p-diff by 0.21 (>= 0.18), >= 0.84 tall (nwell.1)
            rect("nwell", -0.21, -0.21, 2.00, 0.84),
            rect("poly", 0.42, -0.13, 0.16, 0.68),
            rect("poly", 1.00, -0.13, 0.16, 0.68),
            // VDD (left, right) + shared Y (middle)
            rect("licon1", 0.10, 0.125, 0.17, 0.17),
            rect("licon1", 0.65, 0.125, 0.17, 0.17),
            rect("licon1", 1.31, 0.125, 0.17, 0.17),
            rect("li1", 0.02, 0.045, 0.33, 0.33),
            rect("li1", 0.57, 0.045, 0.33, 0.33),
            rect("li1", 1.23, 0.045, 0.33, 0.33),
        ])
    }

    /// A full CMOS NAND2 cell: series NMOS pull-down + parallel PMOS pull-up sharing two
    /// vertical poly gates (A, B), the output Y routed (li1 L-jog) from the PMOS shared
    /// drain to the NMOS top node, with p+/n+ taps to the rails. Y = NOT(A AND B).
    private func nand2Cell(cell: String) -> LayoutDocument {
        var c = LayoutCell(name: cell, shapes: [
            // --- NMOS series pull-down (bottom) ---
            rect("diff", 0.00, 0.00, 1.58, 0.42),
            rect("nsdm", -0.125, -0.125, 1.83, 0.67),
            rect("licon1", 0.10, 0.125, 0.17, 0.17),   // GND (left)
            rect("licon1", 1.31, 0.125, 0.17, 0.17),   // Y   (right); middle n1 = no contact
            // --- PMOS parallel pull-up (top) ---
            rect("diff", 0.00, 1.40, 1.58, 0.42),
            rect("psdm", -0.125, 1.275, 1.83, 0.67),
            rect("licon1", 0.10, 1.525, 0.17, 0.17),   // VDD (left)
            rect("licon1", 0.65, 1.525, 0.17, 0.17),   // Y   (middle, shared drain)
            rect("licon1", 1.31, 1.525, 0.17, 0.17),   // VDD (right)
            // --- shared vertical poly gates ---
            rect("poly", 0.42, -0.13, 0.16, 2.08),     // gate A
            rect("poly", 1.00, -0.13, 0.16, 2.08),     // gate B
            // --- n-well around the PMOS + n-well tap ---
            rect("nwell", -0.21, 1.19, 2.00, 1.60),
            // --- p+ substrate tap (-> VGND), below the NMOS left ---
            rect("diff", 0.02, -0.785, 0.41, 0.41),
            rect("psdm", -0.105, -0.91, 0.66, 0.66),
            rect("licon1", 0.14, -0.665, 0.17, 0.17),
            rect("li1", 0.02, -0.81, 0.38, 1.185),     // VGND: NMOS GND + substrate tap
            // --- n+ n-well tap (-> VPWR), top middle ---
            rect("diff", 0.585, 2.20, 0.41, 0.41),
            rect("nsdm", 0.46, 2.075, 0.66, 0.66),
            rect("licon1", 0.705, 2.32, 0.17, 0.17),
            // --- VPWR: both PMOS sources + n-well tap joined by a top rail ---
            rect("li1", 0.02, 1.445, 0.33, 1.105),     // VDD-left up to rail
            rect("li1", 1.23, 1.445, 0.33, 1.105),     // VDD-right up to rail
            rect("li1", 0.02, 2.10, 1.54, 0.45),       // VPWR rail (over the Y, clears it)
            // --- output Y: L-jog from PMOS shared drain down to the NMOS top node ---
            rect("li1", 0.57, 0.045, 0.33, 1.73),      // vertical: PMOS Y down into the field
            rect("li1", 0.57, 0.045, 0.99, 0.33),      // horizontal: across to the NMOS Y
        ])
        c.labels = [
            label("A", "poly", 0.50, 0.95),
            label("B", "poly", 1.08, 0.95),
            label("Y", "li1", 0.73, 0.20),
            label("VPWR", "li1", 0.78, 2.30),
            label("VGND", "li1", 0.18, 0.20),
        ]
        return LayoutDocument(name: cell, cells: [c], topCellID: c.id)
    }

    @Test("A generated CMOS NAND2 cell passes real Magic Sky130 DRC",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func nand2CellClean() async throws {
        let report = try await runDRC(cell: "gen_nand2", document: nand2Cell(cell: "gen_nand2"))
        #expect(report.passed,
                "diagnostics: \(report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    @Test("The generated NAND2 matches its schematic under real Netgen LVS (internal node, no label)",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func nand2MatchesSchematicLVS() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-nand2-lvs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gds = dir.appending(path: "gen_nand2.gds")
        try MaskDataFormatConverter(tech: Sky130LayoutTech.tech())
            .exportDocument(nand2Cell(cell: "gen_nand2"), to: gds, format: .gds)

        // Y = NOT(A AND B): two parallel PMOS (VPWR<->Y, gates A/B) and two series NMOS
        // (Y<->n1<->VGND, gates B/A). `n1` is the un-labeled shared-diffusion node in the
        // layout; Netgen matches it by topology. Port-less, as the extracted cell is.
        let schematic = """
        * generated NAND2 reference
        .subckt gen_nand2 A B Y VPWR VGND
        X0 Y A VPWR VPWR sky130_fd_pr__pfet_01v8 w=0.42 l=0.16
        X1 Y B VPWR VPWR sky130_fd_pr__pfet_01v8 w=0.42 l=0.16
        X2 Y B n1 VGND sky130_fd_pr__nfet_01v8 w=0.42 l=0.16
        X3 n1 A VGND VGND sky130_fd_pr__nfet_01v8 w=0.42 l=0.16
        .ends
        """
        let schematicURL = dir.appending(path: "gen_nand2.spice")
        try schematic.write(to: schematicURL, atomically: true, encoding: .utf8)

        let signoff = try #require(LiveSignoffService.locate())
        let review = try await signoff.run(
            layoutGDS: gds, topCell: "gen_nand2",
            schematicNetlist: schematicURL, artifactDirectory: dir
        )
        let lvs = try #require(review.reports.first { $0.kind == .lvs })
        #expect(lvs.passed, "LVS: \(lvs.diagnostics.map { ($0.ruleID ?? "?", $0.message) }); netlist at \(dir.path)")
    }

    @Test("Sky130CellSignoffService synthesizes the NAND2 generator, signs it off, and emits GDS",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func synthesizeNAND2SignsOff() async throws {
        // The cell-agnostic agent flow: a different cell type through the SAME service.
        let service = try #require(Sky130CellSignoffService.locate())
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-nand2-flow-\(UUID().uuidString)")
        let output = try await service.synthesize(Sky130NAND2Generator(), name: "sky130_nand2", into: dir)

        let rules = output.review.reports.flatMap { $0.diagnostics }.map { $0.ruleID ?? "?" }
        #expect(output.passed, "synthesized NAND2 must be DRC + LVS clean: \(rules)")
        #expect(FileManager.default.fileExists(atPath: output.gdsURL.path(percentEncoded: false)),
                "the GDS artifact must be emitted")
        #expect(output.review.reports.contains { $0.kind == .drc && $0.passed })
        #expect(output.review.reports.contains { $0.kind == .lvs && $0.passed })
    }

    @Test("Sky130CellSignoffService synthesizes the NOR2 generator, signs it off, and emits GDS",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func synthesizeNOR2SignsOff() async throws {
        // The dual of the NAND2 (parallel NMOS / series PMOS) through the same flow.
        let service = try #require(Sky130CellSignoffService.locate())
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-nor2-flow-\(UUID().uuidString)")
        let output = try await service.synthesize(Sky130NOR2Generator(), name: "sky130_nor2", into: dir)

        let rules = output.review.reports.flatMap { $0.diagnostics }.map { $0.ruleID ?? "?" }
        #expect(output.passed, "synthesized NOR2 must be DRC + LVS clean: \(rules)")
        #expect(FileManager.default.fileExists(atPath: output.gdsURL.path(percentEncoded: false)),
                "the GDS artifact must be emitted")
        #expect(output.review.reports.contains { $0.kind == .drc && $0.passed })
        #expect(output.review.reports.contains { $0.kind == .lvs && $0.passed })
    }

    @Test("A generated parallel-PMOS pair (two gates on one p-diff in n-well) passes real Magic Sky130 DRC",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func pmosParallelPairClean() async throws {
        let report = try await runDRC(cell: "gen_pmos_parallel", document: pmosParallelPair(cell: "gen_pmos_parallel"))
        #expect(report.passed,
                "diagnostics: \(report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
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

    /// A transmission gate: an NMOS (gate EN) and a PMOS (gate ENB) in PARALLEL, passing
    /// A<->B when EN=1 / ENB=0. Unlike an inverter the two gates are SEPARATE nets and the
    /// source/drain are the signal A (left) and B (right); the bulks tie to the rails via
    /// taps. This is the novel primitive a flip-flop is built from.
    private func transmissionGate(cell: String) -> LayoutDocument {
        var c = LayoutCell(name: cell, shapes: [
            // NMOS + PMOS active + implants + n-well
            rect("diff", 0.00, 0.00, 1.00, 0.42),
            rect("nsdm", -0.125, -0.125, 1.25, 0.67),
            rect("diff", 0.00, 1.40, 1.00, 0.42),
            rect("psdm", -0.125, 1.275, 1.25, 0.67),
            rect("nwell", -0.21, 1.19, 1.42, 1.57),
            // SEPARATE gates: EN over the NMOS only, ENB over the PMOS only
            rect("poly", 0.42, -0.13, 0.16, 0.68),     // EN  (NMOS gate, endcaps)
            rect("poly", 0.42, 1.27, 0.16, 0.68),      // ENB (PMOS gate)
            // A/B source-drain contacts on both rows
            rect("licon1", 0.10, 0.125, 0.17, 0.17),
            rect("licon1", 0.73, 0.125, 0.17, 0.17),
            rect("licon1", 0.10, 1.525, 0.17, 0.17),
            rect("licon1", 0.73, 1.525, 0.17, 0.17),
            rect("li1", 0.02, 0.045, 0.33, 1.81),       // A: left diffusions joined
            rect("li1", 0.65, 0.045, 0.33, 1.81),       // B: right diffusions joined
            // p+ substrate tap (-> VGND, NMOS bulk)
            rect("diff", 0.045, -0.785, 0.41, 0.41),
            rect("psdm", -0.08, -0.91, 0.66, 0.66),
            rect("licon1", 0.165, -0.665, 0.17, 0.17),
            rect("li1", 0.02, -0.81, 0.41, 0.40),
            // n+ n-well tap (-> VPWR, PMOS bulk)
            rect("diff", 0.045, 2.17, 0.41, 0.41),
            rect("nsdm", -0.08, 2.045, 0.66, 0.66),
            rect("licon1", 0.165, 2.29, 0.17, 0.17),
            rect("li1", 0.02, 2.13, 0.41, 0.40),
        ])
        c.labels = [
            label("A", "li1", 0.18, 0.90),
            label("B", "li1", 0.81, 0.90),
            label("EN", "poly", 0.50, 0.20),
            label("ENB", "poly", 0.50, 1.60),
            label("VPWR", "li1", 0.18, 2.30),
            label("VGND", "li1", 0.18, -0.65),
        ]
        return LayoutDocument(name: cell, cells: [c], topCellID: c.id)
    }

    @Test("A generated transmission gate passes real Magic Sky130 DRC",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func transmissionGateClean() async throws {
        let report = try await runDRC(cell: "gen_tg", document: transmissionGate(cell: "gen_tg"))
        #expect(report.passed, "diagnostics: \(report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    @Test("The generated transmission gate matches its schematic under real Netgen LVS",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func transmissionGateLVS() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-tg-lvs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gds = dir.appending(path: "gen_tg.gds")
        try MaskDataFormatConverter(tech: Sky130LayoutTech.tech())
            .exportDocument(transmissionGate(cell: "gen_tg"), to: gds, format: .gds)
        let schematic = """
        * transmission gate
        .subckt gen_tg A B EN ENB VPWR VGND
        X0 A EN B VGND sky130_fd_pr__nfet_01v8 w=0.42 l=0.16
        X1 A ENB B VPWR sky130_fd_pr__pfet_01v8 w=0.42 l=0.16
        .ends
        """
        let schematicURL = dir.appending(path: "gen_tg.spice")
        try schematic.write(to: schematicURL, atomically: true, encoding: .utf8)
        let signoff = try #require(LiveSignoffService.locate())
        let review = try await signoff.run(layoutGDS: gds, topCell: "gen_tg",
                                           schematicNetlist: schematicURL, artifactDirectory: dir)
        let lvs = try #require(review.reports.first { $0.kind == .lvs })
        #expect(lvs.passed, "LVS: \(lvs.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    /// A tristate (clocked) inverter: OUT = ~IN when EN=1 / ENB=0, else hi-Z. NMOS series
    /// (gates EN, IN) pull OUT to VGND; PMOS series (gates ENB, IN) pull OUT to VPWR. The
    /// IN gate spans both rows (shared); the EN/ENB gates are split. The other DFF
    /// primitive (the storage/feedback element).
    private func tristateInverter(cell: String) -> LayoutDocument {
        var c = LayoutCell(name: cell, shapes: [
            // NMOS series (VGND - IN - n1 - EN - OUT) and PMOS series (VPWR - IN - p1 - ENB - OUT)
            rect("diff", 0.00, 0.00, 1.58, 0.42),
            rect("nsdm", -0.125, -0.125, 1.83, 0.67),
            rect("diff", 0.00, 1.40, 1.58, 0.42),
            rect("psdm", -0.125, 1.275, 1.83, 0.67),
            rect("nwell", -0.21, 1.19, 2.00, 1.57),
            // gates: IN shared (full height), EN over NMOS only, ENB over PMOS only
            rect("poly", 0.42, -0.13, 0.16, 2.08),     // IN
            rect("poly", 1.00, -0.13, 0.16, 0.68),     // EN  (NMOS)
            rect("poly", 1.00, 1.27, 0.16, 0.68),      // ENB (PMOS)
            // contacts: VGND/VPWR (left), OUT (right); middle nodes n1/p1 contact-less
            rect("licon1", 0.10, 0.125, 0.17, 0.17),
            rect("licon1", 1.31, 0.125, 0.17, 0.17),
            rect("licon1", 0.10, 1.525, 0.17, 0.17),
            rect("licon1", 1.31, 1.525, 0.17, 0.17),
            rect("li1", 1.23, 0.045, 0.33, 1.81),       // OUT: drains joined (right)
            // p+ substrate tap (-> VGND) + VGND strap over NMOS source
            rect("diff", 0.045, -0.785, 0.41, 0.41),
            rect("psdm", -0.08, -0.91, 0.66, 0.66),
            rect("licon1", 0.165, -0.665, 0.17, 0.17),
            rect("li1", 0.02, -0.81, 0.41, 1.185),       // VGND: NMOS source + substrate tap
            // n+ n-well tap (-> VPWR) + VPWR strap over PMOS source
            rect("diff", 0.045, 2.17, 0.41, 0.41),
            rect("nsdm", -0.08, 2.045, 0.66, 0.66),
            rect("licon1", 0.165, 2.29, 0.17, 0.17),
            rect("li1", 0.02, 1.445, 0.41, 1.105),       // VPWR: PMOS source + n-well tap
        ])
        c.labels = [
            label("IN", "poly", 0.50, 0.90),
            label("EN", "poly", 1.08, 0.20),
            label("ENB", "poly", 1.08, 1.60),
            label("OUT", "li1", 1.39, 0.95),
            label("VPWR", "li1", 0.18, 2.00),
            label("VGND", "li1", 0.18, 0.20),
        ]
        return LayoutDocument(name: cell, cells: [c], topCellID: c.id)
    }

    @Test("A generated tristate inverter passes real Magic Sky130 DRC + Netgen LVS",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func tristateInverterSignsOff() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-tinv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gds = dir.appending(path: "gen_tinv.gds")
        try MaskDataFormatConverter(tech: Sky130LayoutTech.tech())
            .exportDocument(tristateInverter(cell: "gen_tinv"), to: gds, format: .gds)
        let schematic = """
        * tristate inverter
        .subckt gen_tinv IN OUT EN ENB VPWR VGND
        X0 OUT EN n1 VGND sky130_fd_pr__nfet_01v8 w=0.42 l=0.16
        X1 n1 IN VGND VGND sky130_fd_pr__nfet_01v8 w=0.42 l=0.16
        X2 OUT ENB p1 VPWR sky130_fd_pr__pfet_01v8 w=0.42 l=0.16
        X3 p1 IN VPWR VPWR sky130_fd_pr__pfet_01v8 w=0.42 l=0.16
        .ends
        """
        let schematicURL = dir.appending(path: "gen_tinv.spice")
        try schematic.write(to: schematicURL, atomically: true, encoding: .utf8)
        let signoff = try #require(LiveSignoffService.locate())
        let review = try await signoff.run(layoutGDS: gds, topCell: "gen_tinv",
                                           schematicNetlist: schematicURL, artifactDirectory: dir)
        let drc = try #require(review.reports.first { $0.kind == .drc })
        let lvs = try #require(review.reports.first { $0.kind == .lvs })
        #expect(drc.passed, "DRC: \(drc.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
        #expect(lvs.passed, "LVS: \(lvs.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    @Test("A generated inverter with well/substrate taps passes real Magic Sky130 DRC",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func tappedInverterClean() async throws {
        let report = try await runDRC(cell: "gen_inv_tapped", document: tappedInverter(cell: "gen_inv_tapped"))
        #expect(report.passed,
                "diagnostics: \(report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    @Test("Sky130CellSignoffService synthesizes an inverter, signs it off, and emits GDS",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func synthesizeSignoffEmitGDS() async throws {
        // The whole agent-callable physical flow in one call.
        let service = try #require(Sky130CellSignoffService.locate())
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-flow-\(UUID().uuidString)")
        let output = try await service.synthesizeInverter(name: "sky130_inverter", into: dir)

        #expect(output.passed, "synthesized cell must be DRC + LVS clean")
        #expect(FileManager.default.fileExists(atPath: output.gdsURL.path(percentEncoded: false)),
                "the GDS artifact must be emitted")
        #expect(output.review.reports.contains { $0.kind == .drc && $0.passed })
        #expect(output.review.reports.contains { $0.kind == .lvs && $0.passed })
    }

    @Test("The generator signs off clean across transistor widths (DRC + LVS)",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)),
          arguments: [0.42, 0.65, 1.00, 1.50])
    func widthParameterizedSignsOff(width: Double) async throws {
        // The parametric floorplan must hold across the supported width range — this is
        // the link from electrical sizing (W) to a signed-off physical cell.
        let service = try #require(Sky130CellSignoffService.locate())
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-w-\(UUID().uuidString)")
        let output = try await service.synthesizeInverter(name: "sky130_inverter", width: width, into: dir)
        let rules = output.review.reports.flatMap { $0.diagnostics }.map { $0.ruleID ?? "?" }
        #expect(output.passed, "width \(width) not clean: \(rules)")
    }

    /// A CMOS inverter spec for the electrical sizing loop (20 fF load), `width` in metres.
    private func inverterSpec(width: Double) -> DesignFlowDesignSpec {
        DesignFlowDesignSpec(
            name: "inverter", title: "CMOS inverter delay loop",
            components: [
                DesignFlowDesignSpec.Component(name: "VDD", deviceKindID: "vsource", parameters: ["dc": 1.8]),
                DesignFlowDesignSpec.Component(name: "VIN", deviceKindID: "vsource", parameters: [
                    "pulse_v1": 0, "pulse_v2": 1.8, "pulse_td": 2e-9,
                    "pulse_tr": 0.5e-9, "pulse_tf": 0.5e-9, "pulse_pw": 20e-9, "pulse_per": 40e-9,
                ]),
                DesignFlowDesignSpec.Component(name: "MN", deviceKindID: "nmos_l1",
                    parameters: ["w": width, "l": 0.15e-6], modelPresetID: "generic_nmos"),
                DesignFlowDesignSpec.Component(name: "MP", deviceKindID: "pmos_l1",
                    parameters: ["w": width, "l": 0.15e-6], modelPresetID: "generic_pmos"),
                DesignFlowDesignSpec.Component(name: "CL", deviceKindID: "capacitor", parameters: ["c": 20e-15]),
                DesignFlowDesignSpec.Component(name: "GND1", deviceKindID: "ground"),
            ],
            nets: [
                DesignFlowDesignSpec.Net(name: "vdd", terminals: [
                    DesignFlowDesignSpec.Terminal(component: "VDD", port: "pos"),
                    DesignFlowDesignSpec.Terminal(component: "MP", port: "source"),
                    DesignFlowDesignSpec.Terminal(component: "MP", port: "bulk"),
                ]),
                DesignFlowDesignSpec.Net(name: "in", terminals: [
                    DesignFlowDesignSpec.Terminal(component: "VIN", port: "pos"),
                    DesignFlowDesignSpec.Terminal(component: "MN", port: "gate"),
                    DesignFlowDesignSpec.Terminal(component: "MP", port: "gate"),
                ]),
                DesignFlowDesignSpec.Net(name: "out", terminals: [
                    DesignFlowDesignSpec.Terminal(component: "MN", port: "drain"),
                    DesignFlowDesignSpec.Terminal(component: "MP", port: "drain"),
                    DesignFlowDesignSpec.Terminal(component: "CL", port: "pos"),
                ]),
                DesignFlowDesignSpec.Net(name: "0", terminals: [
                    DesignFlowDesignSpec.Terminal(component: "VDD", port: "neg"),
                    DesignFlowDesignSpec.Terminal(component: "VIN", port: "neg"),
                    DesignFlowDesignSpec.Terminal(component: "MN", port: "source"),
                    DesignFlowDesignSpec.Terminal(component: "MN", port: "bulk"),
                    DesignFlowDesignSpec.Terminal(component: "CL", port: "neg"),
                    DesignFlowDesignSpec.Terminal(component: "GND1", port: "gnd"),
                ]),
            ],
            analyses: [DesignFlowDesignSpec.Analysis(kind: .tran, stopTime: 30e-9, stepTime: 0.02e-9)],
            pexIR: nil
        )
    }

    @Test("Spec -> GDS: size the inverter electrically, then synthesize + sign off the sized cell",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func specDrivenCellFlowEmitsSignedOffGDS() async throws {
        // The whole chain: a narrow inverter misses a delay target, the loop widens the
        // FETs (failure-driven) to meet it, and the SIZED width is realized as a Sky130
        // cell that passes real DRC + LVS and is emitted as GDS.
        let flow = try #require(SpecDrivenCellFlow.locate())
        let spec = PerformanceSpec(metric: .propagationDelaySeconds, comparison: .atMost, target: 0.2e-9)
        let tunable = SpecDrivenDesignLoop.Tunable(
            componentNames: ["MN", "MP"], parameter: "w", effect: .largerReducesMetric,
            stepFactor: 1.7, minValue: 0.1e-6, maxValue: 1.5e-6
        )
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-spec2gds-\(UUID().uuidString)")

        let output = try await flow.run(
            initial: inverterSpec(width: 0.3e-6), tunable: tunable, spec: spec,
            maxIterations: 8, into: dir
        ) { waveform in
            try SpecDrivenDesignLoop.propagationDelay(in: waveform, from: "in", to: "out", thresholdV: 0.9)
        }

        // Electrical: it converged by widening (failure-driven), and the layout width
        // tracks the sized device on the manufacturing grid.
        #expect(output.converged)
        #expect(output.layoutWidthMicrons >= output.sizedWidthMicrons - 1e-9,
                "the realized cell must be at least as wide as the sized device")
        // Physical: the sized cell is DRC + LVS clean and a GDS was emitted.
        let rules = output.physical.review.reports.flatMap { $0.diagnostics }.map { $0.ruleID ?? "?" }
        #expect(output.passed, "sized cell (W=\(output.layoutWidthMicrons)µm) not clean: \(rules)")
        #expect(FileManager.default.fileExists(atPath: output.physical.gdsURL.path(percentEncoded: false)),
                "the GDS artifact must be emitted for the sized cell")
    }

    @Test("Physical loop: two too-close met1 wires are spaced apart to DRC-clean, driven by the named violation",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func physicalLoopSpacesTooCloseWires() async throws {
        // The physical analog of the spec loop: start below met1 minimum spacing, let
        // DRC name the violation (met1.2), route the report through the Explain stage,
        // and let the loop grow the gap (Decide -> Edit) until it is clean —
        // failure-driven, not a fixed script.
        let drc = try #require(Sky130LayoutDRC.locate())
        let loop = PhysicalDesignLoop(drc: drc)
        let cell = "gen_met1_pair"
        let tunable = PhysicalDesignLoop.Tunable(
            parameter: "met1_gap", fixesReason: "min_spacing_violation", onLayer: "met1",
            stepFactor: 1.3, minValue: 0.10, maxValue: 0.30
        )
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-physloop-\(UUID().uuidString)")

        let outcome = try await loop.run(
            initial: 0.10, tunable: tunable, cellName: cell, into: dir, maxIterations: 6
        ) { gap in
            // Two legal-width (0.20) met1 wires `gap` µm apart on the y axis.
            let lower = LayoutShape(layer: Sky130LayoutTech.layer("met1"),
                geometry: .rect(LayoutRect(origin: LayoutPoint(x: 0, y: 0), size: LayoutSize(width: 2.0, height: 0.20))))
            let upper = LayoutShape(layer: Sky130LayoutTech.layer("met1"),
                geometry: .rect(LayoutRect(origin: LayoutPoint(x: 0, y: 0.20 + gap), size: LayoutSize(width: 2.0, height: 0.20))))
            let cellIR = LayoutCell(name: cell, shapes: [lower, upper])
            return LayoutDocument(name: cell, cells: [cellIR], topCellID: cellIR.id)
        }

        #expect(outcome.converged,
                "iters: \(outcome.iterations.map { ($0.parameterValue, $0.passed, $0.blockingRules) })")
        let first = try #require(outcome.iterations.first)
        #expect(first.passed == false, "a 0.10µm gap must violate met1 min spacing (0.14)")
        #expect(first.blockingRules.contains { $0.lowercased().contains("met1") },
                "the violation must be named met1.x: \(first.blockingRules)")
        #expect(outcome.finalParameter >= 0.14 - 1e-9, "must space to >= met1 minimum spacing")
        #expect(outcome.finalReport.passed, "the final geometry must be DRC-clean")
    }

    /// A DRC stub that is never expected to run — for the budget guard, which throws
    /// before any check.
    private struct UnusedDRC: LayoutDRCChecking {
        func check(_ document: LayoutDocument, cell: String, in directory: URL) async throws -> ExternalSignoffToolReport {
            throw CancellationError()
        }
    }

    @Test("Physical loop rejects a non-positive budget (no silent pass)")
    func physicalLoopRejectsNonPositiveBudget() async {
        let loop = PhysicalDesignLoop(drc: UnusedDRC())
        let tunable = PhysicalDesignLoop.Tunable(
            parameter: "met1_gap", fixesReason: "min_spacing_violation", onLayer: "met1",
            stepFactor: 1.3, minValue: 0.10, maxValue: 0.30
        )
        await #expect(throws: PhysicalDesignLoop.LoopError.nonPositiveBudget) {
            _ = try await loop.run(
                initial: 0.10, tunable: tunable, cellName: "x",
                into: FileManager.default.temporaryDirectory, maxIterations: 0
            ) { _ in LayoutDocument(name: "x", cells: [LayoutCell(name: "x", shapes: [])], topCellID: LayoutCell(name: "x", shapes: []).id) }
        }
    }

    @Test("Physical loop refuses to 'fix' a violation its tunable does not address",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func physicalLoopRefusesUnaddressableViolation() async throws {
        // Same too-close-wires geometry (a SPACING violation), but the tunable claims to
        // fix a WIDTH violation — the loop must throw, not blindly grow or silently pass.
        let drc = try #require(Sky130LayoutDRC.locate())
        let loop = PhysicalDesignLoop(drc: drc)
        let cell = "gen_met1_pair_unfixable"
        let tunable = PhysicalDesignLoop.Tunable(
            parameter: "met1_width", fixesReason: "min_width_violation", onLayer: "met1",
            stepFactor: 1.3, minValue: 0.10, maxValue: 0.30
        )
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-physloop-unfix-\(UUID().uuidString)")

        await #expect(throws: PhysicalDesignLoop.LoopError.self) {
            _ = try await loop.run(
                initial: 0.10, tunable: tunable, cellName: cell, into: dir, maxIterations: 4
            ) { gap in
                let lower = LayoutShape(layer: Sky130LayoutTech.layer("met1"),
                    geometry: .rect(LayoutRect(origin: LayoutPoint(x: 0, y: 0), size: LayoutSize(width: 2.0, height: 0.20))))
                let upper = LayoutShape(layer: Sky130LayoutTech.layer("met1"),
                    geometry: .rect(LayoutRect(origin: LayoutPoint(x: 0, y: 0.20 + gap), size: LayoutSize(width: 2.0, height: 0.20))))
                let cellIR = LayoutCell(name: cell, shapes: [lower, upper])
                return LayoutDocument(name: cell, cells: [cellIR], topCellID: cellIR.id)
            }
        }
    }

    @Test("The Sky130InverterGenerator output passes real DRC + Netgen LVS end-to-end",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(5)))
    func generatorOutputSignsOff() async throws {
        // Drive the whole flow from the production generator (not test-embedded
        // geometry): generate -> GDS -> real DRC + LVS.
        let generator = Sky130InverterGenerator()
        let cell = "sky130_inverter"
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-gen-cell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let gds = dir.appending(path: "\(cell).gds")
        try MaskDataFormatConverter(tech: Sky130LayoutTech.tech())
            .exportDocument(generator.generate(name: cell), to: gds, format: .gds)
        let schematicURL = dir.appending(path: "\(cell).spice")
        try generator.schematic(name: cell).write(to: schematicURL, atomically: true, encoding: .utf8)

        let signoff = try #require(LiveSignoffService.locate())
        let review = try await signoff.run(
            layoutGDS: gds, topCell: cell, schematicNetlist: schematicURL, artifactDirectory: dir
        )
        let drc = try #require(review.reports.first { $0.kind == .drc })
        let lvs = try #require(review.reports.first { $0.kind == .lvs })
        #expect(drc.passed, "DRC: \(drc.diagnostics.map { $0.ruleID ?? "?" })")
        #expect(lvs.passed, "LVS: \(lvs.diagnostics.map { $0.ruleID ?? "?" })")
        #expect(review.passed, "the generated cell must be DRC + LVS clean")
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
        .subckt gen_inv_tapped A Y VPWR VGND
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
