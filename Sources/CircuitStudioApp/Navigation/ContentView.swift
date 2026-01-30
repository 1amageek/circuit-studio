import SwiftUI
import CircuitStudioCore
import SchematicEditor
import WaveformViewer

/// Main content area with macOS HIG-compliant layout:
/// Sidebar (navigator) | Editor Area | Inspector
public struct ContentView: View {
    @Bindable var appState: AppState
    let services: ServiceContainer
    @Bindable var waveformViewModel: WaveformViewModel
    @Bindable var schematicViewModel: SchematicViewModel

    public init(
        appState: AppState,
        services: ServiceContainer,
        waveformViewModel: WaveformViewModel,
        schematicViewModel: SchematicViewModel
    ) {
        self.appState = appState
        self.services = services
        self.waveformViewModel = waveformViewModel
        self.schematicViewModel = schematicViewModel
    }

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            VStack(spacing: 0) {
                detailView
                errorBanner
            }
            .toolbar {
                toolbarContent
            }
        }
        .inspector(isPresented: $appState.showInspector) {
            inspectorContent
                .inspectorColumnWidth(min: 200, ideal: 280, max: 400)
        }
        .onChange(of: appState.simulationResult?.id) { _, resultID in
            if resultID != nil, let waveform = appState.simulationResult?.waveform {
                waveformViewModel.load(waveform: waveform)
                appState.activeEditor = .waveform
            }
        }
    }

    // MARK: - Sidebar (Project Navigator only)

    private var sidebarContent: some View {
        ProjectNavigatorView(
            appState: appState,
            fileSystemService: services.fileSystemService
        )
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        switch appState.activeEditor {
        case .netlist:
            NetlistEditorView(appState: appState)
        case .schematic:
            SchematicEditorView(viewModel: schematicViewModel)
        case .waveform:
            HSplitView {
                WaveformChartView(viewModel: waveformViewModel)
                    .frame(minWidth: 400)
                TraceListView(viewModel: waveformViewModel)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
            }
        }
    }

    // MARK: - Error Banner

    @ViewBuilder
    private var errorBanner: some View {
        if let error = appState.simulationError {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Spacer()
                Button {
                    appState.simulationError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.red.opacity(0.1))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Editor mode picker (center)
        ToolbarItem(placement: .principal) {
            Picker("Editor", selection: $appState.activeEditor) {
                Label("Netlist", systemImage: "doc.text")
                    .tag(EditorMode.netlist)
                Label("Schematic", systemImage: "square.grid.3x3")
                    .tag(EditorMode.schematic)
                Label("Waveform", systemImage: "waveform.path")
                    .tag(EditorMode.waveform)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
        }

        // Global actions
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task {
                    await appState.runSimulation(service: services.simulationService)
                }
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .disabled(appState.spiceSource.isEmpty || appState.isSimulating)
            .keyboardShortcut("r", modifiers: .command)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                openFile()
            } label: {
                Label("Open File", systemImage: "doc.badge.plus")
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                openFolder()
            } label: {
                Label("Open Folder", systemImage: "folder.badge.plus")
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        // Context-dependent toolbar items
        switch appState.activeEditor {
        case .schematic:
            schematicToolbarItems
        case .waveform:
            WaveformToolbarContent(viewModel: waveformViewModel)
        case .netlist:
            ToolbarItem(placement: .status) {
                if let fileName = appState.spiceFileName {
                    Text(fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        // Inspector toggle (trailing)
        ToolbarItem {
            Button {
                appState.showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
        }

        // Progress indicator
        if appState.isSimulating {
            ToolbarItem {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ToolbarContentBuilder
    private var schematicToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .secondaryAction) {
            Button {
                schematicViewModel.tool = .select
            } label: {
                Label("Select", systemImage: "arrow.uturn.left")
            }
            .help("Select tool")

            Button {
                schematicViewModel.tool = .wire
            } label: {
                Label("Wire", systemImage: "line.diagonal")
            }
            .help("Wire tool")

            Button {
                schematicViewModel.tool = .label
            } label: {
                Label("Net Label", systemImage: "tag")
            }
            .help("Net label tool")
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorContent: some View {
        switch appState.activeEditor {
        case .schematic:
            PropertyInspector(viewModel: schematicViewModel)
        case .waveform:
            TraceListView(viewModel: waveformViewModel)
        default:
            Text("No inspector available")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - File Open

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "cir")!,
            .init(filenameExtension: "spice")!,
            .plainText,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try appState.loadSPICEFile(url: url)
            } catch {
                appState.simulationError = "Failed to load file: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Folder Open

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let root = try services.fileSystemService.scanDirectory(at: url)
                appState.projectRootURL = url
                appState.projectRoot = root
            } catch {
                appState.simulationError = "Failed to open folder: \(error.localizedDescription)"
            }
        }
    }
}

/// Simple text editor view for SPICE netlist source.
public struct NetlistEditorView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        TextEditor(text: $appState.spiceSource)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(8)
    }
}

// MARK: - Previews

#Preview("Content — Netlist") {
    let state = AppState()
    state.activeEditor = .netlist
    state.spiceSource = """
    * RC Lowpass Filter
    V1 in 0 5
    R1 in out 1k
    C1 out 0 1n
    .tran 0.1u 20u
    .end
    """
    state.spiceFileName = "rc_lowpass.cir"
    return ContentView(
        appState: state,
        services: ServiceContainer(),
        waveformViewModel: WaveformViewModel(),
        schematicViewModel: SchematicViewModel()
    )
    .frame(width: 1200, height: 800)
}

#Preview("Content — Schematic") {
    let state = AppState()
    state.activeEditor = .schematic
    return ContentView(
        appState: state,
        services: ServiceContainer(),
        waveformViewModel: WaveformViewModel(),
        schematicViewModel: SchematicViewModel()
    )
    .frame(width: 1200, height: 800)
}

#Preview("Netlist Editor") {
    let state = AppState()
    state.spiceSource = """
    * Simple RC
    V1 in 0 DC 5
    R1 in out 1k
    C1 out 0 1n
    .end
    """
    state.spiceFileName = "example.cir"
    return NetlistEditorView(appState: state)
        .frame(width: 1200, height: 800)
}

#Preview("Netlist Editor — Empty") {
    NetlistEditorView(appState: AppState())
        .frame(width: 1200, height: 800)
}
