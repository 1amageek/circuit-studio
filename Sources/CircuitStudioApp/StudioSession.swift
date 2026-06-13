import SwiftUI
import CircuitStudioCore
import SchematicEditor
import WaveformViewer
import LayoutEditor
import LayoutCore
import LayoutTech
import LayoutIO
import LayoutVerify

/// Human app session for one project: a library of design cells, each with
/// its own editors, plus the shared state — waveform viewer, technology,
/// and the active-cell pointer that drives every editor pane.
///
/// Cells reference each other by name (`PlacedComponent.cellName`), forming
/// the hierarchy that netlist generation emits as `.subckt` blocks. The
/// session keeps every cell's palette catalog in sync with the library so
/// a cell can always place its siblings — except itself and its ancestors,
/// which would create a cycle.
@Observable
@MainActor
public final class StudioSession {
    /// Default name of the first cell in a fresh session.
    public static let defaultCellName = "Top"

    // MARK: - Cells

    public private(set) var cells: [CellWorkspace]
    public private(set) var activeCell: CellWorkspace
    public private(set) var topCellName: String

    /// Palette/symbol catalog before project cells are folded in.
    public let baseCatalog: DeviceCatalog

    /// Cells excluded from palettes because their interface failed to
    /// derive, with reasons. Refreshed on every catalog rebuild.
    public private(set) var catalogIssues: [DeviceCatalog.CellCatalogIssue] = []

    /// Invoked when the user double-clicks a placed cell instance to
    /// descend into that cell. Attached to every cell's schematic editor.
    public var cellDescendAction: ((String) -> Void)? {
        didSet {
            for cell in cells {
                cell.schematicViewModel.cellInstanceDescendHandler = cellDescendAction
            }
        }
    }

    // MARK: - Shared State

    public let waveformViewModel: WaveformViewModel

    // Technology database (nil = use sampleProcess default)
    public var techDatabase: LayoutTechDatabase?
    public var techName: String?

    // Design metadata
    public var designName: String = "Untitled"

    // MARK: - Init

    /// Creates a session with a single cell. The base catalog is taken from
    /// the provided schematic view model so preconfigured editors keep
    /// their device set.
    public init(
        schematicViewModel: SchematicViewModel = SchematicViewModel(),
        layoutViewModel: LayoutEditorViewModel = LayoutEditorViewModel(),
        waveformViewModel: WaveformViewModel = WaveformViewModel()
    ) {
        let first = CellWorkspace(
            name: Self.defaultCellName,
            schematicViewModel: schematicViewModel,
            layoutViewModel: layoutViewModel
        )
        self.cells = [first]
        self.activeCell = first
        self.topCellName = first.name
        self.baseCatalog = schematicViewModel.catalog
        self.waveformViewModel = waveformViewModel
    }

    // MARK: - Active-Cell Forwarding

    public var activeCellName: String { activeCell.name }
    public var topCell: CellWorkspace? { cell(named: topCellName) }

    public var schematicViewModel: SchematicViewModel { activeCell.schematicViewModel }
    public var layoutViewModel: LayoutEditorViewModel { activeCell.layoutViewModel }
    public var crossProbe: CrossProbeService { activeCell.crossProbe }

    public var designUnit: DesignUnit? {
        get { activeCell.designUnit }
        set { activeCell.designUnit = newValue }
    }

    public var layoutGenerationError: String? {
        get { activeCell.layoutGenerationError }
        set { activeCell.layoutGenerationError = newValue }
    }

    public var unroutedNets: [String] {
        get { activeCell.unroutedNets }
        set { activeCell.unroutedNets = newValue }
    }

    public var skippedComponents: [String] {
        get { activeCell.skippedComponents }
        set { activeCell.skippedComponents = newValue }
    }

    public var lastSavedSchematicHash: Int? {
        get { activeCell.lastSavedSchematicHash }
        set { activeCell.lastSavedSchematicHash = newValue }
    }

