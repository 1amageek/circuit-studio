import SwiftUI

/// Edit-menu operations published by whichever editor currently holds key
/// focus (schematic canvas, layout canvas). A nil closure means the focused
/// editor does not support that operation; when no editor publishes at all
/// (e.g. a text view has focus) the menu falls back to the responder chain
/// so native text editing keeps working.
struct EditorCommands {
    var canUndo: Bool = false
    var canRedo: Bool = false
    var undo: (() -> Void)?
    var redo: (() -> Void)?
    var cut: (() -> Void)?
    var copy: (() -> Void)?
    var paste: (() -> Void)?
    var duplicate: (() -> Void)?
    var delete: (() -> Void)?
    var selectAll: (() -> Void)?
}

private struct EditorCommandsFocusedKey: FocusedValueKey {
    typealias Value = EditorCommands
}

extension FocusedValues {
    var editorCommands: EditorCommands? {
        get { self[EditorCommandsFocusedKey.self] }
        set { self[EditorCommandsFocusedKey.self] = newValue }
    }
}
