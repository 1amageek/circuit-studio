import SwiftUI

/// Floating palette overlay for the schematic canvas.
/// Displays component and tool selection with collapse/expand support.
public struct ComponentPaletteOverlay: View {
    @Bindable var viewModel: SchematicViewModel
    @State private var isExpanded: Bool = true

    public init(viewModel: SchematicViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if isExpanded {
            expandedContent
        } else {
            collapsedContent
        }
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Components")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.up.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ComponentPalette(viewModel: viewModel)
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 200)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .padding(12)
    }

    private var collapsedContent: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = true
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .frame(width: 36, height: 36)
        .background(.ultraThinMaterial)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .padding(12)
    }
}

#Preview("Palette Overlay — Expanded") {
    ZStack(alignment: .topLeading) {
        Color(nsColor: .controlBackgroundColor)
        ComponentPaletteOverlay(viewModel: SchematicPreview.emptyViewModel())
    }
    .frame(width: 600, height: 400)
}

#Preview("Palette Overlay — Collapsed") {
    ZStack(alignment: .topLeading) {
        Color(nsColor: .controlBackgroundColor)
        ComponentPaletteOverlay(viewModel: SchematicPreview.emptyViewModel())
    }
    .frame(width: 600, height: 400)
}
