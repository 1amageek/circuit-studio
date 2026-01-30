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
                if appState.showConsole {
                    SimulationConsoleView(appState: appState)
                }
            }
            .toolbar {
                toolbarContent
            }
        }
        .inspector(isPresented: $appState.showInspector) {
            inspectorContent
                .inspectorColumnWidth(min: 200, ideal: 280, max: 400)
        }
        .onChange(of: appState.isSimulating) { wasSimulating, isSimulating in
            if wasSimulating, !isSimulating,
               appState.simulationError == nil,
               let waveform = appState.simulationResult?.waveform {
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
            WaveformResultView(viewModel: waveformViewModel)
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

        // Run / Stop
        ToolbarItem(placement: .primaryAction) {
            if appState.isSimulating {
                Button {
                    appState.cancelSimulation(service: services.simulationService)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .keyboardShortcut(".", modifiers: .command)
            } else {
                Button {
                    Task {
                        switch appState.activeEditor {
                        case .schematic:
                            await appState.runSchematicSimulation(
                                document: schematicViewModel.document,
                                analysisCommand: appState.selectedAnalysis,
                                generator: services.netlistGenerator,
                                service: services.simulationService
                            )
                        default:
                            await appState.runSimulation(service: services.simulationService)
                        }
                    }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(runButtonDisabled)
                .keyboardShortcut("r", modifiers: .command)
            }
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

        ToolbarItem(placement: .primaryAction) {
            Button {
                do {
                    try appState.saveSPICEFile()
                } catch {
                    appState.log("Save failed: \(error.localizedDescription)", kind: .error)
                }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(appState.spiceSource.isEmpty)
        }

        // Context-dependent toolbar items
        switch appState.activeEditor {
        case .schematic:
            schematicToolbarItems
        case .waveform:
            waveformToolbarItems
        case .netlist:
            ToolbarItem(placement: .status) {
                if let fileName = appState.spiceFileName {
                    Text(fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        // Simulation status
        ToolbarItem(placement: .status) {
            if let status = appState.simulationStatus {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }

        // Console toggle
        ToolbarItem {
            Button {
                appState.showConsole.toggle()
            } label: {
                Label("Console", systemImage: "terminal")
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
    }

    private var runButtonDisabled: Bool {
        if appState.isSimulating { return true }
        switch appState.activeEditor {
        case .schematic:
            return schematicViewModel.document.components.isEmpty
                || schematicViewModel.hasErrors
        default:
            return appState.spiceSource.isEmpty
        }
    }

    private var analysisLabel: String {
        switch appState.selectedAnalysis {
        case .op: return "OP"
        case .tran: return "Tran"
        case .ac: return "AC"
        case .dcSweep: return "DC"
        case .noise: return "Noise"
        case .tf: return "TF"
        case .pz: return "PZ"
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

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Operating Point") {
                    appState.selectedAnalysis = .op
                }
                Button("Transient (1ms)") {
                    appState.selectedAnalysis = .tran(TranSpec(stopTime: 1e-3, stepTime: 10e-6))
                }
                Button("AC Sweep (1Hz\u{2013}1MHz)") {
                    appState.selectedAnalysis = .ac(ACSpec(
                        scaleType: .decade, numberOfPoints: 20,
                        startFrequency: 1, stopFrequency: 1e6
                    ))
                }
            } label: {
                Label(analysisLabel, systemImage: "function")
            }
        }
    }

    @ToolbarContentBuilder
    private var waveformToolbarItems: some ToolbarContent {
        WaveformToolbarContent(viewModel: waveformViewModel)

        ToolbarItem(placement: .primaryAction) {
            Button {
                waveformViewModel.exportWaveform()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(waveformViewModel.waveformData == nil)
            .help("Export waveform data")
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorContent: some View {
        switch appState.activeEditor {
        case .schematic:
            PropertyInspector(viewModel: schematicViewModel)
        case .waveform:
            WaveformInspectorView(viewModel: waveformViewModel)
        case .netlist:
            NetlistInspectorView(appState: appState)
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

/// Inspector panel for the netlist editor showing file info and analysis settings.
private struct NetlistInspectorView: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            Section("File") {
                LabeledContent("Name", value: appState.spiceFileName ?? "Untitled")
                LabeledContent("Lines", value: "\(appState.spiceSource.components(separatedBy: "\n").count)")
            }
            Section("Analysis") {
                Picker("Type", selection: $appState.selectedAnalysis) {
                    Text("OP").tag(AnalysisCommand.op)
                    Text("Tran").tag(AnalysisCommand.tran(TranSpec(stopTime: 1e-3, stepTime: 10e-6)))
                    Text("AC").tag(AnalysisCommand.ac(ACSpec(
                        scaleType: .decade, numberOfPoints: 20,
                        startFrequency: 1, stopFrequency: 1e6
                    )))
                }
            }
            if let error = appState.simulationError {
                Section("Error") {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Inspector panel for the waveform viewer showing data metadata.
private struct WaveformInspectorView: View {
    @Bindable var viewModel: WaveformViewModel

    var body: some View {
        Form {
            Section("Data") {
                LabeledContent("Sweep", value: viewModel.sweepLabel)
                LabeledContent("Points", value: "\(viewModel.waveformData?.pointCount ?? 0)")
                LabeledContent("Signals", value: "\(viewModel.document.traces.count)")
                LabeledContent("Visible", value: "\(viewModel.document.traces.filter(\.isVisible).count)")
            }
            if viewModel.isComplex {
                Section("Mode") {
                    LabeledContent("Type", value: "Complex (AC)")
                }
            }
            if let error = viewModel.exportError {
                Section("Export Error") {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
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

#Preview("OP — Voltage Divider") {
    let state = AppState()
    state.activeEditor = .netlist
    state.spiceSource = """
    * Voltage Divider
    V1 in 0 DC 5
    R1 in out 1k
    R2 out 0 1k
    .op
    .end
    """
    state.spiceFileName = "voltage_divider.cir"
    return ContentView(
        appState: state,
        services: ServiceContainer(),
        waveformViewModel: WaveformViewModel(),
        schematicViewModel: SchematicViewModel()
    )
    .frame(width: 1200, height: 800)
}

#Preview("Tran — RC Step Response") {
    let state = AppState()
    state.activeEditor = .netlist
    state.spiceSource = """
    * RC Lowpass Filter
    V1 in 0 PULSE(0 5 1u 0.1u 0.1u 10u 20u)
    R1 in out 1k
    C1 out 0 1n
    .tran 0.1u 20u
    .end
    """
    state.spiceFileName = "rc_tran.cir"
    return ContentView(
        appState: state,
        services: ServiceContainer(),
        waveformViewModel: WaveformViewModel(),
        schematicViewModel: SchematicViewModel()
    )
    .frame(width: 1200, height: 800)
}

#Preview("AC — RC Lowpass") {
    let state = AppState()
    state.activeEditor = .netlist
    state.spiceSource = """
    * RC Lowpass AC
    V1 in 0 AC 1
    R1 in out 1k
    C1 out 0 1n
    .ac dec 20 1 1G
    .end
    """
    state.spiceFileName = "rc_ac.cir"
    return ContentView(
        appState: state,
        services: ServiceContainer(),
        waveformViewModel: WaveformViewModel(),
        schematicViewModel: SchematicViewModel()
    )
    .frame(width: 1200, height: 800)
}

#Preview("Schematic — Voltage Divider") {
    let state = AppState()
    state.activeEditor = .schematic
    state.selectedAnalysis = .op
    return ContentView(
        appState: state,
        services: ServiceContainer(),
        waveformViewModel: WaveformViewModel(),
        schematicViewModel: SchematicPreview.voltageDividerViewModel()
    )
    .frame(width: 1200, height: 800)
}
