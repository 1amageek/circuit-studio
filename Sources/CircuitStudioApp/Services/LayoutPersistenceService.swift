import Foundation
import CircuitStudioCore
import LayoutCore

/// Coordinates layout persistence between the in-memory session and the
/// project on disk, mirroring Xcode's file model: newly generated documents
/// land on disk immediately, edits are tracked as unsaved changes until
/// the next save, and opening a project restores the full editor state.
///
/// Layouts are persisted per cell under `cells/<name>/`: the native document
/// (`layout.json`, full fidelity — IDs, nets, pins) which is the restore
/// source of truth, plus the design-unit binding. The top cell additionally
/// writes `top.oas` (mask geometry only) at the project root, which the PEX
/// and tapeout flows consume. The technology database is project-wide.
@MainActor
public struct LayoutPersistenceService {
    /// Project-root file name of the OASIS interchange artifact. Matches the
    /// default layout input of `PEXProjectConfig`.
    public static let interchangeFileName = "top.oas"

    private let projectService: ProjectService

    public init(projectService: ProjectService) {
        self.projectService = projectService
    }

    /// Writes one cell's layout artifacts and records its saved baseline.
    /// The design-unit binding is saved alongside, or removed when the
    /// workspace has none, so a stale binding cannot resurface on next
    /// open. When the cell is the project's top cell the OASIS interchange
    /// artifact is refreshed too.
    public func persistLayout(
        of workspace: CellWorkspace,
        in project: StudioSession,
        toProjectAt projectRoot: URL
    ) throws {
        let document = workspace.layoutViewModel.editor.document
        let tech = workspace.layoutViewModel.tech
        try projectService.saveCellLayoutDocument(
            document,
            cellName: workspace.name,
            forProjectAt: projectRoot
        )
        try projectService.saveLayoutTech(tech, forProjectAt: projectRoot)
        if let unit = workspace.designUnit {
            try projectService.saveCellDesignUnit(unit, cellName: workspace.name, forProjectAt: projectRoot)
        } else {
            try projectService.removeCellDesignUnit(cellName: workspace.name, forProjectAt: projectRoot)
        }
        if workspace.name == project.topCellName {
            try projectService.saveLayout(
                document: document,
                tech: tech,
                to: Self.interchangeFileName,
                inProjectAt: projectRoot
            )
        }
        workspace.markLayoutSaved()
    }

    /// Persists every cell's layout. Cells whose layout is empty have their
    /// stale on-disk layout artifacts removed instead, so a cleared layout
    /// stays cleared after reopen.
    public func persistAllLayouts(of project: StudioSession, toProjectAt projectRoot: URL) throws {
        for workspace in project.cells {
            if workspace.layoutHasContent {
                try persistLayout(of: workspace, in: project, toProjectAt: projectRoot)
            } else {
                try projectService.removeCellLayoutArtifacts(
                    cellName: workspace.name,
                    forProjectAt: projectRoot
                )
            }
        }
    }

    /// Restores the layout editor state saved by ``persistLayout(of:in:toProjectAt:)``.
    /// Returns `false` when the cell has no persisted layout document;
    /// throws when artifacts exist but cannot be read, so a broken project
    /// surfaces instead of silently opening empty.
    public func restoreLayout(
        into workspace: CellWorkspace,
        fromProjectAt projectRoot: URL
    ) throws -> Bool {
        guard projectService.hasCellLayoutDocument(
            cellName: workspace.name,
            forProjectAt: projectRoot
        ) else {
            return false
        }
        let document = try projectService.loadCellLayoutDocument(
            cellName: workspace.name,
            forProjectAt: projectRoot
        )
        let tech = try projectService.loadLayoutTech(forProjectAt: projectRoot)
        let unit = try projectService.loadCellDesignUnitIfPresent(
            cellName: workspace.name,
            forProjectAt: projectRoot
        )
        workspace.applyLayout(document: document, tech: tech, designUnit: unit)
        return true
    }

    /// Generates a layout for the active cell and, when a project is open,
    /// writes its layout artifacts immediately — a newly created document
    /// belongs on disk. Without a project the layout stays in memory and is
    /// reported as unsaved by ``CellWorkspace/isLayoutDirty``.
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
            try persistLayout(of: project.activeCell, in: project, toProjectAt: projectRoot)
            appState.log(
                "Layout of \(project.activeCellName) saved",
                kind: .success
            )
        } catch {
            appState.log(
                "Layout generated but could not be saved: \(error.localizedDescription)",
                kind: .error
            )
        }
    }
}
