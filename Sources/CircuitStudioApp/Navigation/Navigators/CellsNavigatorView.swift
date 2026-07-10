import SwiftUI
import CircuitStudioCore

/// Library manager for the project's design cells — the primary navigation of
/// the new "project = cell library" model. Lists every cell, marks the
/// hierarchy root, and surfaces each cell's derived interface. Selecting a
/// cell makes it active, switching every editor pane to it; the context menu
/// re-roots the hierarchy or removes a cell, both through the session's typed
/// operations so protected cells (top, last, still-instantiated) report a
/// reason instead of silently failing.
struct CellsNavigatorView: View {
    @Bindable var appState: AppState
    @Bindable var project: StudioSession

    /// Cell awaiting delete confirmation — removing a cell discards its
    /// schematic and layout, so the gesture is confirmed first.
    @State private var cellPendingDeletion: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            cellList
        }
        .confirmationDialog(
            "Delete cell \(cellPendingDeletion ?? "")?",
            isPresented: deletionDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let name = cellPendingDeletion { delete(name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The cell's schematic and layout are removed from the project. This cannot be undone once you save.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 4) {
            Text("CELLS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(project.cells.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button {
                appState.isNewCellSheetPresented = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Cell (⌘N)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - List

    private var cellList: some View {
        List {
            ForEach(orderedCells) { workspace in
                Button {
                    activate(workspace.name)
                } label: {
                    cellRow(workspace)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        workspace.name == project.activeCellName
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear
                    )
                    .contextMenu { contextMenu(for: workspace) }
            }
        }
        .listStyle(.sidebar)
    }

    private func cellRow(_ workspace: CellWorkspace) -> some View {
        let summary = interfaceSummary(of: workspace)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: workspace.name == project.topCellName
                ? "square.stack.3d.up.fill"
                : "square.stack.3d.up")
                .foregroundStyle(workspace.name == project.topCellName ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(workspace.name)
                        .font(.system(.body, design: .monospaced))
                    if workspace.name == project.topCellName {
                        Text("TOP")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }
                    if workspace.hasUnsavedChanges {
                        Circle()
                            .fill(.tertiary)
                            .frame(width: 6, height: 6)
                            .help("Unsaved changes")
                    }
                }
                summaryLabel(summary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func summaryLabel(_ summary: InterfaceSummary) -> some View {
        switch summary {
        case .ports(let text):
            Text(text)
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .invalid(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .help(reason)
        }
    }

    @ViewBuilder
    private func contextMenu(for workspace: CellWorkspace) -> some View {
        Button("Edit") { activate(workspace.name) }
        Button("Set as Top Cell") { setTop(workspace.name) }
            .disabled(workspace.name == project.topCellName)
        Divider()
        Button("Delete", role: .destructive) {
            cellPendingDeletion = workspace.name
        }
        .disabled(project.cells.count <= 1 || workspace.name == project.topCellName)
    }

    // MARK: - Interface Summary

    /// Whether a cell's interface derives, and a short description for the row.
    /// A failure is shown as an explicit warning — it is not hidden — while
    /// the authoritative palette-exclusion reasons live in the Issues view.
    private enum InterfaceSummary {
        case ports(String)
        case invalid(String)
    }

    private func interfaceSummary(of workspace: CellWorkspace) -> InterfaceSummary {
        let document = workspace.schematicViewModel.document
        do {
            let interface = try CellInterface.derive(from: document)
            return .ports(portCountText(interface, componentCount: document.components.count))
        } catch {
            return .invalid(error.localizedDescription)
        }
    }

    private func portCountText(_ interface: CellInterface, componentCount: Int) -> String {
        let counts = Dictionary(grouping: interface.ports, by: \.direction)
            .mapValues(\.count)
        var parts: [String] = []
        for direction in PortDirection.allCases {
            guard let count = counts[direction], count > 0 else { continue }
            parts.append("\(count) \(directionLabel(direction))")
        }
        let portSummary = parts.isEmpty ? "no ports" : parts.joined(separator: " · ")
        return "\(portSummary) · \(componentCount) comp"
    }

    private func directionLabel(_ direction: PortDirection) -> String {
        switch direction {
        case .input: return "in"
        case .output: return "out"
        case .bidirectional: return "io"
        case .power: return "pwr"
        case .ground: return "gnd"
        }
    }

    // MARK: - Ordering

    /// Cells in a stable display order: the top cell first, then alphabetical.
    private var orderedCells: [CellWorkspace] {
        project.cells.sorted { lhs, rhs in
            if lhs.name == project.topCellName { return true }
            if rhs.name == project.topCellName { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Operations

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { cellPendingDeletion != nil },
            set: { presented in if !presented { cellPendingDeletion = nil } }
        )
    }

    private func activate(_ name: String) {
        do {
            try project.activateCell(named: name)
            appState.showSchematic(.visual)
        } catch {
            appState.log("Could not open cell '\(name)': \(error.localizedDescription)", kind: .error)
        }
    }

    private func setTop(_ name: String) {
        do {
            try project.setTopCell(named: name)
            appState.log("'\(name)' is now the top cell", kind: .info)
        } catch {
            appState.log("Could not set top cell: \(error.localizedDescription)", kind: .error)
        }
    }

    private func delete(_ name: String) {
        do {
            try project.removeCell(named: name)
            appState.log("Deleted cell '\(name)'", kind: .info)
        } catch {
            appState.log("Could not delete cell '\(name)': \(error.localizedDescription)", kind: .error)
        }
        cellPendingDeletion = nil
    }
}
