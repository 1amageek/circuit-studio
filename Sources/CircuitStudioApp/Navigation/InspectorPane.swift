import SwiftUI

/// Right-sidebar pane composed of an Xcode-style tab bar and the active inspector content.
struct InspectorPane: View {
    @Bindable var appState: AppState
    let services: ServiceContainer
    @Bindable var project: StudioSession

    var body: some View {
        VStack(spacing: 0) {
            PaneTabBar(
                selection: $appState.inspectorTab,
                items: Self.tabItems
            )
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.inspectorTab {
        case .properties:
            PropertiesInspectorTab(appState: appState, project: project)
        case .process:
            ProcessInspectorTab(appState: appState)
        case .analysis:
            AnalysisInspectorTab(
                appState: appState,
                project: project,
                catalog: services.catalog
            )
        case .waveform:
            WaveformInspectorTab(viewModel: project.waveformViewModel)
        }
    }

    private static let tabItems: [PaneTabItem<InspectorTab>] = [
        .init(.properties, systemImage: "slider.horizontal.3", help: "Properties"),
        .init(.process, systemImage: "cpu", help: "Process"),
        .init(.analysis, systemImage: "function", help: "Analysis"),
        .init(.waveform, systemImage: "waveform", help: "Waveform"),
    ]
}
