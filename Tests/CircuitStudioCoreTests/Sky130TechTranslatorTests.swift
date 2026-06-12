import Foundation
import Testing
import LayoutCore
import LayoutTech
import LayoutAutoGen
import LayoutIO
@testable import CircuitStudioApp

/// #38 — generic-tech artifacts must be verifiable on the REAL Sky130 deck.
/// The translator's own contract (structural completeness) is unit-tested
/// here; correctness of the translated geometry is judged by Magic DRC +
/// Netgen LVS in the gated round-trip test at the bottom.
@Suite("Sky130 tech translator")
struct Sky130TechTranslatorTests {

    private func deviceDocument(kind: String, name: String) throws -> LayoutDocument {
        let tech = LayoutTechDatabase.sampleProcess()
        let cell = try MOSFETCellGenerator().generateCell(
            deviceKindID: kind,
            instanceName: name,
            parameters: ["w": 2.0, "l": 0.18],
            tech: tech
        )
        return LayoutDocument(name: name, cells: [cell], topCellID: cell.id)
    }

    private func shapes(on layer: String, in cell: LayoutCell) -> [LayoutShape] {
        cell.shapes.filter { $0.layer.name == layer }
    }

    @Test("Every translated element is on a layer the Sky130 tech defines")
    func translationIsComplete() throws {
        let document = try deviceDocument(kind: "nmos", name: "M1")
        let output = try Sky130TechTranslator().translate(document)

        let definedNames = Set(output.tech.layers.map(\.id.name))
        for cell in output.document.cells {
            for shape in cell.shapes {
                #expect(definedNames.contains(shape.layer.name), "shape on \(shape.layer.name)")
            }
            for label in cell.labels {
                #expect(definedNames.contains(label.layer.name), "label on \(label.layer.name)")
            }
            for pin in cell.pins {
                #expect(definedNames.contains(pin.layer.name), "pin on \(pin.layer.name)")
            }
        }
    }

