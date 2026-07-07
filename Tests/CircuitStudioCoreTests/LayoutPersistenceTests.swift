import Foundation
import LayoutCore
import LayoutEditor
import Testing

@testable import CircuitStudioApp
@testable import CircuitStudioCore
@testable import SchematicEditor

/// Creates a throwaway project directory initialized as a studio project.
private func makeTemporaryProject() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "layout-persistence-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try ProjectService().createProject(at: root)
    return root
}

private func removeTemporaryProject(_ root: URL) {
    do {
        try FileManager.default.removeItem(at: root)
    } catch {
        Issue.record("Failed to remove temporary project root \(root.path(percentEncoded: false)): \(error)")
    }
}

@MainActor
private func makeGeneratedSession() -> StudioSession {
    let project = StudioSession(schematicViewModel: SchematicPreview.cmosInverterViewModel())
    let catalog = DeviceCatalog.standard()
    let service = DesignFlowService(netlistGenerator: NetlistGenerator(catalog: catalog))
    project.generateLayout(service: service, catalog: catalog)
    return project
}

@Suite("Layout Project Artifacts")
@MainActor
struct LayoutProjectArtifactTests {

    @Test("Layout document, tech, and design unit round-trip through the project")
    func artifactRoundTrip() throws {
        let root = try makeTemporaryProject()
        defer { removeTemporaryProject(root) }
        let service = ProjectService()

        let project = makeGeneratedSession()
        let cell = project.activeCellName
        let document = project.layoutViewModel.editor.document
        let tech = project.layoutViewModel.tech
        let unit = try #require(project.designUnit)

        try service.saveCellLayoutDocument(document, cellName: cell, forProjectAt: root)
        try service.saveLayoutTech(tech, forProjectAt: root)
        try service.saveCellDesignUnit(unit, cellName: cell, forProjectAt: root)

        #expect(try service.loadCellLayoutDocument(cellName: cell, forProjectAt: root) == document)
        #expect(try service.loadLayoutTech(forProjectAt: root) == tech)

        let loadedUnit = try #require(
            try service.loadCellDesignUnitIfPresent(cellName: cell, forProjectAt: root)
        )
        #expect(loadedUnit.componentToInstance == unit.componentToInstance)
        #expect(loadedUnit.netNameToLayoutNet == unit.netNameToLayoutNet)
        #expect(loadedUnit.deviceKindToCell == unit.deviceKindToCell)
        #expect(loadedUnit.schematicHash == unit.schematicHash)
    }

    @Test("A cell without a saved layout reports none")
    func emptyProjectHasNoLayout() throws {
        let root = try makeTemporaryProject()
        defer { removeTemporaryProject(root) }
        let service = ProjectService()

        let cell = StudioSession.defaultCellName
        #expect(!service.hasCellLayoutDocument(cellName: cell, forProjectAt: root))
        #expect(try service.loadCellDesignUnitIfPresent(cellName: cell, forProjectAt: root) == nil)
    }

    @Test("removeCellDesignUnit clears a persisted binding and tolerates absence")
    func removeDesignUnit() throws {
        let root = try makeTemporaryProject()
        defer { removeTemporaryProject(root) }
        let service = ProjectService()
        let cell = StudioSession.defaultCellName

        // Removing a binding that was never written must not throw.
        try service.removeCellDesignUnit(cellName: cell, forProjectAt: root)

        try service.saveCellDesignUnit(DesignUnit(schematicHash: 42), cellName: cell, forProjectAt: root)
        #expect(try service.loadCellDesignUnitIfPresent(cellName: cell, forProjectAt: root) != nil)

        try service.removeCellDesignUnit(cellName: cell, forProjectAt: root)
        #expect(try service.loadCellDesignUnitIfPresent(cellName: cell, forProjectAt: root) == nil)
    }
}

@Suite("Layout Dirty Tracking")
@MainActor
struct LayoutDirtyTrackingTests {

    @Test("A fresh session with an empty layout is clean")
    func freshSessionIsClean() {
        let project = StudioSession()
        #expect(!project.layoutHasContent)
        #expect(!project.isLayoutDirty)
    }

    @Test("A generated layout counts as unsaved until persisted")
    func generatedLayoutIsDirty() {
        let project = makeGeneratedSession()
        #expect(project.layoutHasContent)
        #expect(project.isLayoutDirty)
    }

    @Test("markLayoutSaved clears the dirty state")
    func markSavedClears() {
        let project = makeGeneratedSession()
        project.markLayoutSaved()
        #expect(!project.isLayoutDirty)
    }

    @Test("Editing after a save marks the layout dirty again")
    func editAfterSaveIsDirty() {
        let project = makeGeneratedSession()
        project.markLayoutSaved()
        project.layoutViewModel.addRectangle(
            from: LayoutPoint(x: 0, y: 0),
            to: LayoutPoint(x: 50, y: 50)
        )
        #expect(project.isLayoutDirty)
    }

