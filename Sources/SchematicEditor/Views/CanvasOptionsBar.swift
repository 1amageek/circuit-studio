import SwiftUI

/// Floating canvas options bar: grid visibility, snap-to-grid, and grid
/// spacing. Lives in the bottom-leading corner of the schematic canvas.
public struct CanvasOptionsBar: View {
    @Bindable var viewModel: SchematicViewModel

    private static let gridSizes: [CGFloat] = [5, 10, 20, 25, 50]

    public init(viewModel: SchematicViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 2) {
            Button {
                viewModel.showsGrid.toggle()
            } label: {
                Image(systemName: "grid")
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
                    .foregroundStyle(viewModel.showsGrid ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(viewModel.showsGrid ? "Hide Grid" : "Show Grid")

            Button {
                viewModel.snapsToGrid.toggle()
            } label: {
                Image(systemName: "dot.scope")
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
                    .foregroundStyle(viewModel.snapsToGrid ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(viewModel.snapsToGrid ? "Disable Snap to Grid" : "Snap to Grid")

            Divider()
                .frame(height: 14)

            Menu {
                Picker("Grid Spacing", selection: $viewModel.gridSize) {
                    ForEach(Self.gridSizes, id: \.self) { size in
                        Text("\(Int(size)) pt").tag(size)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Text("\(Int(viewModel.gridSize))")
                    .font(.caption.monospacedDigit())
                    .frame(height: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Grid Spacing")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

#Preview("Canvas Options") {
    ZStack(alignment: .bottomLeading) {
        Color(nsColor: .controlBackgroundColor)
        CanvasOptionsBar(viewModel: SchematicPreview.emptyViewModel())
            .padding(12)
    }
    .frame(width: 400, height: 120)
}
