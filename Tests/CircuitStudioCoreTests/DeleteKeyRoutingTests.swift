import AppKit
import CircuitStudioCore
import Foundation
import LayoutCore
import LayoutEditor
import SchematicEditor
import Testing

@testable import CircuitStudioApp

@Suite("Delete Key Gate")
struct DeleteKeyGateTests {

    @Test("Plain Delete with no modifiers routes")
    func plainDeleteRoutes() {
        #expect(
            DeleteKeyGate.shouldRoute(
                keyCode: DeleteKeyGate.deleteKeyCode,
                modifierFlags: [],
                firstResponderEditsText: false
            )
        )
    }

    @Test("Forward Delete routes even with the function flag the key carries")
    func forwardDeleteRoutesWithFunctionFlag() {
        #expect(
            DeleteKeyGate.shouldRoute(
                keyCode: DeleteKeyGate.forwardDeleteKeyCode,
                modifierFlags: [.function],
                firstResponderEditsText: false
            )
        )
    }

    @Test("Shift+Delete still routes")
    func shiftDeleteRoutes() {
        #expect(
            DeleteKeyGate.shouldRoute(
                keyCode: DeleteKeyGate.deleteKeyCode,
                modifierFlags: [.shift],
                firstResponderEditsText: false
            )
        )
    }

    @Test(
        "Command, Control and Option chords never route",
        arguments: [
            NSEvent.ModifierFlags.command,
            NSEvent.ModifierFlags.control,
            NSEvent.ModifierFlags.option,
        ]
    )
    func modifierChordsDoNotRoute(modifier: NSEvent.ModifierFlags) {
        #expect(
            !DeleteKeyGate.shouldRoute(
                keyCode: DeleteKeyGate.deleteKeyCode,
                modifierFlags: modifier,
                firstResponderEditsText: false
            )
        )
    }

    @Test("Editable text first responder always wins")
    func editableTextWins() {
        #expect(
            !DeleteKeyGate.shouldRoute(
                keyCode: DeleteKeyGate.deleteKeyCode,
                modifierFlags: [],
                firstResponderEditsText: true
            )
        )
    }

    @Test("Non-delete keys never route")
    func otherKeysDoNotRoute() {
        // keyCode 0 is the 'a' key.
        #expect(
            !DeleteKeyGate.shouldRoute(
                keyCode: 0,
                modifierFlags: [],
                firstResponderEditsText: false
            )
        )
    }
}

@Suite("Routed Delete Command")
@MainActor
struct RoutedDeleteCommandTests {

    @Test("An editor holding key focus suppresses routing for every workspace")
    func editorFocusSuppressesRouting() {
        let schematic = SchematicViewModel()
        let layout = LayoutEditorViewModel()
        for workspace in [Workspace.schematicCapture, .layout, .integration, .review] {
            let action = RoutedDeleteCommand.resolve(
                workspace: workspace,
                schematicMode: .visual,
                editorHasKeyFocus: true,
                schematic: schematic,
                layout: layout
            )
            #expect(action == nil, "Focused editor must own Delete in \(workspace)")
        }
    }

    @Test("Schematic visual workspace deletes the selection and records undo")
    func schematicDeleteDeletesSelectionWithUndo() throws {
        let schematic = SchematicViewModel()
        let component = PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero)
        schematic.document.components.append(component)
        schematic.document.selection = [component.id]

        let action = try #require(
            RoutedDeleteCommand.resolve(
                workspace: .schematicCapture,
                schematicMode: .visual,
                editorHasKeyFocus: false,
                schematic: schematic,
                layout: LayoutEditorViewModel()
            )
        )

        #expect(action())
        #expect(schematic.document.components.isEmpty)
        #expect(schematic.canUndo)

        schematic.undo()
        #expect(schematic.document.components.count == 1)
    }

    @Test("An empty schematic selection reports unhandled so the event propagates")
    func emptySchematicSelectionReportsUnhandled() throws {
        let schematic = SchematicViewModel()
        schematic.document.components.append(
            PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero)
        )

        let action = try #require(
            RoutedDeleteCommand.resolve(
                workspace: .schematicCapture,
                schematicMode: .visual,
                editorHasKeyFocus: false,
                schematic: schematic,
                layout: LayoutEditorViewModel()
            )
        )

        #expect(!action())
        #expect(schematic.document.components.count == 1)
    }

    @Test("Netlist mode never routes: the text editor owns Delete")
    func netlistModeDoesNotRoute() {
        let action = RoutedDeleteCommand.resolve(
            workspace: .schematicCapture,
            schematicMode: .netlist,
            editorHasKeyFocus: false,
            schematic: SchematicViewModel(),
            layout: LayoutEditorViewModel()
        )
        #expect(action == nil)
    }

    @Test("Layout workspace deletes the selected shape")
    func layoutDeleteDeletesSelectedShape() throws {
        let layout = LayoutEditorViewModel()
        layout.addRectangle(
            from: LayoutPoint(x: 0, y: 0),
            to: LayoutPoint(x: 100, y: 100)
        )
        let cellID = try #require(layout.editTargetCellID)
        let shape = try #require(layout.editor.document.cell(withID: cellID)?.shapes.first)
        layout.selectedShapeIDs = [shape.id]

        let action = try #require(
            RoutedDeleteCommand.resolve(
                workspace: .layout,
                schematicMode: .visual,
                editorHasKeyFocus: false,
                schematic: SchematicViewModel(),
                layout: layout
            )
        )

        #expect(action())
        #expect(layout.editor.document.cell(withID: cellID)?.shapes.isEmpty == true)
        #expect(layout.selectedShapeIDs.isEmpty)
    }

    @Test("An empty layout selection reports unhandled")
    func emptyLayoutSelectionReportsUnhandled() throws {
        let action = try #require(
            RoutedDeleteCommand.resolve(
                workspace: .layout,
                schematicMode: .visual,
                editorHasKeyFocus: false,
                schematic: SchematicViewModel(),
                layout: LayoutEditorViewModel()
            )
        )
        #expect(!action())
    }

    @Test("Integration and review workspaces keep focus-driven dispatch")
    func ambiguousWorkspacesDoNotRoute() {
        for workspace in [Workspace.integration, .review] {
            let action = RoutedDeleteCommand.resolve(
                workspace: workspace,
                schematicMode: .visual,
                editorHasKeyFocus: false,
                schematic: SchematicViewModel(),
                layout: LayoutEditorViewModel()
            )
            #expect(action == nil, "No unambiguous canvas target in \(workspace)")
        }
    }
}

/// The router only works if ContentView actually installs it; nothing
/// in-process can observe a missing `.background` (key dispatch needs a
/// running NSApplication event loop), so the wiring is pinned at the
/// source level like the canvas key-order tests.
@Suite("Delete Key Router Wiring")
struct DeleteKeyRouterWiringTests {

    @Test func contentViewInstallsTheRouter() throws {
        let contentViewSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CircuitStudioCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources/CircuitStudioApp/Navigation/ContentView.swift")
        let source = try String(contentsOf: contentViewSource, encoding: .utf8)

        #expect(
            source.contains(".background(DeleteKeyRouterView(action: routedDeleteAction))"),
            "ContentView must install the window-level Delete-key router; without it Delete beeps whenever focus sits outside the canvas"
        )
    }
}
