import SwiftUI
import CircuitStudioCore
import CircuitPhysicalDesign
import SchematicEditor
import LayoutEditor
import LayoutCore
import LayoutTech

/// Editing state for one design cell: its schematic, its layout, and the
/// binding between them. A project session owns one workspace per cell, so
/// every cell keeps independent editors, cross-probe mappings, and dirty
/// tracking — the same per-file model an IDE uses for open documents.
@Observable
@MainActor
public final class CellWorkspace: Identifiable {
    /// Cell name — the identity shared with netlists, layouts, and the
    /// on-disk `cells/<name>/` directory.
    public let name: String

    public let schematicViewModel: SchematicViewModel
    public let layoutViewModel: LayoutEditorViewModel
    public let crossProbe: CrossProbeService

    // Schematic-to-layout binding
    public var designUnit: DesignUnit?
    public var layoutGenerationError: String?
    public var unroutedNets: [String] = []
    public var skippedComponents: [String] = []

    /// Schematic hash as of the last project open or save; nil = never persisted.
    public var lastSavedSchematicHash: Int?

    public nonisolated var id: String { name }

    public init(
        name: String,
        schematicViewModel: SchematicViewModel = SchematicViewModel(),
        layoutViewModel: LayoutEditorViewModel = LayoutEditorViewModel()
    ) {
        self.name = name
        self.schematicViewModel = schematicViewModel
        self.layoutViewModel = layoutViewModel
        self.crossProbe = CrossProbeService()
    }

    // MARK: - Dirty Tracking

    /// True when the schematic differs from the last opened/saved state.
    /// A never-persisted schematic counts as dirty once it has content.
    public var isSchematicDirty: Bool {
        let current = DesignUnit.schematicHash(for: schematicViewModel.document)
        guard let saved = lastSavedSchematicHash else {
            return !schematicViewModel.document.components.isEmpty
                || !schematicViewModel.document.wires.isEmpty
        }
        return current != saved
    }

    /// Records the current schematic as the saved baseline.
    public func markSchematicSaved() {
        lastSavedSchematicHash = DesignUnit.schematicHash(for: schematicViewModel.document)
    }

    /// True when the schematic has changed since the last layout generation.
    public var isLayoutStale: Bool {
        guard let unit = designUnit else { return false }
        let currentHash = DesignUnit.schematicHash(for: schematicViewModel.document)
        return unit.schematicHash != currentHash
    }

    /// True when any cell carries geometry, vias, or instances.
    public var layoutHasContent: Bool {
        layoutViewModel.editor.document.cells.contains { cell in
            !cell.shapes.isEmpty || !cell.vias.isEmpty || !cell.instances.isEmpty
        }
    }

    /// True when the layout differs from its last persisted state.
    /// A never-persisted layout counts as dirty once it has content.
    public var isLayoutDirty: Bool {
        guard layoutViewModel.editor.isPersisted else { return layoutHasContent }
        return layoutViewModel.editor.hasUnsavedChanges
    }

    /// Records the current layout as the saved baseline.
    public func markLayoutSaved() {
        layoutViewModel.editor.markSaved()
    }

    /// True when this cell has any unsaved schematic or layout changes.
    public var hasUnsavedChanges: Bool {
        isSchematicDirty || isLayoutDirty
    }

    // MARK: - Layout Restoration

    /// Restores persisted layout editor state: the document, its technology,
    /// and the schematic-to-layout binding that powers cross-probe and
    /// staleness tracking. Marks the restored layout as the saved baseline.
    public func applyLayout(
        document: LayoutDocument,
        tech: LayoutTechDatabase,
        designUnit unit: DesignUnit?
    ) {
        layoutViewModel.loadDocument(document, tech: tech)
        designUnit = unit
        if let unit {
            crossProbe.instanceMapping = unit.componentToInstance
            crossProbe.netMapping = unit.netNameToLayoutNet
            // Inverting a map can collide if two components share a layout
            // instance; keep the first deterministically rather than trapping.
            crossProbe.instanceToComponent = Dictionary(
                unit.componentToInstance.map { ($0.value, $0.key) },
                uniquingKeysWith: { first, _ in first }
            )
        } else {
            crossProbe.instanceMapping = [:]
            crossProbe.netMapping = [:]
            crossProbe.instanceToComponent = [:]
        }
        layoutViewModel.fitAll()
        markLayoutSaved()
    }

    // MARK: - Layout Generation

    /// Generates physical layout from this cell's schematic through the
    /// shared design-flow API. Updates the layout editor, cross-probe
    /// mappings, and the design-unit binding on success; records the error
    /// on failure (hierarchical cells are rejected by the auto-layout
    /// engine with a typed error).
    public func generateLayout(
        service: DesignFlowService,
        catalog: DeviceCatalog,
        tech: LayoutTechDatabase?
    ) {
        layoutGenerationError = nil
        unroutedNets = []
        skippedComponents = []

        let availability = CircuitLayoutAvailability.evaluate(
            document: schematicViewModel.document,
            catalog: catalog,
            deviceCellEngines: service.layoutEngineCatalog,
            activeCellName: name
        )
        guard availability.isAvailable else {
            layoutGenerationError = availability.reason
            return
        }

        do {
            let output = try service.generateLayout(DesignFlowLayoutGenerationRequest(
                schematic: schematicViewModel.document,
                catalog: catalog,
                tech: tech
            ))

            // loadDocument re-syncs the active cell, render index, and live
            // verification with the new document.
            layoutViewModel.loadDocument(output.document, tech: output.tech)
            layoutViewModel.violations = output.drcResult.violations

            crossProbe.instanceMapping = output.designUnit.componentToInstance
            crossProbe.netMapping = output.designUnit.netNameToLayoutNet
            // Inverting a map can collide if two components share a layout
            // instance; keep the first deterministically rather than trapping.
            crossProbe.instanceToComponent = Dictionary(
                output.designUnit.componentToInstance.map { ($0.value, $0.key) },
                uniquingKeysWith: { first, _ in first }
            )

            designUnit = output.designUnit
            unroutedNets = output.unroutedNets
            skippedComponents = output.skippedComponents

            layoutViewModel.fitAll()
        } catch {
            layoutGenerationError = error.localizedDescription
        }
    }
}
