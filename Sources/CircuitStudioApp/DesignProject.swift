import SwiftUI
import CircuitStudioCore
import SchematicEditor
import WaveformViewer
import LayoutEditor
import LayoutCore
import LayoutTech
import LayoutIO
import LayoutVerify

/// Unified design project that owns all editor ViewModels and shared state.
@Observable
@MainActor
public final class DesignProject {
    // Editor ViewModels
    public let schematicViewModel: SchematicViewModel
    public let layoutViewModel: LayoutEditorViewModel
    public let waveformViewModel: WaveformViewModel

    // Cross-probe
    public let crossProbe: CrossProbeService

    // Auto-layout
    private let autoLayoutService: AutoLayoutService
    public var designUnit: DesignUnit?
    public var layoutGenerationError: String?
    public var unroutedNets: [String] = []
    public var skippedComponents: [String] = []

    // Technology database (nil = use sampleProcess default)
    public var techDatabase: LayoutTechDatabase?
    public var techName: String?

    // Design metadata
    public var designName: String = "Untitled"
    public var isNetlistDirty: Bool = false

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
        self.autoLayoutService = AutoLayoutService()
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
        layoutGenerationError = nil
        unroutedNets = []
        skippedComponents = []

        do {
            let output = try autoLayoutService.generate(
                from: schematicViewModel.document,
                catalog: catalog,
                tech: techDatabase
            )

            // Update layout editor
            layoutViewModel.editor = LayoutDocumentEditor(document: output.document)
            layoutViewModel.tech = output.tech
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
extension DesignProject {
    /// Creates a project with layout already generated from a sample schematic.
    static func withGeneratedLayout(
        schematicViewModel: SchematicViewModel,
        catalog: DeviceCatalog = .standard(),
        canvasSize: CGSize = CGSize(width: 1200, height: 800)
    ) -> DesignProject {
        let project = DesignProject(schematicViewModel: schematicViewModel)
        project.generateLayout(catalog: catalog)
        project.layoutViewModel.canvasSize = canvasSize
        project.layoutViewModel.fitAll()
        return project
    }
}
#endif
