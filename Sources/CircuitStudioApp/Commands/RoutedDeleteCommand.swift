import LayoutEditor
import SchematicEditor

/// Deletes the visible editor's selection; returns whether anything was
/// deleted so the caller can decide between swallowing the key event and
/// letting it propagate (and beep).
typealias RoutedDeleteAction = @MainActor () -> Bool

/// Resolves the Delete verb for the workspace's visible canvas when no
/// editor subtree holds key focus. While an editor holds focus its canvas
/// handles Delete itself — including canvas-internal behavior such as
/// retracting the last drawing vertex — so this resolver must stand down.
@MainActor
enum RoutedDeleteCommand {

    static func resolve(
        workspace: Workspace,
        schematicMode: SchematicMode,
        editorHasKeyFocus: Bool,
        schematic: SchematicViewModel,
        layout: LayoutEditorViewModel
    ) -> RoutedDeleteAction? {
        guard !editorHasKeyFocus else { return nil }

        switch workspace {
        case .schematicCapture:
            guard schematicMode == .visual else { return nil }
            return {
                guard !schematic.document.selection.isEmpty else { return false }
                schematic.recordForUndo()
                schematic.deleteSelection()
                return true
            }
        case .layout:
            return {
                let hasSelection =
                    !layout.selectedShapeIDs.isEmpty || layout.selectedInstanceID != nil
                guard hasSelection else { return false }
                layout.deleteSelection()
                return true
            }
        case .integration, .review:
            // Integration shows both canvases side by side; without key focus
            // the delete target is ambiguous, so keep focus-driven dispatch.
            return nil
        }
    }
}
