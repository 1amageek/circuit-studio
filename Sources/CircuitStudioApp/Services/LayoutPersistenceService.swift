import Foundation
import CircuitStudioCore
import LayoutCore

/// Coordinates layout persistence between the in-memory session and the
/// project on disk, mirroring Xcode's file model: newly generated documents
/// land on disk immediately, edits are tracked as unsaved changes until
/// the next save, and opening a project restores the full editor state.
///
/// Two artifacts are written per save: the native document
/// (`.xcircuite/layout.json`, full fidelity — IDs, nets, pins) which is the
/// restore source of truth, and `top.oas` (mask geometry only) which the
/// PEX and tapeout flows consume.
@MainActor
public struct LayoutPersistenceService {
    /// Project-root file name of the OASIS interchange artifact. Matches the
    /// default layout input of `PEXProjectConfig`.
    public static let interchangeFileName = "top.oas"

    private let projectService: ProjectService

    public init(projectService: ProjectService) {
        self.projectService = projectService
    }

    /// Writes all layout artifacts and records the saved baseline.
    /// The design-unit binding is saved alongside, or removed when the
    /// session has none, so a stale binding cannot resurface on next open.
    public func persistLayout(of project: StudioSession, toProjectAt projectRoot: URL) throws {
        let document = project.layoutViewModel.editor.document
        let tech = project.layoutViewModel.tech
        try projectService.saveLayoutDocument(document, forProjectAt: projectRoot)
        try projectService.saveLayoutTech(tech, forProjectAt: projectRoot)
        if let unit = project.designUnit {
            try projectService.saveDesignUnit(unit, forProjectAt: projectRoot)
        } else {
            try projectService.removeDesignUnit(forProjectAt: projectRoot)
        }
        try projectService.saveLayout(
            document: document,
            tech: tech,
            to: Self.interchangeFileName,
            inProjectAt: projectRoot
        )
        project.markLayoutSaved()
    }

    /// Restores the layout editor state saved by ``persistLayout``.
    /// Returns `false` when the project has no persisted layout document;
    /// throws when artifacts exist but cannot be read, so a broken project
    /// surfaces instead of silently opening empty.
    public func restoreLayout(
        into project: StudioSession,
        fromProjectAt projectRoot: URL
    ) throws -> Bool {
        guard projectService.hasLayoutDocument(forProjectAt: projectRoot) else {
            return false
        }
        let document = try projectService.loadLayoutDocument(forProjectAt: projectRoot)
        let tech = try projectService.loadLayoutTech(forProjectAt: projectRoot)
        let unit = try projectService.loadDesignUnitIfPresent(forProjectAt: projectRoot)
        project.applyLayout(document: document, tech: tech, designUnit: unit)
        return true
    }

    /// Generates a layout and, when a project is open, writes the layout
    /// artifacts immediately — a newly created document belongs on disk.
    /// Without a project the layout stays in memory and is reported as
    /// unsaved by ``StudioSession/isLayoutDirty``.
    public func generateLayout(
        project: StudioSession,
        appState: AppState,
        designFlow: DesignFlowService,
        catalog: DeviceCatalog
    ) {
        project.generateLayout(service: designFlow, catalog: catalog)
        guard project.layoutGenerationError == nil else { return }
        guard let projectRoot = appState.projectRootURL else { return }
        do {
            try persistLayout(of: project, toProjectAt: projectRoot)
            appState.log("Layout saved to \(Self.interchangeFileName)", kind: .success)
        } catch {
            appState.log(
                "Layout generated but could not be saved: \(error.localizedDescription)",
                kind: .error
            )
        }
    }
}
