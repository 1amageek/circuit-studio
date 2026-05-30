import Foundation
import Testing
@testable import CircuitStudioApp

/// Tests for deriving a cell's reference schematic from the PDK (so design-by-name
/// → evaluation needs no hand-supplied schematic). The slicing logic is covered
/// purely (CI-safe); the end-to-end derive+signoff is gated on the toolchain.
@Suite("PDK schematic derivation")
struct PDKSchematicProviderTests {

    private let deck = """
    * header
    .subckt foo__a A Y
    X0 A Y nfet
    .ends
    .subckt foo__b B Z VPWR
    X0 B Z nfet
    X1 B Z pfet
    .ends
    """

    @Test("Slices the requested subcircuit exactly")
    func slicesRequested() throws {
        let b = try #require(PDKSchematicProvider.sliceSubcircuit(named: "foo__b", from: deck))
        #expect(b.contains(".subckt foo__b B Z VPWR"))
        #expect(b.contains("X1 B Z pfet"))
        #expect(b.hasSuffix(".ends\n"))
        // Must not bleed the other cell's devices in.
        #expect(!b.contains("foo__a"))
    }

    @Test("Returns nil for an absent subcircuit")
    func absentReturnsNil() {
        #expect(PDKSchematicProvider.sliceSubcircuit(named: "foo__missing", from: deck) == nil)
    }

    @Test("Matches the cell-name token exactly (no prefix collision)")
    func exactTokenMatch() {
        // "foo__a2" must not match the ".subckt foo__a" block.
        #expect(PDKSchematicProvider.sliceSubcircuit(named: "foo__a2", from: deck) == nil)
    }

    @Test(
        "Derives a real PDK cell schematic that signs off against its materialized layout",
        .enabled(if: PDKSchematicProvider.locate() != nil && PDKCellLayoutService.locate() != nil),
        .timeLimit(.minutes(3))
    )
    func deriveAndSignoff() async throws {
        let provider = try #require(PDKSchematicProvider.locate())
        let layout = try #require(PDKCellLayoutService.locate())
        let work = FileManager.default.temporaryDirectory.appending(path: "PDKSchem-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let cell = "sky130_fd_sc_hd__inv_1"

        let schematic = try provider.schematic(forCell: cell, into: work.appending(path: "schem"))
        let contents = try String(contentsOf: schematic, encoding: .utf8)
        #expect(contents.contains(".subckt \(cell)"))

        let gds = try layout.materialize(cell: cell, into: work.appending(path: "layout"))
        let review = try await DesignFlowService().runLiveSignoff(
            layoutGDS: gds, topCell: cell, schematicNetlist: schematic,
            artifactDirectory: work.appending(path: "signoff")
        )
        #expect(review.passed, "PDK-derived schematic must LVS-match the materialized layout")
    }

    @Test("Rejects a cell name without a library prefix")
    func rejectsBadCellName() throws {
        let provider = PDKSchematicProvider(pdkRoot: "/nonexistent")
        #expect(throws: PDKSchematicProvider.SchematicError.self) {
            _ = try provider.schematic(forCell: "noseparator", into: FileManager.default.temporaryDirectory)
        }
    }
}
