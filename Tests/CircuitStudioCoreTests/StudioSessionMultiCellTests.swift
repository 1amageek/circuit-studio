import Foundation
import CoreGraphics
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore
@testable import SchematicEditor

// MARK: - Builders

/// Builds a chain of wires forming one net on its own horizontal row so
/// separate nets never touch.
private func net(_ row: Int, _ pins: [(UUID, String)], name: String? = nil) -> [Wire] {
    let y = CGFloat(row * 100)
    var wires: [Wire] = []
    for (j, pin) in pins.enumerated() {
        wires.append(Wire(
            startPoint: CGPoint(x: CGFloat(j) * 100, y: y),
            endPoint: CGPoint(x: CGFloat(j + 1) * 100, y: y),
            startPin: PinReference(componentID: pin.0, portID: pin.1),
            netName: j == 0 ? name : nil
        ))
    }
    return wires
}

/// A minimal cell body with a derivable interface: input `A` and output `Y`
/// wired across a resistor. Enough for the catalog to register it as a
/// placeable cell and for the netlist generator to emit a `.subckt`.
private func twoPortCellSchematic() -> SchematicDocument {
    let a = PlacedComponent(deviceKindID: "port_input", name: "A", position: .zero)
    let y = PlacedComponent(deviceKindID: "port_output", name: "Y", position: .zero)
    let r = PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero, parameters: ["r": 1000])
    var wires = net(0, [(a.id, "pin"), (r.id, "pos")])
    wires += net(1, [(y.id, "pin"), (r.id, "neg")])
    return SchematicDocument(components: [a, y, r], wires: wires)
}

/// A cell instance referencing `cellName` by name — the hierarchy edge.
private func instance(of cellName: String, named instanceName: String) -> PlacedComponent {
    PlacedComponent(
        deviceKindID: DeviceCatalog.cellKindID(for: cellName),
        name: instanceName,
        position: .zero,
        cellName: cellName
    )
}

private func makeTemporaryProject() async throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "studio-multicell-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try await ProjectService().createProject(at: root)
    return root
}

private func removeTemporaryProject(_ root: URL) {
    do {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    } catch {
        Issue.record("Failed to remove temporary studio session project at \(root.path): \(error)")
    }
}

// MARK: - Library shape

@Suite("Studio Session Multi-Cell")
@MainActor
struct StudioSessionMultiCellTests {

    @Test("A fresh session is a one-cell library whose only cell is the top")
    func freshSessionHasOneTopCell() {
        let project = StudioSession()
        #expect(project.cells.count == 1)
        #expect(project.activeCellName == StudioSession.defaultCellName)
        #expect(project.topCellName == StudioSession.defaultCellName)
        #expect(project.cell(named: StudioSession.defaultCellName) != nil)
    }

    @Test("Adding a cell appends it, activates it, and leaves the top cell alone")
    func addCellAppendsAndActivates() async throws {
        let project = StudioSession()
        try project.addCell(named: "INV")

        #expect(project.cells.map(\.name) == [StudioSession.defaultCellName, "INV"])
        #expect(project.activeCellName == "INV")
        #expect(project.topCellName == StudioSession.defaultCellName)
    }

    @Test("Adding trims surrounding whitespace from the cell name")
    func addCellTrimsWhitespace() async throws {
        let project = StudioSession()
        try project.addCell(named: "  Buffer  ")
        #expect(project.cell(named: "Buffer") != nil)
        #expect(project.activeCellName == "Buffer")
    }

    @Test("Activating switches the active cell and rejects an unknown name")
    func activateCellSwitchesAndGuards() async throws {
        let project = StudioSession()
        try project.addCell(named: "INV")
        try project.activateCell(named: StudioSession.defaultCellName)
        #expect(project.activeCellName == StudioSession.defaultCellName)

        #expect(throws: StudioSessionError.unknownCell("Ghost")) {
            try project.activateCell(named: "Ghost")
        }
    }

    @Test("Designating a top cell changes the root and rejects an unknown name")
    func setTopCellChangesRoot() async throws {
        let project = StudioSession()
        try project.addCell(named: "INV")
        try project.setTopCell(named: "INV")
        #expect(project.topCellName == "INV")

        #expect(throws: StudioSessionError.unknownCell("Ghost")) {
            try project.setTopCell(named: "Ghost")
        }
    }
}

// MARK: - New-cell validation

@Suite("Studio Session New-Cell Validation")
@MainActor
struct StudioSessionValidationTests {

