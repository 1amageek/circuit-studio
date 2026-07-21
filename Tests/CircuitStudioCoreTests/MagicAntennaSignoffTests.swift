import CircuitSignoff
import Foundation
import Testing
import LayoutCore
import LayoutTech
import LayoutIO
@testable import CircuitStudioApp

/// Proves the antenna axis is scored by a REAL tool: a layout built in the IR is
/// exported to Sky130 GDS and checked by Magic's `antennacheck` against the Sky130
/// techfile antenna ratios. A gate wired to a short metal stub is clean; the same
/// gate wired to a large metal plate (a long antenna collected before any diode)
/// is caught. Gated on the toolchain.
@Suite("Magic antenna signoff (gated)")
struct MagicAntennaSignoffTests {

    static let available = MagicAntennaSignoff.locate() != nil

    private func rect(_ layer: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> LayoutShape {
        LayoutShape(
            layer: Sky130LayoutTech.layer(layer),
            geometry: .rect(LayoutRect(origin: LayoutPoint(x: x, y: y), size: LayoutSize(width: w, height: h)))
        )
    }

    /// An NMOS whose GATE is lifted to met1 (poly -> licon1 -> li1 -> mcon -> met1),
    /// with a minimum-width met1 wire of length `metalLength` on that gate net. Sky130's
    /// met1 antenna rule is `sidewall` (perimeter-based), so a long thin run — not a
    /// fat plate — is the antenna: metal charge collected on the gate during fab with no
    /// diode to bleed it off. A short run is a normal in-cell connection.
    private func gateWithMetal(cell: String, metalLength: Double, diffusionTie: Bool = false) -> LayoutDocument {
        let thin = 0.14   // met1 minimum width; the long dimension drives the antenna perimeter
        var shapes: [LayoutShape] = [
            // --- the transistor: n+ active + poly gate + source/drain contacts ---
            rect("diff", 0.00, 0.00, 1.00, 0.42),
            rect("nsdm", -0.125, -0.125, 1.25, 0.67),
            rect("poly", 0.42, -0.13, 0.16, 1.30),       // gate, extended up to the contact pad
            rect("licon1", 0.10, 0.125, 0.17, 0.17),     // source contact
            rect("licon1", 0.73, 0.125, 0.17, 0.17),     // drain contact
            rect("li1", 0.02, 0.045, 0.33, 0.33),        // source li1
            rect("li1", 0.65, 0.045, 0.33, 0.33),        // drain li1
            // --- the gate's poly contact up to li1 (poly -> licon1 -> li1) ---
            rect("poly", 0.31, 0.74, 0.38, 0.38),        // poly pad over the gate
            rect("licon1", 0.41, 0.84, 0.17, 0.17),      // poly contact
            rect("npc", 0.31, 0.74, 0.38, 0.38),         // nitride-poly-cut enclosing licon by 0.10
            rect("li1", 0.33, 0.76, 0.34, 0.34),         // li1 over the poly contact
            // --- li1 -> mcon -> met1 (the gate net climbs to met1) ---
            rect("mcon", 0.41, 0.84, 0.17, 0.17),        // mcon on the gate li1
            rect("met1", 0.40, 0.83, metalLength, thin),  // the gate-connected met1 run (length = antenna)
        ]
        if diffusionTie {
            let tieX = 1.20
            shapes.append(contentsOf: [
                rect("diff", tieX - 0.205, 0.00, 0.41, 0.41),
                rect("nsdm", tieX - 0.33, -0.125, 0.66, 0.66),
                rect("licon1", tieX - 0.085, 0.125, 0.17, 0.17),
                rect("li1", tieX - 0.165, 0.045, 0.33, 0.33),
                rect("mcon", tieX - 0.085, 0.125, 0.17, 0.17),
                rect("met1", tieX - 0.165, 0.045, 0.33, 0.925),
            ])
        }
        let cellIR = LayoutCell(name: cell, shapes: shapes)
        return LayoutDocument(name: cell, cells: [cellIR], topCellID: cellIR.id)
    }

    private func runAntenna(cell: String, document: LayoutDocument) async throws -> ExternalSignoffToolReport {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-antenna-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gds = dir.appending(path: "\(cell).gds")
        try MaskDataFormatConverter(tech: try Sky130LayoutTech.tech()).exportDocument(document, to: gds, format: .gds)

        let antenna = try #require(MagicAntennaSignoff.locate())
        let result = try await ExternalSignoffCommandRunner(parser: MagicAntennaSignoff.reportParser).run(
            command: antenna.command(cell: cell, gds: gds, artifactDirectory: dir),
            artifactDirectory: dir
        )
        return result.report
    }

    @Test("A gate wired to a small metal stub passes real Magic antennacheck",
          .enabled(if: MagicAntennaSignoffTests.available), .timeLimit(.minutes(5)))
    func smallMetalClean() async throws {
        // A 1 µm met1 stub — a normal in-cell connection, well under the ratio.
        let report = try await runAntenna(
            cell: "ant_clean",
            document: gateWithMetal(cell: "ant_clean", metalLength: 1.0))
        #expect(report.passed,
                "expected clean; diagnostics: \(report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }

    @Test("A gate wired to a large metal plate is caught as an antenna violation",
          .enabled(if: MagicAntennaSignoffTests.available), .timeLimit(.minutes(5)))
    func largeMetalAntennaCaught() async throws {
        // A 200 µm met1 run on one minimum gate — its perimeter is far beyond the
        // Sky130 met1 sidewall antenna ratio with no diode to drain the collected charge.
        let report = try await runAntenna(
            cell: "ant_violation",
            document: gateWithMetal(cell: "ant_violation", metalLength: 200.0))
        #expect(!report.passed, "the antenna violation must be rejected")
        #expect(report.diagnostics.contains { ($0.ruleID ?? "").lowercased().contains("antenna") },
                "expected a named antenna rule; got \(report.diagnostics.map { $0.ruleID ?? "?" })")
    }

    @Test("A diffusion tie discharges the same long gate metal for real Magic antennacheck",
          .enabled(if: MagicAntennaSignoffTests.available), .timeLimit(.minutes(5)))
    func longMetalWithDiffusionTiePasses() async throws {
        let report = try await runAntenna(
            cell: "ant_diffusion_tie",
            document: gateWithMetal(cell: "ant_diffusion_tie", metalLength: 200.0, diffusionTie: true))
        #expect(report.passed,
                "expected clean with diffusion tie; diagnostics: \(report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")
    }
}
