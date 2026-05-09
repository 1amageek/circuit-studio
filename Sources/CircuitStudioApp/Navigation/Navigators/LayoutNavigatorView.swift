import SwiftUI
import LayoutCore
import LayoutEditor
import LayoutTech

/// Outline of the layout document — cell hierarchy + layers.
/// Selecting a cell opens it in the layout editor; toggling a layer hides/shows shapes.
struct LayoutNavigatorView: View {
    @Bindable var viewModel: LayoutEditorViewModel

    var body: some View {
        if viewModel.editor.document.cells.isEmpty {
            ContentUnavailableView(
                "No Layout",
                systemImage: "square.dashed",
                description: Text("Generate or open a layout to see the cell hierarchy here.")
            )
        } else {
            outline
        }
    }

    private var outline: some View {
        List {
            cellsSection
            layersSection
        }
        .listStyle(.sidebar)
    }

    // MARK: - Cells

    private var cellsSection: some View {
        Section("Cells") {
            ForEach(viewModel.allCells) { cell in
                cellRow(cell)
            }
        }
    }

    private func cellRow(_ cell: LayoutCell) -> some View {
        let isActive = cell.id == viewModel.activeCellID
        return Button {
            viewModel.openCell(cell.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isActive ? "square.dashed.inset.filled" : "square.dashed")
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                Text(cell.name)
                    .font(.system(.body))
                    .foregroundStyle(isActive ? Color.accentColor : .primary)
                Spacer()
                Text("\(cell.shapes.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Layers

    private var layersSection: some View {
        Section("Layers") {
            ForEach(viewModel.tech.layers, id: \.id) { layer in
                layerRow(layer)
            }
        }
    }

    private func layerRow(_ layer: LayoutLayerDefinition) -> some View {
        let isHidden = viewModel.hiddenLayers.contains(layer.id)
        let isActive = viewModel.activeLayer == layer.id
        return HStack(spacing: 6) {
            Button {
                if isHidden {
                    viewModel.hiddenLayers.remove(layer.id)
                } else {
                    viewModel.hiddenLayers.insert(layer.id)
                }
            } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .foregroundStyle(isHidden ? .tertiary : .secondary)
            }
            .buttonStyle(.plain)

            RoundedRectangle(cornerRadius: 2)
                .fill(layer.color.swiftUIColor)
                .frame(width: 14, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )

            Button {
                viewModel.activeLayer = layer.id
            } label: {
                Text(layer.displayName)
                    .font(.system(.body))
                    .foregroundStyle(isActive ? Color.accentColor : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private extension LayoutColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
