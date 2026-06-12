import SwiftUI
import AppKit

/// Replaces the standard Edit menu groups so the canvas editors participate
/// in Undo/Redo and pasteboard commands. Each item prefers the focused
/// editor's published operation and otherwise forwards the corresponding
/// selector down the responder chain, which keeps native text editing
/// (netlist editor, inspector fields) fully functional.
struct EditMenuCommands: Commands {
    @FocusedValue(\.editorCommands) private var editor: EditorCommands?

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                perform(editor?.undo, fallback: Selector(("undo:")))
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(isDisabled(editor?.undo, enabled: editor?.canUndo))

            Button("Redo") {
                perform(editor?.redo, fallback: Selector(("redo:")))
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(isDisabled(editor?.redo, enabled: editor?.canRedo))
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                perform(editor?.cut, fallback: #selector(NSText.cut(_:)))
            }
            .keyboardShortcut("x", modifiers: .command)
            .disabled(isDisabled(editor?.cut))

            Button("Copy") {
                perform(editor?.copy, fallback: #selector(NSText.copy(_:)))
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(isDisabled(editor?.copy))

            Button("Paste") {
                perform(editor?.paste, fallback: #selector(NSText.paste(_:)))
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(isDisabled(editor?.paste))

            Button("Duplicate") {
                perform(editor?.duplicate, fallback: nil)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(editor?.duplicate == nil)

            Button("Delete") {
                perform(editor?.delete, fallback: #selector(NSText.delete(_:)))
            }
            .disabled(isDisabled(editor?.delete))

            Divider()

            Button("Select All") {
                perform(editor?.selectAll, fallback: #selector(NSText.selectAll(_:)))
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(isDisabled(editor?.selectAll))
        }
    }

    /// Runs the focused editor's operation, or forwards the selector down
    /// the responder chain when no editor publishes one.
    private func perform(_ operation: (() -> Void)?, fallback: Selector?) {
        if let operation {
            operation()
        } else if let fallback {
            NSApp.sendAction(fallback, to: nil, from: nil)
        }
    }

    /// A canvas editor that publishes commands but not this operation
    /// disables the item; with no editor focused the item stays enabled
    /// for the responder chain (text views validate it themselves).
    private func isDisabled(_ operation: (() -> Void)?, enabled: Bool? = nil) -> Bool {
        guard editor != nil else { return false }
        if operation == nil { return true }
        if let enabled { return !enabled }
        return false
    }
}
