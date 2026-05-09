import SwiftUI
import WaveformViewer

/// Bottom debug area with Xcode-style tab bar (Console / Waveform / Issues).
/// Visibility is driven by `appState.showDebugArea`; the active tab is `appState.debugAreaTab`.
struct DebugAreaPane: View {
    @Bindable var appState: AppState
    @Bindable var project: DesignProject

    var body: some View {
        VStack(spacing: 0) {
            PaneTabBar(
                selection: $appState.debugAreaTab,
                items: Self.tabItems,
                trailing: {
                    Button {
                        appState.showDebugArea = false
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Hide Debug Area")
                }
            )
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.debugAreaTab {
        case .console:
            SimulationConsoleView(appState: appState)
        case .waveform:
            WaveformResultView(viewModel: project.waveformViewModel)
        case .issues:
            IssuesNavigatorView(appState: appState, project: project)
        }
    }

    private static let tabItems: [PaneTabItem<DebugAreaTab>] = [
        .init(.console, systemImage: "terminal", help: "Console"),
        .init(.waveform, systemImage: "waveform", help: "Waveform"),
        .init(.issues, systemImage: "exclamationmark.triangle", help: "Issues"),
    ]
}
