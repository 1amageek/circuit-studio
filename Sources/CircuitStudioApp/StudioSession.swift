import SwiftUI
import CircuitStudioCore
import SchematicEditor
import WaveformViewer
import LayoutEditor
import LayoutCore
import LayoutTech
import LayoutIO
import LayoutVerify

/// Human app session that owns editor ViewModels and shared UI state.
@Observable
@MainActor
public final class StudioSession {
    // Editor ViewModels
    public let schematicViewModel: SchematicViewModel
    public let layoutViewModel: LayoutEditorViewModel
    public let waveformViewModel: WaveformViewModel

    // Cross-probe
    public let crossProbe: CrossProbeService

    // Auto-layout
    public var designUnit: DesignUnit?
    public var layoutGenerationError: String?
    public var unroutedNets: [String] = []
    public var skippedComponents: [String] = []

    // Technology database (nil = use sampleProcess default)
    public var techDatabase: LayoutTechDatabase?
    public var techName: String?

    // Design metadata
    public var designName: String = "Untitled"

    /// Schematic hash as of the last project open or save; nil = never persisted.
    public var lastSavedSchematicHash: Int?

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

    public init(
        schematicViewModel: SchematicViewModel = SchematicViewModel(),
        layoutViewModel: LayoutEditorViewModel = LayoutEditorViewModel(),
        waveformViewModel: WaveformViewModel = WaveformViewModel()
    ) {
        self.schematicViewModel = schematicViewModel
        self.layoutViewModel = layoutViewModel
        self.waveformViewModel = waveformViewModel
        self.crossProbe = CrossProbeService()
    }

    /// Loads a technology file and converts it to a LayoutTechDatabase.
    ///
    /// Supports `.json` (IRTechLibrary), `.lef`, and `.lyp` formats.
    public func loadTechFile(from url: URL) throws {
        let converter = TechFormatConverter()
        let tech = try converter.loadTech(from: url)
        techDatabase = tech
        techName = url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Project Config Extraction / Restoration

    /// Extracts schematic placement for persistence.
    public func schematicPlacement(sourceNetlist: String) -> SchematicPlacement {
        SchematicPlacement(
            sourceNetlist: sourceNetlist,
            document: schematicViewModel.document
        )
    }

    /// Restores schematic state from a persisted placement.
    public func apply(_ placement: SchematicPlacement) {
        schematicViewModel.document = placement.document
    }

    /// Generates physical layout from the current schematic document.
    ///
    /// Requires a valid schematic with components and wires.
    /// Updates layoutViewModel, crossProbe mappings, and designUnit on success.
    public func generateLayout(catalog: DeviceCatalog) {
        generateLayout(
            service: DesignFlowService(netlistGenerator: NetlistGenerator(catalog: catalog)),
            catalog: catalog
        )
    }

    /// Generates physical layout through the shared design-flow API.
    public func generateLayout(service: DesignFlowService, catalog: DeviceCatalog) {
        layoutGenerationError = nil
        unroutedNets = []
        skippedComponents = []

        do {
            let output = try service.generateLayout(DesignFlowLayoutGenerationRequest(
                schematic: schematicViewModel.document,
                catalog: catalog,
                tech: techDatabase
            ))

            // Update layout editor — loadDocument re-syncs the active cell,
            // render index, and live verification with the new document.
            layoutViewModel.loadDocument(output.document, tech: output.tech)
            layoutViewModel.violations = output.drcResult.violations

            // Update cross-probe mappings
            crossProbe.instanceMapping = output.designUnit.componentToInstance
            crossProbe.netMapping = output.designUnit.netNameToLayoutNet
            crossProbe.instanceToComponent = Dictionary(
                uniqueKeysWithValues: output.designUnit.componentToInstance.map { ($0.value, $0.key) }
            )

            // Store binding
            designUnit = output.designUnit
            unroutedNets = output.unroutedNets
            skippedComponents = output.skippedComponents

            // Auto-fit layout to visible canvas area
            layoutViewModel.fitAll()
        } catch {
            layoutGenerationError = error.localizedDescription
        }
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
