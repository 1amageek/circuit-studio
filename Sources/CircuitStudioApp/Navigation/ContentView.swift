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
                    .layoutPriority(1)
                if appState.showConsole {
                    SimulationConsoleView(appState: appState)
                        .frame(maxHeight: 200)
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
        .onChange(of: appState.streamingWaveformVersion) { _, _ in
            if let waveform = appState.streamingWaveform {
                waveformViewModel.updateStreaming(waveform: waveform)
            }
        }
        .onChange(of: appState.isSimulating) { wasSimulating, isSimulating in
            if wasSimulating, !isSimulating,
               appState.simulationError == nil,
               let waveform = appState.simulationResult?.waveform {
                waveformViewModel.load(waveform: waveform)

                // Filter waveform to PORT components if any are placed
                let resolver = TerminalResolver()
                let extractor = NetExtractor()
                let nets = extractor.extract(from: schematicViewModel.document)
                let resolved = resolver.resolve(
                    document: schematicViewModel.document,
                    nets: nets,
                    catalog: services.netlistGenerator.catalog
                )
                waveformViewModel.applyTerminalComponents(resolved)
            }
        }
        .onChange(of: appState.spiceSource) { _, _ in
            appState.scheduleNetlistParse(service: services.netlistParsingService)
        }
        .onAppear {
            if !appState.spiceSource.isEmpty {
                appState.scheduleNetlistParse(service: services.netlistParsingService)
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
        HSplitView {
            editorView
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            if appState.showSimulationResults {
                WaveformResultView(viewModel: waveformViewModel)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var editorView: some View {
        switch appState.activeEditor {
        case .netlist:
            NetlistEditorView(appState: appState)
        case .schematic:
            SchematicEditorView(viewModel: schematicViewModel)
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
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
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
        case .netlist:
            ToolbarItem(placement: .status) {
                if let fileName = appState.spiceFileName {
                    Text(fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if appState.showSimulationResults {
            waveformToolbarItems
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

        // Panel toggles
        ToolbarItemGroup {
            Button {
                appState.showSimulationResults.toggle()
            } label: {
                Label("Simulation Results",
                      systemImage: appState.showSimulationResults
                          ? "rectangle.righthalf.inset.filled"
                          : "rectangle.righthalf.inset.filled")
            }
            .disabled(appState.simulationResult == nil && !appState.isSimulating)

            Button {
                appState.showConsole.toggle()
            } label: {
                Label("Console", systemImage: "terminal")
            }

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
        case .netlist:
            if appState.spiceSource.isEmpty { return true }
            guard let info = appState.netlistInfo else { return true }
            return info.hasErrors || info.components.isEmpty
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
        if appState.showSimulationResults {
            WaveformInspectorView(viewModel: waveformViewModel)
        } else {
            switch appState.activeEditor {
            case .schematic:
                PropertyInspector(viewModel: schematicViewModel)
            case .netlist:
                NetlistInspectorView(appState: appState)
            }
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

/// Inspector panel for the netlist editor showing parsed netlist info.
private struct NetlistInspectorView: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            fileSection
            analysisSection
            componentsSection
            nodesSection
            modelsSection
            diagnosticsSection
            simulationErrorSection
        }
        .formStyle(.grouped)
    }

    // MARK: - File

    private var fileSection: some View {
        Section("File") {
            LabeledContent("Name", value: appState.spiceFileName ?? "Untitled")
            LabeledContent("Lines", value: "\(appState.spiceSource.components(separatedBy: "\n").count)")
            if let title = appState.netlistInfo?.title {
                LabeledContent("Title", value: title)
            }
        }
    }

    // MARK: - Analysis

    @ViewBuilder
    private var analysisSection: some View {
        let detected = appState.netlistInfo?.analyses ?? []
        Section("Analysis") {
            if detected.isEmpty {
                Picker("Type", selection: $appState.selectedAnalysis) {
                    Text("OP").tag(AnalysisCommand.op)
                    Text("Tran").tag(AnalysisCommand.tran(TranSpec(stopTime: 1e-3, stepTime: 10e-6)))
                    Text("AC").tag(AnalysisCommand.ac(ACSpec(
                        scaleType: .decade, numberOfPoints: 20,
                        startFrequency: 1, stopFrequency: 1e6
                    )))
                }
            } else {
                ForEach(detected) { analysis in
                    LabeledContent(analysis.type) {
                        Text(analysis.label)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private var componentsSection: some View {
        let components = appState.netlistInfo?.components ?? []
        if !components.isEmpty {
            Section("Components (\(components.count))") {
                ForEach(components) { component in
                    HStack {
                        Text(component.name)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                        Spacer()
                        if let model = component.modelName {
                            Text(model)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let value = component.primaryValue {
                            Text(value)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(component.type)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Nodes

    @ViewBuilder
    private var nodesSection: some View {
        let nodes = appState.netlistInfo?.nodes ?? []
        if !nodes.isEmpty {
            Section("Nodes (\(nodes.count))") {
                ForEach(nodes, id: \.self) { node in
                    Text(node)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
    }

    // MARK: - Models

    @ViewBuilder
    private var modelsSection: some View {
        let models = appState.netlistInfo?.models ?? []
        if !models.isEmpty {
            Section("Models (\(models.count))") {
                ForEach(models) { model in
                    LabeledContent(model.name) {
                        Text(model.type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Diagnostics

    @ViewBuilder
    private var diagnosticsSection: some View {
        let diagnostics = appState.netlistInfo?.diagnostics ?? []
        if !diagnostics.isEmpty {
            Section("Diagnostics") {
                ForEach(diagnostics) { d in
                    HStack(spacing: 6) {
                        Image(systemName: diagnosticIcon(d.severity))
                            .foregroundStyle(diagnosticColor(d.severity))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.message)
                                .font(.caption)
                            if let line = d.line {
                                Text("Line \(line)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Simulation Error

    @ViewBuilder
    private var simulationErrorSection: some View {
        if let error = appState.simulationError {
            Section("Error") {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    // MARK: - Diagnostic Helpers

    private func diagnosticIcon(_ severity: NetlistDiagnostic.Severity) -> String {
        switch severity {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .hint: return "lightbulb.fill"
        }
    }

    private func diagnosticColor(_ severity: NetlistDiagnostic.Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .hint: return .secondary
        }
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

#Preview("OP — Diode Forward Bias") {
    let state = AppState()
    state.activeEditor = .schematic
    state.selectedAnalysis = .op
    return ContentView(
        appState: state,
        services: ServiceContainer(),
        waveformViewModel: WaveformViewModel(),
        schematicViewModel: SchematicPreview.diodeForwardBiasViewModel()
    )
    .frame(width: 1200, height: 800)
}

#Preview("AC — RC Lowpass") {
    let state = AppState()
    state.activeEditor = .schematic
    state.selectedAnalysis = .ac(ACSpec(
        scaleType: .decade, numberOfPoints: 20,
        startFrequency: 1, stopFrequency: 1e6
    ))
    return ContentView(
        appState: state,
        services: ServiceContainer(),
        waveformViewModel: WaveformViewModel(),
        schematicViewModel: SchematicPreview.rcLowpassViewModel()
    )
    .frame(width: 1200, height: 800)
}

#Preview("Tran — RC Loaded Step") {
    let state = AppState()
    state.activeEditor = .schematic
    state.selectedAnalysis = .tran(TranSpec(stopTime: 2e-6, stepTime: 1e-9))
    return ContentView(
        appState: state,
        services: ServiceContainer(),
        waveformViewModel: WaveformViewModel(),
        schematicViewModel: SchematicPreview.rcLoadedStepViewModel()
    )
    .frame(width: 1200, height: 800)
}

#Preview("Tran — RLC Damped") {
    let state = AppState()
    state.activeEditor = .schematic
    state.selectedAnalysis = .tran(TranSpec(stopTime: 500e-9, stepTime: 0.5e-9))
    return ContentView(
        appState: state,
        services: ServiceContainer(),
        waveformViewModel: WaveformViewModel(),
        schematicViewModel: SchematicPreview.rlcDampedViewModel()
    )
    .frame(width: 1200, height: 800)
}

#Preview("Tran — CMOS Inverter") {
    let state = AppState()
    state.activeEditor = .schematic
    state.selectedAnalysis = .tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9))
    return ContentView(
        appState: state,
        services: ServiceContainer(),
        waveformViewModel: WaveformViewModel(),
        schematicViewModel: SchematicPreview.cmosInverterViewModel()
    )
    .frame(width: 1200, height: 800)
}

