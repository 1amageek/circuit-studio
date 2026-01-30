import SwiftUI

/// Floating button overlay for the schematic canvas that opens
/// a Keynote-style popover with component categories and a device grid.
public struct ComponentPaletteOverlay: View {
    @Bindable var viewModel: SchematicViewModel
    @State private var showPopover: Bool = false

    public init(viewModel: SchematicViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            ComponentPalette(viewModel: viewModel) {
                showPopover = false
            }
        }
        .padding(12)
    }
}

#Preview("Palette Overlay") {
    ZStack(alignment: .topLeading) {
        Color(nsColor: .controlBackgroundColor)
        ComponentPaletteOverlay(viewModel: SchematicPreview.emptyViewModel())
    }
    .frame(width: 600, height: 400)
}