    @Test("Each contact cut becomes a centered licon1/mcon pair under a covering li1")
    func contactsRestack() throws {
        let document = try deviceDocument(kind: "nmos", name: "M1")
        let original = document.cells[0]
        let contacts = shapes(on: "CONTACT", in: original)
        #expect(!contacts.isEmpty)

        let output = try Sky130TechTranslator().translate(document)
        let cell = output.document.cells[0]
        let licons = shapes(on: "licon1", in: cell)
        let lis = shapes(on: "li1", in: cell)
        let mcons = shapes(on: "mcon", in: cell)
        #expect(licons.count == contacts.count)
        #expect(mcons.count == contacts.count)
        // li1 merges per contact column, so there are fewer pads than cuts
        // but at least one per column.
        #expect(!lis.isEmpty)
        #expect(lis.count < contacts.count)

        let liRects = lis.compactMap { li -> LayoutRect? in
            guard case .rect(let rect) = li.geometry else { return nil }
            return rect
        }
        #expect(liRects.count == lis.count)

        for contact in contacts {
            guard case .rect(let cut) = contact.geometry else {
                Issue.record("generator emitted a non-rect contact")
                return
            }
            let stacked = licons.contains { licon in
                guard case .rect(let rect) = licon.geometry else { return false }
                return abs(rect.center.x - cut.center.x) < 1e-9
                    && abs(rect.center.y - cut.center.y) < 1e-9
                    && abs(rect.size.width - 0.17) < 1e-9
                    && abs(rect.size.height - 0.17) < 1e-9
            }
            #expect(stacked, "no centered licon1 for contact at \(cut.center)")
        }

        // Every licon must sit under a li1 pad with the 0.08 enclosure
        // (Sky130 li.5), and pads must keep the 0.17 li spacing (li.3) —
        // the rule the per-cut pads of a naive translation would break.
        for licon in licons {
            guard case .rect(let rect) = licon.geometry else { continue }
            let covered = liRects.contains { li in
                rect.minX - li.minX > 0.0799 && li.maxX - rect.maxX > 0.0799
                    && rect.minY - li.minY > 0.0799 && li.maxY - rect.maxY > 0.0799
            }
            #expect(covered, "licon at \(rect.center) lacks a 0.08-enclosing li1 pad")
        }
        for i in liRects.indices {
            for j in liRects.indices where j > i {
                let a = liRects[i], b = liRects[j]
                let dx = max(a.minX - b.maxX, b.minX - a.maxX)
                let dy = max(a.minY - b.maxY, b.minY - a.maxY)
                #expect(max(dx, dy) > 0.17 - 1e-9,
                        "li1 pads at \(a.center) and \(b.center) are closer than 0.17")
            }
        }
    }

    @Test("npc and a poly pad appear over gate contacts only")
    func gateContactsGetNPC() throws {
        let document = try deviceDocument(kind: "nmos", name: "M1")
        let output = try Sky130TechTranslator().translate(document)
        let cell = output.document.cells[0]

        // The single-finger MOSFET has exactly one gate contact.
        let npcs = shapes(on: "npc", in: cell)
        #expect(npcs.count == 1)
        guard case .rect(let npc) = npcs[0].geometry else {
            Issue.record("npc is not a rect")
            return
        }
        // npc must enclose its licon by the Sky130 npc rule margin.
        let enclosing = shapes(on: "licon1", in: cell).contains { licon in
            guard case .rect(let rect) = licon.geometry else { return false }
            return rect.minX - npc.minX > 0.099 && npc.maxX - rect.maxX > 0.099
                && rect.minY - npc.minY > 0.099 && npc.maxY - rect.maxY > 0.099
        }
        #expect(enclosing)
    }

    @Test("NMOS active classifies as diff, its substrate tie as tap with grown enclosure")
    func nmosActiveClassification() throws {
        let document = try deviceDocument(kind: "nmos", name: "M1")
        let output = try Sky130TechTranslator().translate(document)
        let cell = output.document.cells[0]

        let diffs = shapes(on: "diff", in: cell)
        let taps = shapes(on: "tap", in: cell)
        #expect(diffs.count == 1)
        #expect(taps.count == 1)
        #expect(shapes(on: "nwell", in: cell).isEmpty)
        #expect(shapes(on: "nsdm", in: cell).count == 1)
        #expect(shapes(on: "psdm", in: cell).count == 1)

        // The tap must enclose every licon it hosts by 0.12 horizontally
        // (Sky130 licon.7), and its implant must keep 0.125 around the
        // grown tap (psdm.2).
        guard case .rect(let tap) = taps[0].geometry else {
            Issue.record("tap is not a rect")
            return
        }
        let hostedLicons = shapes(on: "licon1", in: cell).compactMap { licon -> LayoutRect? in
            guard case .rect(let rect) = licon.geometry, tap.contains(rect.center) else { return nil }
            return rect
        }
        #expect(!hostedLicons.isEmpty)
        for licon in hostedLicons {
            #expect(licon.minX - tap.minX > 0.119)
            #expect(tap.maxX - licon.maxX > 0.119)
        }
        let psdm = shapes(on: "psdm", in: cell)[0]
        guard case .rect(let implant) = psdm.geometry else {
            Issue.record("psdm is not a rect")
            return
        }
        #expect(tap.minX - implant.minX > 0.1249)
        #expect(implant.maxX - tap.maxX > 0.1249)
    }

    @Test("PMOS classification: diffusion in the well is diff, the well tie is tap")
    func pmosActiveClassification() throws {
        let document = try deviceDocument(kind: "pmos", name: "M2")
        let output = try Sky130TechTranslator().translate(document)
        let cell = output.document.cells[0]

        #expect(shapes(on: "nwell", in: cell).count == 1)
        #expect(shapes(on: "diff", in: cell).count == 1)
        #expect(shapes(on: "tap", in: cell).count == 1)
        // PMOS: device diffusion is p+ (psdm), the well tie is n+ (nsdm).
        guard case .rect(let diff) = shapes(on: "diff", in: cell)[0].geometry,
              case .rect(let psdm) = shapes(on: "psdm", in: cell)[0].geometry else {
            Issue.record("diff/psdm not rects")
            return
        }
        #expect(psdm.contains(diff.center))
    }

    @Test("Routing layers, vias, labels and pins remap; nets pass through")
    func routingAndAnnotationsRemap() throws {
        let net = LayoutNet(name: "mid")
        let cell = LayoutCell(
            name: "TOP",
            shapes: [
                LayoutShape(layer: LayoutLayerID(name: "M1", purpose: "drawing"), netID: net.id,
                            geometry: .rect(LayoutRect(origin: .zero, size: LayoutSize(width: 1, height: 0.23)))),
                LayoutShape(layer: LayoutLayerID(name: "M2", purpose: "drawing"), netID: net.id,
                            geometry: .rect(LayoutRect(origin: .zero, size: LayoutSize(width: 0.28, height: 1)))),
            ],
            vias: [LayoutVia(viaDefinitionID: "VIA1", position: LayoutPoint(x: 0.14, y: 0.14), netID: net.id)],
            labels: [LayoutLabel(text: "mid", position: .zero, layer: LayoutLayerID(name: "M1", purpose: "drawing"))],
            pins: [LayoutPin(name: "mid", position: .zero, size: LayoutSize(width: 0.23, height: 0.23),
                             layer: LayoutLayerID(name: "M1", purpose: "drawing"))],
            nets: [net]
        )
        let document = LayoutDocument(name: "TOP", cells: [cell], topCellID: cell.id)

        let output = try Sky130TechTranslator().translate(document)
        let translated = output.document.cells[0]
        #expect(Set(translated.shapes.map(\.layer.name)) == ["met1", "met2"])
        #expect(translated.vias.map(\.viaDefinitionID) == ["via"])
        #expect(translated.labels.map(\.layer.name) == ["met1"])
        #expect(translated.pins.map(\.layer.name) == ["met1"])
        #expect(translated.nets == [net])
        #expect(translated.shapes.allSatisfy { $0.netID == net.id })
    }

    @Test("Unsupported layers fail loud, never silently drop")
    func unsupportedLayerThrows() throws {
        let cell = LayoutCell(name: "R", shapes: [
            LayoutShape(layer: LayoutLayerID(name: "RESI", purpose: "drawing"),
                        geometry: .rect(LayoutRect(origin: .zero, size: LayoutSize(width: 1, height: 1)))),
        ])
        let document = LayoutDocument(name: "R", cells: [cell], topCellID: cell.id)
        #expect(throws: Sky130TechTranslator.TranslationError.unsupportedLayer(layer: "RESI", cell: "R")) {
            _ = try Sky130TechTranslator().translate(document)
        }
    }

    @Test("An active without an implant cover fails loud")
    func unclassifiableActiveThrows() throws {
        let cell = LayoutCell(name: "A", shapes: [
            LayoutShape(layer: LayoutLayerID(name: "ACTIVE", purpose: "drawing"),
                        geometry: .rect(LayoutRect(origin: .zero, size: LayoutSize(width: 1, height: 1)))),
        ])
        let document = LayoutDocument(name: "A", cells: [cell], topCellID: cell.id)
        #expect(throws: Sky130TechTranslator.TranslationError.unclassifiableActive(cell: "A")) {
            _ = try Sky130TechTranslator().translate(document)
        }
    }

    @Test("A contact on neither poly nor active fails loud")
    func floatingContactThrows() throws {
        let cell = LayoutCell(name: "C", shapes: [
            LayoutShape(layer: LayoutLayerID(name: "CONTACT", purpose: "cut"),
                        geometry: .rect(LayoutRect(origin: .zero, size: LayoutSize(width: 0.22, height: 0.22)))),
        ])
        let document = LayoutDocument(name: "C", cells: [cell], topCellID: cell.id)
        #expect(throws: Sky130TechTranslator.TranslationError.contactOutsideDeviceGeometry(cell: "C")) {
            _ = try Sky130TechTranslator().translate(document)
        }
    }

    @Test("An unknown via definition fails loud")
    func unknownViaDefinitionThrows() throws {
        let cell = LayoutCell(name: "V", vias: [
            LayoutVia(viaDefinitionID: "CONT_ACTIVE", position: .zero),
        ])
        let document = LayoutDocument(name: "V", cells: [cell], topCellID: cell.id)
        #expect(throws: Sky130TechTranslator.TranslationError.unsupportedViaDefinition(id: "CONT_ACTIVE", cell: "V")) {
            _ = try Sky130TechTranslator().translate(document)
        }
    }
}

