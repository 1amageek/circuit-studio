import SwiftUI
import CircuitStudioCore

/// Names and creates a new design cell — the "New File" gesture of the
/// project-as-cell-library model. Validates the name live against the same
/// rules the session enforces, then adds the cell, makes it active, and opens
/// the schematic editor on it. The session's `addCell` remains the
/// authoritative gate; this view's inline validation is advisory feedback.
struct NewCellSheet: View {
    @Bindable var appState: AppState
    @Bindable var project: StudioSession
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Cell")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Cell name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if validation == nil { create() } }
                validationLabel
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(validation != nil)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    @ViewBuilder
    private var validationLabel: some View {
        if let validation {
            Text(validation)
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Text("Letters, digits, and underscores; must start with a letter.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Advisory message mirroring the session's `addCell` guards, or nil when
    /// the name is acceptable. An empty field reads as "not yet valid" without
    /// flagging an error the user has not had a chance to make.
    private var validation: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return " "
        }
        if !CellInterface.isValidSPICEName(trimmed) {
            return StudioSessionError.invalidCellName(trimmed).localizedDescription
        }
        if project.cells.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            return StudioSessionError.duplicateCellName(trimmed).localizedDescription
        }
        return nil
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try project.addCell(named: trimmed)
            appState.workspace = .schematicCapture
            appState.schematicMode = .visual
            appState.navigatorTab = .schematic
            appState.log("Created cell '\(trimmed)'", kind: .success)
            dismiss()
        } catch {
            appState.log("Could not create cell: \(error.localizedDescription)", kind: .error)
        }
    }
}
