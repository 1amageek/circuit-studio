import SwiftUI
import CircuitStudioCore
import SchematicEditor
import LayoutEditor

/// Left-sidebar pane composed of an Xcode-style tab bar and the active navigator's content.
struct NavigatorPane: View {
    @Bindable var appState: AppState
    let services: ServiceContainer
    @Bindable var project: StudioSession

    var body: some View {
        VStack(spacing: 0) {
            PaneTabBar(
                selection: $appState.navigatorTab,
                items: Self.tabItems
            )
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.navigatorTab {
        case .project:
            ProjectNavigatorView(
                appState: appState,
                fileSystemService: services.fileSystemService
            )
        case .cells:
            CellsNavigatorView(appState: appState, project: project)
        case .schematic:
            SchematicNavigatorView(appState: appState, viewModel: project.schematicViewModel)
        case .layout:
            LayoutNavigatorView(appState: appState, viewModel: project.layoutViewModel)
        case .issues:
            IssuesNavigatorView(appState: appState, project: project)
        case .simulation:
            SimulationNavigatorView(appState: appState)
        }
    }

    private static let tabItems: [PaneTabItem<NavigatorTab>] = [
        .init(.project, systemImage: "folder", help: "Project"),
        .init(.cells, systemImage: "square.stack.3d.up", help: "Cells"),
        .init(.schematic, systemImage: "square.grid.3x3", help: "Schematic"),
        .init(.layout, systemImage: "square.dashed", help: "Layout"),
        .init(.issues, systemImage: "exclamationmark.triangle", help: "Issues"),
        .init(.simulation, systemImage: "waveform.path.ecg", help: "Simulation"),
    ]
}
