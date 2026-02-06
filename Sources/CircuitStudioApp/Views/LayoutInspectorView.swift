import SwiftUI
import LayoutEditor
import LayoutCore
import LayoutVerify

/// Inspector panel for the layout editor showing layer, selection, grid, and DRC info.
struct LayoutInspectorView: View {
    @Bindable var viewModel: LayoutEditorViewModel

    var body: some View {
        Form {
            layerSection
            selectionSection
            gridSection
            violationsSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Active Layer

    private var layerSection: some View {
        Section("Layer") {
            LabeledContent("Active") {
                Text(viewModel.activeLayer.name)
                    .font(.system(.body, design: .monospaced))
            }
            LabeledContent("Purpose") {
                Text(viewModel.activeLayer.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Selection

    @ViewBuilder
    private var selectionSection: some View {
        Section("Selection") {
            if viewModel.selectedShapeIDs.isEmpty {
                Text("No selection")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Shapes", value: "\(viewModel.selectedShapeIDs.count)")
            }
        }
    }

    // MARK: - Grid

    private var gridSection: some View {
        Section("Grid") {
            LabeledContent("Size") {
                Text(String(format: "%.3g \u{00B5}m", viewModel.gridSize))
                    .font(.system(.body, design: .monospaced))
            }
            LabeledContent("Zoom") {
                Text(String(format: "%.0f%%", viewModel.zoom * 100))
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    // MARK: - DRC Violations

    @ViewBuilder
    private var violationsSection: some View {
        Section("DRC") {
            if viewModel.violations.isEmpty {
                Text("No violations")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Violations", value: "\(viewModel.violations.count)")
                ForEach(viewModel.violations.prefix(20), id: \.id) { violation in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(violation.message)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
                if viewModel.violations.count > 20 {
                    Text("\(viewModel.violations.count - 20) more...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
