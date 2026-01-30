import CircuitStudioCore

/// Snapshot-based undo/redo stack for SchematicDocument.
///
/// Each entry is a full copy of the document state.
/// SchematicDocument is a value type (struct) so copies are CoW-efficient.
public struct UndoStack: Sendable {
    private var undoEntries: [SchematicDocument] = []
    private var redoEntries: [SchematicDocument] = []
    private let maxDepth: Int

    public init(maxDepth: Int = 100) {
        self.maxDepth = maxDepth
    }

    public var canUndo: Bool { !undoEntries.isEmpty }
    public var canRedo: Bool { !redoEntries.isEmpty }

    /// Record the current document state before a mutation.
    public mutating func record(_ document: SchematicDocument) {
        undoEntries.append(document)
        if undoEntries.count > maxDepth {
            undoEntries.removeFirst()
        }
        redoEntries.removeAll()
    }

    /// Undo: push current state onto redo stack, pop and return previous state.
    public mutating func undo(current: SchematicDocument) -> SchematicDocument? {
        guard let previous = undoEntries.popLast() else { return nil }
        redoEntries.append(current)
        return previous
    }

    /// Redo: push current state onto undo stack, pop and return next state.
    public mutating func redo(current: SchematicDocument) -> SchematicDocument? {
        guard let next = redoEntries.popLast() else { return nil }
        undoEntries.append(current)
        return next
    }
}
