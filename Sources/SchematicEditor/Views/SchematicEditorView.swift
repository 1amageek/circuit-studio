import SwiftUI

/// Composite view combining the schematic canvas with a floating component palette.
public struct SchematicEditorView: View {
    @Bindable var viewModel: SchematicViewModel

    public init(viewModel: SchematicViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            SchematicCanvas(viewModel: viewModel)
                .overlay(alignment: .topLeading) {
                    ComponentPaletteOverlay(viewModel: viewModel)
                }
                .overlay(alignment: .bottomTrailing) {
                    MiniMapView(viewModel: viewModel)
                        .padding(12)
                }

            if !viewModel.diagnostics.isEmpty {
                DiagnosticsBar(diagnostics: viewModel.diagnostics) { componentID in
                    if let id = componentID {
                        viewModel.select(id)
                    }
                }
            }
        }
        .onChange(of: viewModel.document.components.count) {
            viewModel.validateDocument()
            viewModel.recomputeTerminals()
        }
        .onChange(of: viewModel.document.wires.count) {
            viewModel.validateDocument()
            viewModel.recomputeTerminals()
        }
        .onChange(of: viewModel.document.labels.count) {
            viewModel.validateDocument()
        }
        .onChange(of: viewModel.document.probes.count) {
            viewModel.recomputeTerminals()
        }
        .onAppear {
            viewModel.validateDocument()
            viewModel.recomputeTerminals()
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