    @Test("Deleting all content after a save still counts as dirty")
    func deleteAllAfterSaveIsDirty() {
        let project = StudioSession()
        project.layoutViewModel.addRectangle(
            from: LayoutPoint(x: 0, y: 0),
            to: LayoutPoint(x: 100, y: 100)
        )
        project.markLayoutSaved()

        project.layoutViewModel.selectAllShapes()
        project.layoutViewModel.deleteSelection()

        #expect(!project.layoutHasContent)
        #expect(project.isLayoutDirty, "Disk still holds shapes; the session must not read clean")
    }
}

@Suite("Layout Persist and Restore")
@MainActor
struct LayoutPersistRestoreTests {

    @Test("Persisting writes the editor artifacts and the OASIS interchange file")
    func persistWritesArtifacts() throws {
        let root = try makeTemporaryProject()
        defer { removeTemporaryProject(root) }
        let projectService = ProjectService()
        let persistence = LayoutPersistenceService(projectService: projectService)

        let project = makeGeneratedSession()
        try persistence.persistLayout(of: project.activeCell, in: project, toProjectAt: root)

        #expect(projectService.hasCellLayoutDocument(cellName: project.activeCellName, forProjectAt: root))
        #expect(try projectService.loadCellDesignUnitIfPresent(cellName: project.activeCellName, forProjectAt: root) != nil)
        let oasPath = root.appending(path: LayoutPersistenceService.interchangeFileName)
        #expect(FileManager.default.fileExists(atPath: oasPath.path(percentEncoded: false)))
        #expect(!project.isLayoutDirty)
    }

    @Test("Persisting without a design unit removes a stale binding")
    func persistWithoutDesignUnitRemovesBinding() throws {
        let root = try makeTemporaryProject()
        defer { removeTemporaryProject(root) }
        let projectService = ProjectService()
        let persistence = LayoutPersistenceService(projectService: projectService)

        let generated = makeGeneratedSession()
        try persistence.persistLayout(of: generated.activeCell, in: generated, toProjectAt: root)
        #expect(try projectService.loadCellDesignUnitIfPresent(cellName: generated.activeCellName, forProjectAt: root) != nil)

        let unbound = StudioSession()
        unbound.layoutViewModel.addRectangle(
            from: LayoutPoint(x: 0, y: 0),
            to: LayoutPoint(x: 100, y: 100)
        )
        try persistence.persistLayout(of: unbound.activeCell, in: unbound, toProjectAt: root)
        #expect(try projectService.loadCellDesignUnitIfPresent(cellName: unbound.activeCellName, forProjectAt: root) == nil)
    }

    @Test("Restore rebuilds the document, binding, and cross-probe, and reads clean")
    func restoreRoundTrip() throws {
        let root = try makeTemporaryProject()
        defer { removeTemporaryProject(root) }
        let persistence = LayoutPersistenceService(projectService: ProjectService())

        let saved = makeGeneratedSession()
        try persistence.persistLayout(of: saved.activeCell, in: saved, toProjectAt: root)

        let reopened = StudioSession()
        let restored = try persistence.restoreLayout(into: reopened.activeCell, fromProjectAt: root)
        #expect(restored)

        #expect(reopened.layoutViewModel.editor.document == saved.layoutViewModel.editor.document)
        #expect(reopened.layoutViewModel.tech == saved.layoutViewModel.tech)

        let unit = try #require(reopened.designUnit)
        let savedUnit = try #require(saved.designUnit)
        #expect(unit.componentToInstance == savedUnit.componentToInstance)
        #expect(unit.schematicHash == savedUnit.schematicHash)

        #expect(reopened.crossProbe.instanceMapping == savedUnit.componentToInstance)
        #expect(reopened.crossProbe.netMapping == savedUnit.netNameToLayoutNet)

        #expect(reopened.layoutHasContent)
        #expect(!reopened.isLayoutDirty, "A freshly restored layout matches disk")

        // The active cell must resolve inside the restored document so the
        // canvas draws it.
        let activeCell = try #require(reopened.layoutViewModel.activeCell)
        #expect(activeCell.id == reopened.layoutViewModel.editor.document.topCellID)
    }

    @Test("Restoring a project without a layout returns false and changes nothing")
    func restoreWithoutLayout() throws {
        let root = try makeTemporaryProject()
        defer { removeTemporaryProject(root) }
        let persistence = LayoutPersistenceService(projectService: ProjectService())

        let project = StudioSession()
        let didRestore = try persistence.restoreLayout(into: project.activeCell, fromProjectAt: root)
        #expect(!didRestore)
        #expect(!project.layoutHasContent)
        #expect(project.designUnit == nil)
    }