/// The honest gate for #38: the agent closes a generic-tech intent, the
/// artifact round-trips through GDS, the translator restacks it onto the
/// Sky130 layers, and the REAL Magic DRC + Netgen LVS deck judges it.
@MainActor
@Suite("Sky130 tech translation round trip", .timeLimit(.minutes(10)))
struct Sky130TechTranslationRoundTripTests {

    private static let chainIntent = """
    .subckt chain a mid out gnd
    M1 mid a gnd gnd nmos W=2u L=0.18u
    M2 out mid gnd gnd nmos W=2u L=0.18u
    .ends
    """

    private static let chainReferenceSPICE = """
    * translated chain reference
    .subckt CHAIN a mid out gnd
    XM1 mid a gnd gnd sky130_fd_pr__nfet_01v8 w=2 l=0.18
    XM2 out mid gnd gnd sky130_fd_pr__nfet_01v8 w=2 l=0.18
    .ends
    """

    @Test("Agent-closed generic intent passes the real Sky130 Magic/Netgen deck after translation",
          .enabled(if: Sky130GeneratedDRCTests.available))
    func agentArtifactSignsOffOnSky130() async throws {
        let genericTech = LayoutTechDatabase.sampleProcess()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sky130-translate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                Issue.record("Failed to remove temporary directory: \(error)")
            }
        }

        // 1. The agent closes the intent on the generic tech (DRC, LVS,
        //    replay-determinism gated inside close()).
        let agent = GoalDrivenLayoutAgent(designName: "CHAIN", tech: genericTech)
        let evidence = try agent.close(intent: Self.chainIntent, exportDirectory: directory)
        #expect(evidence.closed)

        // 2. Translation consumes the ARTIFACT, not editor state: reimport
        //    the generic GDS, restack onto Sky130 layers, re-export.
        let reimported = try GDSFormatConverter(tech: genericTech)
            .importDocument(from: evidence.gdsURL, format: .gds)
        let output = try Sky130TechTranslator().translate(reimported)
        let sky130GDS = directory.appendingPathComponent("CHAIN-sky130.gds")
        try GDSFormatConverter(tech: output.tech)
            .exportDocument(output.document, to: sky130GDS, format: .gds)

        // 3. The real deck judges it.
        let spiceURL = directory.appendingPathComponent("CHAIN.spice")
        try Self.chainReferenceSPICE.write(to: spiceURL, atomically: true, encoding: .utf8)
        let signoff = try #require(LiveSignoffService.locate())
        let review = try await signoff.run(
            layoutGDS: sky130GDS,
            topCell: "CHAIN",
            schematicNetlist: spiceURL,
            artifactDirectory: directory
        )
        let drc = try #require(review.reports.first { $0.kind == .drc })
        let lvs = try #require(review.reports.first { $0.kind == .lvs })
        #expect(drc.passed, "Sky130 DRC: \(drc.diagnostics.prefix(10).map { ($0.ruleID ?? "?", $0.message) })")
        #expect(lvs.passed, "Sky130 LVS: \(lvs.diagnostics.prefix(10).map { ($0.ruleID ?? "?", $0.message) })")
    }
}
