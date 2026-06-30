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
        defer { removeCoreTestTemporaryDirectory(work) }
        let cell = "sky130_fd_sc_hd__inv_1"

        let schematic = try provider.schematic(forCell: cell, into: work.appending(path: "schem"))
        let contents = try String(contentsOf: schematic, encoding: .utf8)
        #expect(contents.contains(".subckt \(cell)"))

        let gds = try await layout.materialize(cell: cell, into: work.appending(path: "layout"))
        let review = try await DesignFlowService().runLiveSignoff(
            layoutGDS: gds, topCell: cell, schematicNetlist: schematic,
            artifactDirectory: work.appending(path: "signoff")
        )
        #expect(review.passed, "PDK-derived schematic must LVS-match the materialized layout")
    }

    @Test("Rejects a cell name without a library prefix")
    func rejectsBadCellName() throws {
        let fixture = try makeProfileBackedProvider()
        defer { removeCoreTestTemporaryDirectory(fixture.root) }
        #expect(throws: PDKSchematicProvider.SchematicError.self) {
            _ = try fixture.provider.schematic(forCell: "noseparator", into: FileManager.default.temporaryDirectory)
        }
    }

    @Test("Resolves schematic decks through the PDK profile template")
    func resolvesProfileDeclaredDeckTemplate() throws {
        let fixture = try makeProfileBackedProvider()
        defer { removeCoreTestTemporaryDirectory(fixture.root) }
        let work = FileManager.default.temporaryDirectory
            .appending(path: "PDKSchematicProviderOutput-\(UUID().uuidString)")
        defer { removeCoreTestTemporaryDirectory(work) }

        #expect(fixture.provider.hasLibraryDeck(library: "generic_std"))
        let schematic = try fixture.provider.schematic(forCell: "generic_std__inv_1", into: work)
        let contents = try String(contentsOf: schematic, encoding: .utf8)
        #expect(contents.contains(".subckt generic_std__inv_1 A Y"))
    }

    @Test("Rejects cells whose library is absent from the PDK profile")
    func rejectsUnknownLibraryInsteadOfFallingBack() throws {
        let fixture = try makeProfileBackedProvider()
        defer { removeCoreTestTemporaryDirectory(fixture.root) }

        #expect(throws: PDKSchematicProvider.SchematicError.standardCellLibraryMissing) {
            _ = try fixture.provider.schematic(
                forCell: "missing_std__inv_1",
                into: FileManager.default.temporaryDirectory.appending(path: "PDKSchematicProviderMissing-\(UUID().uuidString)")
            )
        }
    }

    private struct ProfileBackedProviderFixture {
        let provider: PDKSchematicProvider
        let root: URL
    }

    private func makeProfileBackedProvider() throws -> ProfileBackedProviderFixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "PDKSchematicProviderProfile-\(UUID().uuidString)")
        let pdkRoot = root.appending(path: "genericPDK")
        let magic = pdkRoot.appending(path: "decks/magic.rc")
        let spice = pdkRoot.appending(path: "libs/generic_std/generic_std.spice")
        try FileManager.default.createDirectory(
            at: magic.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: spice.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("magic\n".utf8).write(to: magic)
        try Data("""
        .subckt generic_std__inv_1 A Y
        X0 A Y nfet
        .ends
        """.utf8).write(to: spice)

        let profile = """
        {
          "schemaVersion": 1,
          "profileID": "generic.test.signoff",
          "pdkID": "generic",
          "rootDirectoryName": "genericPDK",
          "candidateRootPaths": ["\(root.path(percentEncoded: false))"],
          "requirements": [
            {
              "requirementID": "magic",
              "relativePath": "decks/magic.rc"
            },
            {
              "requirementID": "standard-cell-spice-library",
              "relativePath": "libs/{library}/{library}.spice"
            }
          ],
          "standardCellLibraries": [
            {
              "libraryID": "generic_std",
              "spiceDeckRequirementID": "standard-cell-spice-library"
            }
          ],
          "deckRequirements": [],
          "semanticSources": [],
          "semanticChecks": []
        }
        """
        let profileURL = root.appending(path: "generic-signoff-pdk-profile.json")
        try Data(profile.utf8).write(to: profileURL)
        let context = try SignoffPDKContext.resolve(
            requirementID: "magic",
            environment: [
                SignoffPDKContext.profilePathEnvironmentKey: profileURL.path(percentEncoded: false)
            ]
        )
        return ProfileBackedProviderFixture(
            provider: PDKSchematicProvider(context: context),
            root: root
        )
    }
}
