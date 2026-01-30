import SwiftUI

/// Composite view combining the schematic canvas with a floating component palette.
public struct SchematicEditorView: View {
    @Bindable var viewModel: SchematicViewModel

    public init(viewModel: SchematicViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        SchematicCanvas(viewModel: viewModel)
            .overlay(alignment: .topLeading) {
                ComponentPaletteOverlay(viewModel: viewModel)
            }
            .overlay(alignment: .bottomTrailing) {
                MiniMapView(viewModel: viewModel)
                    .padding(12)
            }
    }
}

#Preview("Schematic Editor") {
    SchematicEditorView(viewModel: SchematicPreview.emptyViewModel())
        .frame(width: 800, height: 600)
}

#Preview("Schematic Editor — With Components") {
    SchematicEditorView(viewModel: SchematicPreview.voltageDividerViewModel())
        .frame(width: 800, height: 600)
}
