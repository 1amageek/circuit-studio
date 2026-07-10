import Foundation
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore

@Suite("Editor Navigation Tests")
@MainActor
struct EditorNavigationTests {
    @Test func projectSelectionDoesNotReplaceLoadedNetlistIdentity() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "editor-navigation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { removeCoreTestTemporaryDirectory(root) }

        let netlistURL = root.appending(path: "top.cir")
        let techURL = root.appending(path: "tech.json")
        try "* source\n.end\n".write(to: netlistURL, atomically: true, encoding: .utf8)
        try "{\"name\":\"test\"}\n".write(to: techURL, atomically: true, encoding: .utf8)

        let fileSystem = FileSystemService()
        let appState = AppState()
        try appState.loadSPICEFile(url: netlistURL)
        appState.showWorkspace(.review)
        appState.requestOpenProjectItem(at: techURL, using: fileSystem)

        #expect(appState.editorDestination == .projectFile(techURL))
        #expect(appState.activeWorkspace == nil)
        #expect(appState.projectNavigatorSelection == techURL)
        #expect(appState.loadedNetlistURL == netlistURL)
        #expect(appState.spiceSource == "* source\n.end\n")

        appState.closeTransientEditor()
        #expect(appState.editorDestination == .review)
    }

    @Test func directorySelectionHasAVisibleDestination() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "editor-directory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { removeCoreTestTemporaryDirectory(root) }

        let appState = AppState()
        appState.requestOpenProjectItem(at: root, using: FileSystemService())

        #expect(appState.editorDestination == .projectDirectory(root))
        #expect(appState.projectNavigatorSelection == root)
    }

    @Test func transientEditorsPersistTheLastWorkspaceDestination() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "editor-config-\(UUID().uuidString).json")
        try "{}".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { removeCoreTestTemporaryDirectory(fileURL) }

        let appState = AppState()
        appState.showSchematic(.visual)
        appState.requestOpenProjectItem(at: fileURL, using: FileSystemService())

        let config = appState.workspaceConfig()
        #expect(config.editorDestination == "schematic.visual")

        let restored = AppState()
        restored.apply(config)
        #expect(restored.editorDestination == .schematic(.visual))
    }

    @Test func dirtyFileRequiresAnExplicitResolutionBeforeNavigation() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "editor-pending-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { removeCoreTestTemporaryDirectory(root) }

        let firstURL = root.appending(path: "first.json")
        let secondURL = root.appending(path: "second.json")
        try "{}".write(to: firstURL, atomically: true, encoding: .utf8)
        try "{}".write(to: secondURL, atomically: true, encoding: .utf8)

        let fileSystem = FileSystemService()
        let appState = AppState()
        appState.requestOpenProjectItem(at: firstURL, using: fileSystem)
        appState.updateProjectFileText("{\"dirty\":true}")
        appState.requestOpenProjectItem(at: secondURL, using: fileSystem)

        #expect(appState.editorDestination == .projectFile(firstURL))
        #expect(appState.projectNavigatorSelection == firstURL)
        #expect(appState.pendingProjectItemURL == secondURL)
        #expect(appState.isProjectFileDirty)

        appState.cancelPendingProjectItem()
        appState.showWorkspace(.review)
        appState.requestOpenProjectItem(at: firstURL, using: fileSystem)
        #expect(appState.projectFileDocument?.text == "{\"dirty\":true}")
        #expect(appState.isProjectFileDirty)
    }

    @Test func projectResetRemovesThePreviousDesignContext() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "editor-reset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { removeCoreTestTemporaryDirectory(root) }

        let netlistURL = root.appending(path: "top.cir")
        try "* source\n.end\n".write(to: netlistURL, atomically: true, encoding: .utf8)
        let appState = AppState()
        appState.setProjectRoot(
            root,
            fileTree: FileNode(id: root, name: root.lastPathComponent, isDirectory: true)
        )
        try appState.loadSPICEFile(url: netlistURL)
        appState.showWorkspace(.review)

        appState.resetProjectScopedState()

        #expect(appState.projectRootURL == nil)
        #expect(appState.loadedNetlistURL == nil)
        #expect(appState.spiceSource.isEmpty)
        #expect(appState.editorDestination == .schematic(.netlist))
    }
}