    @Test("Generating with an open project writes artifacts immediately")
    func generateWithProjectPersistsImmediately() throws {
        let root = try makeTemporaryProject()
        defer { removeTemporaryProject(root) }
        let projectService = ProjectService()
        let persistence = LayoutPersistenceService(projectService: projectService)

        let appState = AppState()
        appState.projectRootURL = root
        let project = StudioSession(schematicViewModel: SchematicPreview.cmosInverterViewModel())
        let catalog = DeviceCatalog.standard()
        let designFlow = DesignFlowService(netlistGenerator: NetlistGenerator(catalog: catalog))

        persistence.generateLayout(
            project: project,
            appState: appState,
            designFlow: designFlow,
            catalog: catalog
        )

        #expect(project.layoutGenerationError == nil)
        #expect(projectService.hasCellLayoutDocument(cellName: project.activeCellName, forProjectAt: root))
        #expect(!project.isLayoutDirty, "Generation with an open project lands on disk")
    }

    @Test("Generation stops when top netlist has no materialized schematic")
    func generateWithMissingMaterializedSchematicDoesNotPersist() throws {
        let root = try makeTemporaryProject()
        defer { removeTemporaryProject(root) }
        let projectService = ProjectService()
        try projectService.saveNetlist("* imported netlist\n.op\n.end\n", named: "top.cir", inProjectAt: root)
        let persistence = LayoutPersistenceService(projectService: projectService)

        let appState = AppState()
        appState.projectRootURL = root
        appState.selectedFileURL = root.appending(path: "top.cir")
        let project = StudioSession(schematicViewModel: SchematicPreview.cmosInverterViewModel())
        let catalog = DeviceCatalog.standard()
        let designFlow = DesignFlowService(netlistGenerator: NetlistGenerator(catalog: catalog))

        persistence.generateLayout(
            project: project,
            appState: appState,
            designFlow: designFlow,
            catalog: catalog
        )

        #expect(project.layoutGenerationError?.contains("schematic.json is missing") == true)
        #expect(!project.layoutHasContent)
        #expect(!projectService.hasCellLayoutDocument(cellName: project.activeCellName, forProjectAt: root))
        let oasPath = root.appending(path: LayoutPersistenceService.interchangeFileName)
        #expect(!FileManager.default.fileExists(atPath: oasPath.path(percentEncoded: false)))
    }

    @Test("Generating without a project keeps the layout in memory as unsaved")
    func generateWithoutProjectStaysDirty() {
        let persistence = LayoutPersistenceService(projectService: ProjectService())
        let appState = AppState()
        let project = StudioSession(schematicViewModel: SchematicPreview.cmosInverterViewModel())
        let catalog = DeviceCatalog.standard()
        let designFlow = DesignFlowService(netlistGenerator: NetlistGenerator(catalog: catalog))

        persistence.generateLayout(
            project: project,
            appState: appState,
            designFlow: designFlow,
            catalog: catalog
        )

        #expect(project.layoutGenerationError == nil)
        #expect(project.isLayoutDirty)
    }
}

/// The persistence flow only works if the UI actually routes through it;
/// view wiring is unobservable in-process, so it is pinned at the source
/// level like the Delete-key router wiring.
@Suite("Layout Persistence Wiring")
struct LayoutPersistenceWiringTests {

    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CircuitStudioCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func appRestoresLayoutOnProjectOpenAndPersistsOnSave() throws {
        let app = try source("Sources/CircuitStudioApp/App.swift")
        #expect(app.contains("restoreLayout("), "Opening a project must restore every cell's saved layout")
        #expect(app.contains("persistAllLayouts("), "Cmd-S must persist every cell's layout artifacts")
        #expect(app.contains("wireTerminationGuard()"), "Quitting with unsaved changes must prompt")
    }

    @Test func contentViewSurfacesLayoutStateAndUsesThePersistingGenerate() throws {
        let contentView = try source("Sources/CircuitStudioApp/Navigation/ContentView.swift")
        #expect(contentView.contains("project.hasUnsavedChanges"), "Edited badge must include layout and schematic changes across cells")
        #expect(contentView.contains("!project.layoutHasContent"), "Layout pane must show any loaded layout, not only generated ones")
    }

    @Test func uiNeverBypassesThePersistingGenerate() throws {
        for path in [
            "Sources/CircuitStudioApp/App.swift",
            "Sources/CircuitStudioApp/Navigation/ContentView.swift",
        ] {
            let text = try source(path)
            #expect(
                !text.contains("project.generateLayout(service:"),
                "\(path) must generate through LayoutPersistenceService so new layouts land on disk"
            )
        }
    }
}
