import Foundation
import Testing
import CircuitStudioApp
import CircuitStudioCore

@Suite("Editor Navigation Host Tests")
@MainActor
struct EditorNavigationHostTests {
    @Test func projectFileSelectionKeepsTheLoadedNetlist() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-editor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { removeTemporaryItem(root) }

        let netlistURL = root.appending(path: "top.cir")
        let techURL = root.appending(path: "tech.json")
        try "* source\n.end\n".write(to: netlistURL, atomically: true, encoding: .utf8)
        try "{}\n".write(to: techURL, atomically: true, encoding: .utf8)

        let appState = AppState()
        try appState.loadSPICEFile(url: netlistURL)
        appState.showWorkspace(.review)
        appState.requestOpenProjectItem(at: techURL, using: FileSystemService())

        #expect(appState.editorDestination == .projectFile(techURL))
        #expect(appState.activeWorkspace == nil)
        #expect(appState.projectNavigatorSelection == techURL)
        #expect(appState.loadedNetlistURL == netlistURL)

        appState.closeTransientEditor()
        #expect(appState.editorDestination == .review)
    }

    @Test func invalidJSONIsNotWritten() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-invalid-\(UUID().uuidString).json")
        try "{}\n".write(to: url, atomically: true, encoding: .utf8)
        defer { removeTemporaryItem(url) }

        let fileSystem = FileSystemService()
        let appState = AppState()
        appState.requestOpenProjectItem(at: url, using: fileSystem)
        appState.updateProjectFileText("{")

        var didThrow = false
        do {
            try appState.saveProjectFile(using: fileSystem)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        #expect(try String(contentsOf: url, encoding: .utf8) == "{}\n")
    }

    @Test func dirtyFileNavigationWaitsForAUserDecision() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-pending-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { removeTemporaryItem(root) }

        let firstURL = root.appending(path: "first.json")
        let secondURL = root.appending(path: "second.json")
        try "{}".write(to: firstURL, atomically: true, encoding: .utf8)
        try "{}".write(to: secondURL, atomically: true, encoding: .utf8)

        let appState = AppState()
        let fileSystem = FileSystemService()
        appState.requestOpenProjectItem(at: firstURL, using: fileSystem)
        appState.updateProjectFileText("{\"dirty\":true}")
        appState.requestOpenProjectItem(at: secondURL, using: fileSystem)

        #expect(appState.editorDestination == .projectFile(firstURL))
        #expect(appState.pendingProjectItemURL == secondURL)

        appState.cancelPendingProjectItem()
        appState.showWorkspace(.review)
        appState.requestOpenProjectItem(at: firstURL, using: fileSystem)
        #expect(appState.projectFileDocument?.text == "{\"dirty\":true}")
    }

    @Test func agentSideFileChangesAreNotOverwritten() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-conflict-\(UUID().uuidString).json")
        try "{}\n".write(to: url, atomically: true, encoding: .utf8)
        defer { removeTemporaryItem(url) }

        let appState = AppState()
        let fileSystem = FileSystemService()
        appState.requestOpenProjectItem(at: url, using: fileSystem)
        appState.updateProjectFileText("{\"local\":true}\n")
        try "{\"agent\":true}\n".write(to: url, atomically: true, encoding: .utf8)

        var didThrow = false
        do {
            try appState.saveProjectFile(using: fileSystem)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        #expect(try String(contentsOf: url, encoding: .utf8) == "{\"agent\":true}\n")
    }

    @Test func transientFilesPersistOneWorkspaceDestination() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-route-\(UUID().uuidString).json")
        try "{}\n".write(to: url, atomically: true, encoding: .utf8)
        defer { removeTemporaryItem(url) }

        let appState = AppState()
        appState.showSchematic(.visual)
        appState.requestOpenProjectItem(at: url, using: FileSystemService())

        let config = appState.workspaceConfig()
        #expect(config.editorDestination == "schematic.visual")

        let restored = AppState()
        restored.apply(config)
        #expect(restored.editorDestination == .schematic(.visual))
    }

    @Test func projectResetRemovesThePreviousDesignContext() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-reset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { removeTemporaryItem(root) }

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

    private func removeTemporaryItem(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Could not remove temporary test item: \(error.localizedDescription)")
        }
    }
}