    @Test("A name that is not a valid SPICE identifier is rejected and adds nothing")
    func invalidNameRejected() {
        let project = StudioSession()
        #expect(throws: StudioSessionError.invalidCellName("1bad")) {
            try project.addCell(named: "1bad")
        }
        #expect(project.cells.count == 1)
    }

    @Test("A duplicate name is rejected case-insensitively and adds nothing")
    func duplicateNameRejectedCaseInsensitively() async throws {
        let project = StudioSession()
        try project.addCell(named: "Amp")
        #expect(throws: StudioSessionError.duplicateCellName("amp")) {
            try project.addCell(named: "amp")
        }
        #expect(project.cells.count == 2)
    }
}

// MARK: - Removal guards (cell-in-use protection)

@Suite("Studio Session Cell Removal")
@MainActor
struct StudioSessionRemovalTests {

    @Test("The last remaining cell cannot be removed")
    func cannotRemoveLastCell() {
        let project = StudioSession()
        #expect(throws: StudioSessionError.cannotRemoveLastCell) {
            try project.removeCell(named: StudioSession.defaultCellName)
        }
    }

    @Test("The top cell cannot be removed until another cell is made top")
    func cannotRemoveTopCell() async throws {
        let project = StudioSession()
        try project.addCell(named: "INV")
        #expect(throws: StudioSessionError.cannotRemoveTopCell(StudioSession.defaultCellName)) {
            try project.removeCell(named: StudioSession.defaultCellName)
        }
    }

    @Test("A cell still instantiated by another cell cannot be removed")
    func cannotRemoveCellInUse() async throws {
        let project = StudioSession()                       // Top
        try project.addCell(named: "INV")                   // active INV
        project.schematicViewModel.document = twoPortCellSchematic()
        try project.activateCell(named: StudioSession.defaultCellName)
        project.schematicViewModel.document.components.append(instance(of: "INV", named: "X1"))

        #expect(throws: StudioSessionError.cellInUse(cell: "INV", referencedBy: [StudioSession.defaultCellName])) {
            try project.removeCell(named: "INV")
        }
        #expect(project.cells.count == 2)
    }

    @Test("Removing the active, unreferenced cell succeeds and falls back to the top cell")
    func removeUnusedCellFallsBackToTop() async throws {
        let project = StudioSession()                       // Top
        try project.addCell(named: "Scratch")               // active Scratch
        #expect(project.activeCellName == "Scratch")

        try project.removeCell(named: "Scratch")
        #expect(project.cells.count == 1)
        #expect(project.activeCellName == StudioSession.defaultCellName)
    }

    @Test("Removing a cell that does not exist throws")
    func removeUnknownCellThrows() async throws {
        let project = StudioSession()
        try project.addCell(named: "A")
        #expect(throws: StudioSessionError.unknownCell("Ghost")) {
            try project.removeCell(named: "Ghost")
        }
    }
}

// MARK: - Catalog synchronization

@Suite("Studio Session Catalog Sync")
@MainActor
struct StudioSessionCatalogTests {

    @Test("A sibling cell becomes placeable in another cell after its interface exists")
    func siblingBecomesPlaceable() async throws {
        let project = StudioSession()                       // Top
        try project.addCell(named: "INV")                   // active INV
        project.schematicViewModel.document = twoPortCellSchematic()
        try project.activateCell(named: StudioSession.defaultCellName)  // rebuild; Top active

        let invKind = DeviceCatalog.cellKindID(for: "INV")
        let placeable = project.schematicViewModel.catalog.device(for: invKind)
        #expect(placeable != nil)
        #expect(placeable?.cellName == "INV")
    }

    @Test("A cell never offers itself in its own palette")
    func cellCannotPlaceItself() async throws {
        let project = StudioSession()
        try project.addCell(named: "INV")
        project.schematicViewModel.document = twoPortCellSchematic()
        try project.activateCell(named: "INV")              // rebuild; INV active

        let invKind = DeviceCatalog.cellKindID(for: "INV")
        #expect(project.schematicViewModel.catalog.device(for: invKind) == nil)
    }

    @Test("A cell whose interface fails to derive surfaces as a catalog issue, not a crash")
    func brokenCellSurfacesAsIssue() async throws {
        let project = StudioSession()
        try project.addCell(named: "BROKEN")
        // An unconnected boundary port makes the interface invalid.
        let orphan = PlacedComponent(deviceKindID: "port_input", name: "A", position: .zero)
        project.schematicViewModel.document = SchematicDocument(components: [orphan], wires: [])
        try project.activateCell(named: StudioSession.defaultCellName)  // rebuild

        #expect(project.catalogIssues.contains { $0.cellName == "BROKEN" })
        #expect(project.schematicViewModel.catalog.device(for: DeviceCatalog.cellKindID(for: "BROKEN")) == nil)
    }

