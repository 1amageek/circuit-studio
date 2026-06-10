import SwiftUI
import SchematicEditor
import LayoutEditor

/// Context-aware Properties inspector. Renders the right inspector based on the active workspace and mode.
struct PropertiesInspectorTab: View {
    @Bindable var appState: AppState
    @Bindable var project: StudioSession

    var body: some View {
        switch appState.workspace {
        case .schematicCapture:
            switch appState.schematicMode {
            case .visual:
                PropertyInspector(viewModel: project.schematicViewModel)
            case .netlist:
                NetlistInspectorBody(appState: appState)
            }
        case .layout:
            LayoutInspectorView(viewModel: project.layoutViewModel)
        case .integration:
            LayoutInspectorView(viewModel: project.layoutViewModel)
        }
    }
}