    public var isSchematicDirty: Bool { activeCell.isSchematicDirty }
    public var isLayoutStale: Bool { activeCell.isLayoutStale }
    public var layoutHasContent: Bool { activeCell.layoutHasContent }
    public var isLayoutDirty: Bool { activeCell.isLayoutDirty }

    public func markSchematicSaved() { activeCell.markSchematicSaved() }
    public func markLayoutSaved() { activeCell.markLayoutSaved() }

    /// True when any cell in the project has unsaved schematic or layout
    /// changes — the quit-guard and title-bar dirty signal.
    public var hasUnsavedChanges: Bool {
        cells.contains { $0.hasUnsavedChanges }
    }

    // MARK: - Cell Library

    /// The current cell library: every cell's live schematic document plus
    /// the top-cell designation. This is what netlist generation, palette
    /// building, and persistence consume.
    public var cellLibrary: CellLibrary {
        CellLibrary(
            cells: cells.map { DesignCell(name: $0.name, schematic: $0.schematicViewModel.document) },
            topCellName: topCellName
        )
    }

    public func cell(named name: String) -> CellWorkspace? {
        let key = CellLibrary.identityKey(name)
        return cells.first { CellLibrary.identityKey($0.name) == key }
    }

    // MARK: - Cell Operations

    /// Adds an empty cell and makes it active — the IDE "new file" gesture.
    public func addCell(named rawName: String) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CellInterface.isValidSPICEName(name) else {
            throw StudioSessionError.invalidCellName(name)
        }
        let key = CellLibrary.identityKey(name)
        guard !cells.contains(where: { CellLibrary.identityKey($0.name) == key }) else {
            throw StudioSessionError.duplicateCellName(name)
        }
        let workspace = CellWorkspace(
            name: name,
            schematicViewModel: SchematicViewModel(catalog: baseCatalog)
        )
        workspace.schematicViewModel.cellInstanceDescendHandler = cellDescendAction
        cells.append(workspace)
        activeCell = workspace
        rebuildCatalogs()
    }

    /// Removes a cell. The top cell, the last remaining cell, and cells
    /// still instantiated by others are protected by typed errors.
    public func removeCell(named name: String) throws {
        let key = CellLibrary.identityKey(name)
        guard let index = cells.firstIndex(where: { CellLibrary.identityKey($0.name) == key }) else {
            throw StudioSessionError.unknownCell(name)
        }
        guard cells.count > 1 else {
            throw StudioSessionError.cannotRemoveLastCell
        }
        guard key != CellLibrary.identityKey(topCellName) else {
            throw StudioSessionError.cannotRemoveTopCell(name)
        }
        let referencedBy = cells
            .filter { CellLibrary.identityKey($0.name) != key }
            .filter { workspace in
                workspace.schematicViewModel.document.components.contains { component in
                    guard let cellName = component.cellName else { return false }
                    return CellLibrary.identityKey(cellName) == key
                }
            }
            .map(\.name)
        guard referencedBy.isEmpty else {
            throw StudioSessionError.cellInUse(cell: name, referencedBy: referencedBy)
        }

        let removed = cells.remove(at: index)
        if activeCell === removed {
            // The top cell always survives removal (guarded above).
            try activateCell(named: topCellName)
        }
        rebuildCatalogs()
    }

    /// Switches editing to the named cell and refreshes its palette so
    /// interface changes made in other cells are visible immediately.
    public func activateCell(named name: String) throws {
        guard let workspace = cell(named: name) else {
            throw StudioSessionError.unknownCell(name)
        }
        activeCell = workspace
        rebuildCatalogs()
    }

    /// Designates the hierarchy root — the cell that `top.cir`, `top.oas`,
    /// and the tapeout flow are generated from.
    public func setTopCell(named name: String) throws {
        guard let workspace = cell(named: name) else {
            throw StudioSessionError.unknownCell(name)
        }
        // Store the canonical cell name so topCellName always equals a real
        // cell's name verbatim, keeping case-sensitive comparisons correct.
        topCellName = workspace.name
    }

    /// Replaces the whole cell set — the project-open path. The previous
    /// session content is discarded. Throws when the top or active cell is
    /// not in the new set, or the library fails validation.
    public func replaceCells(
        _ newCells: [(name: String, schematic: SchematicDocument)],
        topCell: String,
        activeCell activeName: String
    ) throws {
        let topKey = CellLibrary.identityKey(topCell)
        let activeKey = CellLibrary.identityKey(activeName)
        guard newCells.contains(where: { CellLibrary.identityKey($0.name) == topKey }) else {
            throw StudioSessionError.unknownCell(topCell)
        }
        guard newCells.contains(where: { CellLibrary.identityKey($0.name) == activeKey }) else {
            throw StudioSessionError.unknownCell(activeName)
        }
        let library = CellLibrary(
            cells: newCells.map { DesignCell(name: $0.name, schematic: $0.schematic) },
            topCellName: topCell
        )
        try library.validate()

        let workspaces = newCells.map { entry -> CellWorkspace in
            let workspace = CellWorkspace(
                name: entry.name,
                schematicViewModel: SchematicViewModel(catalog: baseCatalog)
            )
            workspace.schematicViewModel.document = entry.schematic
            workspace.schematicViewModel.cellInstanceDescendHandler = cellDescendAction
            workspace.markSchematicSaved()
            return workspace
        }
        cells = workspaces
        // Canonicalize: topCellName always equals a real cell's name, so
        // case-sensitive comparisons against it (such as layout persistence
        // selecting the top cell) stay correct.
        topCellName = workspaces.first { CellLibrary.identityKey($0.name) == topKey }?.name ?? topCell
        // Guarded above: activeName matches a cell case-insensitively.
        activeCell = workspaces.first { CellLibrary.identityKey($0.name) == activeKey } ?? workspaces[0]
        rebuildCatalogs()
    }

    /// Rebuilds every cell's palette catalog from the current library.
    /// Each cell sees all siblings except itself and its ancestors (cycle
    /// prevention). Interface failures are collected, not swallowed.
    public func rebuildCatalogs() {
        let library = cellLibrary
        var issues: [DeviceCatalog.CellCatalogIssue] = []
        for workspace in cells {
            let result = baseCatalog.includingCells(
                from: library,
                activeCellName: workspace.name
            )
            workspace.schematicViewModel.updateCatalog(result.catalog)
            if workspace === activeCell {
                issues = result.issues
            }
        }
        catalogIssues = issues
    }

    // MARK: - Technology

    /// Loads a technology file and converts it to a LayoutTechDatabase.
    ///
    /// Supports `.json` (IRTechLibrary), `.lef`, and `.lyp` formats.
    public func loadTechFile(from url: URL) throws {
        let converter = TechFormatConverter()
        let tech = try converter.loadTech(from: url)
        techDatabase = tech
        techName = url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Layout

    /// Restores persisted layout state into the active cell.
    public func applyLayout(
        document: LayoutDocument,
        tech: LayoutTechDatabase,
        designUnit unit: DesignUnit?
    ) {
        activeCell.applyLayout(document: document, tech: tech, designUnit: unit)
    }

    /// Generates physical layout for the active cell.
    public func generateLayout(catalog: DeviceCatalog) {
        generateLayout(
            service: DesignFlowService(netlistGenerator: NetlistGenerator(catalog: catalog)),
            catalog: catalog
        )
    }

    /// Generates physical layout for the active cell through the shared
    /// design-flow API.
    public func generateLayout(service: DesignFlowService, catalog: DeviceCatalog) {
        activeCell.generateLayout(service: service, catalog: catalog, tech: techDatabase)
    }
}

#if DEBUG
extension StudioSession {
    /// Creates a project with layout already generated from a sample schematic.
    static func withGeneratedLayout(
        schematicViewModel: SchematicViewModel,
        catalog: DeviceCatalog = .standard(),
        canvasSize: CGSize = CGSize(width: 1200, height: 800)
    ) -> StudioSession {
        let project = StudioSession(schematicViewModel: schematicViewModel)
        project.generateLayout(catalog: catalog)
        project.layoutViewModel.canvasSize = canvasSize
        project.layoutViewModel.fitAll()
        return project
    }
}
#endif
