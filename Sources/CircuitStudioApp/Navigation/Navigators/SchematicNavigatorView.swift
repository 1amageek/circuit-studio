import SwiftUI
import CircuitStudioCore
import SchematicEditor

/// Outline of the active schematic — components grouped by device prefix and net labels.
/// Selecting a row routes the schematic editor's selection to that element.
struct SchematicNavigatorView: View {
    @Bindable var viewModel: SchematicViewModel

    var body: some View {
        if viewModel.document.components.isEmpty
            && viewModel.document.labels.isEmpty
            && viewModel.document.wires.isEmpty {
            ContentUnavailableView(
                "No Schematic",
                systemImage: "square.grid.3x3",
                description: Text("Place components in the Schematic editor to see them listed here.")
            )
        } else {
            outline
        }
    }

    private var outline: some View {
        List(selection: selectionBinding) {
            componentsSection
            labelsSection
            wiresSection
        }
        .listStyle(.sidebar)
    }

    // MARK: - Sections

    @ViewBuilder
    private var componentsSection: some View {
        let groups = groupedComponents
        if !groups.isEmpty {
            Section("Components") {
                ForEach(groups, id: \.title) { group in
                    DisclosureGroup {
                        ForEach(group.items, id: \.id) { component in
                            componentRow(component)
                                .tag(component.id)
                        }
                    } label: {
                        HStack {
                            Text(group.title)
                                .font(.system(.body))
                            Spacer()
                            Text("\(group.items.count)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var labelsSection: some View {
        if !viewModel.document.labels.isEmpty {
            Section("Net Labels") {
                ForEach(viewModel.document.labels) { label in
                    Label {
                        Text(label.name.isEmpty ? "(unnamed)" : label.name)
                            .font(.system(.body, design: .monospaced))
                    } icon: {
                        Image(systemName: "tag")
                            .foregroundStyle(.orange)
                    }
                    .tag(label.id)
                }
            }
        }
    }

    @ViewBuilder
    private var wiresSection: some View {
        let named = viewModel.document.wires.filter { ($0.netName ?? "").isEmpty == false }
        if !named.isEmpty {
            Section("Named Wires") {
                ForEach(named) { wire in
                    Label {
                        Text(wire.netName ?? "")
                            .font(.system(.body, design: .monospaced))
                    } icon: {
                        Image(systemName: "line.diagonal")
                            .foregroundStyle(.green)
                    }
                    .tag(wire.id)
                }
            }
        }
    }

    private func componentRow(_ component: PlacedComponent) -> some View {
        let kind = viewModel.catalog.device(for: component.deviceKindID)
        return Label {
            HStack {
                Text(component.name)
                    .font(.system(.body, design: .monospaced))
                Spacer()
                if let kind {
                    Text(kind.displayName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } icon: {
            Image(systemName: "rectangle.connected.to.line.below")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private struct Group {
        let title: String
        let items: [PlacedComponent]
    }

    private var groupedComponents: [Group] {
        let dict = Dictionary(grouping: viewModel.document.components) { component in
            viewModel.catalog.device(for: component.deviceKindID)?.displayName
                ?? component.deviceKindID
        }
        return dict
            .map { Group(title: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.title < $1.title }
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.document.selection.first },
            set: { id in
                if let id {
                    viewModel.select(id)
                } else {
                    viewModel.clearSelection()
                }
            }
        )
    }
}
