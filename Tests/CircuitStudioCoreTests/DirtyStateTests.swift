import Testing
import Foundation
import CoreGraphics
@testable import CircuitStudioApp
@testable import CircuitStudioCore

@Suite("Dirty State Tests")
@MainActor
struct DirtyStateTests {

    // MARK: - Netlist dirty (AppState)

    @Test func freshAppStateIsNotDirty() {
        let appState = AppState()
        #expect(!appState.isNetlistDirty)
    }

    @Test func editingSpiceSourceMarksDirty() {
        let appState = AppState()
        appState.spiceSource = "* edited"
        #expect(appState.isNetlistDirty)
    }

    @Test func loadSPICEFileResetsDirtyBaseline() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dirty-test-\(UUID().uuidString).cir")
        try "* loaded netlist\n.end\n".write(to: url, atomically: true, encoding: .utf8)
        defer { removeCoreTestTemporaryDirectory(url) }

        let appState = AppState()
        appState.spiceSource = "* unsaved edits"
        try appState.loadSPICEFile(url: url)

        #expect(!appState.isNetlistDirty)
        #expect(appState.spiceSource == "* loaded netlist\n.end\n")

        appState.spiceSource += "* more"
        #expect(appState.isNetlistDirty)
    }

    @Test func clearSPICEFileClearsSelectionAndDirtyBaseline() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dirty-test-\(UUID().uuidString).cir")
        try "* loaded netlist\n.end\n".write(to: url, atomically: true, encoding: .utf8)
        defer { removeCoreTestTemporaryDirectory(url) }

        let appState = AppState()
        try appState.loadSPICEFile(url: url)
        appState.spiceSource += "* unsaved"
        appState.netlistInfo = NetlistInfo(
            title: nil,
            components: [],
            nodes: [],
            analyses: [],
            models: [],
            diagnostics: [],
            hasErrors: false
        )

        appState.clearSPICEFile()

        #expect(appState.spiceSource.isEmpty)
        #expect(appState.lastSavedSpiceSource.isEmpty)
        #expect(appState.spiceFileName == nil)
        #expect(appState.selectedFileURL == nil)
        #expect(appState.netlistInfo == nil)
        #expect(!appState.isNetlistDirty)
    }

    @Test func saveSPICEFileResetsDirtyBaseline() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dirty-test-\(UUID().uuidString).cir")
        try "* original\n".write(to: url, atomically: true, encoding: .utf8)
        defer { removeCoreTestTemporaryDirectory(url) }

        let appState = AppState()
        try appState.loadSPICEFile(url: url)
        appState.spiceSource = "* changed\n"
        #expect(appState.isNetlistDirty)

        try appState.saveSPICEFile()
        #expect(!appState.isNetlistDirty)
        #expect(try String(contentsOf: url, encoding: .utf8) == "* changed\n")
    }

    // MARK: - Schematic dirty (StudioSession)

    @Test func emptyNeverSavedSchematicIsNotDirty() {
        let project = StudioSession()
        #expect(!project.isSchematicDirty)
    }

    @Test func neverSavedSchematicWithContentIsDirty() {
        let project = StudioSession()
        project.schematicViewModel.document.components.append(
            PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero)
        )
        #expect(project.isSchematicDirty)
    }

    @Test func markSchematicSavedClearsDirty() {
        let project = StudioSession()
        project.schematicViewModel.document.components.append(
            PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero)
        )
        project.markSchematicSaved()
        #expect(!project.isSchematicDirty)

        project.schematicViewModel.document.components.append(
            PlacedComponent(deviceKindID: "vsource", name: "V1", position: CGPoint(x: 100, y: 0))
        )
        #expect(project.isSchematicDirty)
    }
}