    @Test("Unsaved changes aggregate across every cell, not just the active one")
    func hasUnsavedChangesAggregatesAcrossCells() async throws {
        let project = StudioSession()
        try project.addCell(named: "INV")                   // active INV, both cells empty
        #expect(!project.hasUnsavedChanges)

        // Dirty the non-active top cell.
        let top = try #require(project.cell(named: StudioSession.defaultCellName))
        top.schematicViewModel.document.components.append(
            PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero)
        )
        #expect(project.hasUnsavedChanges)
    }
}

// MARK: - Persistence round-trip

/// Exercises the same disk contract the app's save/open path uses
/// (`App.saveProject` writes every cell plus a manifest; `App.loadCells`
/// reads them back and rebuilds the session through `replaceCells`).
@Suite("Studio Session Persistence Round-Trip")
@MainActor
struct StudioSessionPersistenceRoundTripTests {

    @Test("A multi-cell hierarchy survives save and reopen with its top/active designation")
    func multiCellProjectSurvivesSaveAndReopen() async throws {
        let root = try await makeTemporaryProject()
        defer { removeTemporaryProject(root) }
        let service = ProjectService()

        // Author a two-cell project where Top instantiates Leaf, and the
        // active cell differs from the top cell so the session manifest matters.
        let project = StudioSession()                       // Top
        try project.addCell(named: "Leaf")                  // active Leaf
        project.schematicViewModel.document = twoPortCellSchematic()
        try project.activateCell(named: StudioSession.defaultCellName)
        project.schematicViewModel.document.components.append(instance(of: "Leaf", named: "X1"))
        try project.setTopCell(named: StudioSession.defaultCellName)
        try project.activateCell(named: "Leaf")

        // Save: mirror App.saveProject's per-cell schematic + session manifest writes.
        for workspace in project.cells {
            try service.saveCellSchematic(
                workspace.schematicViewModel.document,
                cellName: workspace.name,
                forProjectAt: root
            )
        }
        try await service.saveStudioSessionManifest(
            StudioSessionManifest(topCell: project.topCellName, activeCell: project.activeCellName),
            forProjectAt: root
        )

        // Reopen: mirror App.loadCells — list, load each, read session manifest,
        // then rebuild through replaceCells.
        let cellNames = try service.listCellNames(forProjectAt: root)
        var loaded: [(name: String, schematic: SchematicDocument)] = []
        for name in cellNames {
            loaded.append((name: name, schematic: try service.loadCellSchematic(cellName: name, forProjectAt: root)))
        }
        let manifest = try #require(try service.loadStudioSessionManifestIfPresent(forProjectAt: root))

        let reopened = StudioSession()
        try reopened.replaceCells(loaded, topCell: manifest.topCell, activeCell: manifest.activeCell)

        // The library, its hierarchy, and the top/active pointers all survive.
        #expect(reopened.cells.map(\.name).sorted() == ["Leaf", "Top"])
        #expect(reopened.topCellName == "Top")
        #expect(reopened.activeCellName == "Leaf")

        let leaf = try #require(reopened.cell(named: "Leaf"))
        #expect(leaf.schematicViewModel.document.components.contains { $0.name == "R1" })
        let top = try #require(reopened.cell(named: "Top"))
        #expect(top.schematicViewModel.document.components.contains { $0.cellName == "Leaf" })

        // A freshly reopened project reads clean.
        #expect(!reopened.hasUnsavedChanges)
    }

    @Test("A project with no cells on disk reopens as a single empty top cell")
    func emptyProjectReopensWithDefaultCell() async throws {
        let root = try await makeTemporaryProject()
        defer { removeTemporaryProject(root) }
        let service = ProjectService()

        // No cells were written. App.loadCells resets to a single default cell.
        let cellNames = try service.listCellNames(forProjectAt: root)
        #expect(cellNames.isEmpty)

        let reopened = StudioSession()
        try reopened.replaceCells(
            [(name: StudioSession.defaultCellName, schematic: SchematicDocument())],
            topCell: StudioSession.defaultCellName,
            activeCell: StudioSession.defaultCellName
        )
        #expect(reopened.cells.map(\.name) == [StudioSession.defaultCellName])
        #expect(reopened.topCellName == StudioSession.defaultCellName)
        #expect(!reopened.hasUnsavedChanges)
    }
}
