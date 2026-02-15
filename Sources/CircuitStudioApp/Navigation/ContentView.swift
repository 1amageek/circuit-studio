import SwiftUI
import CircuitStudioCore
import SchematicEditor
import WaveformViewer
import LayoutEditor
import UniformTypeIdentifiers

/// Main content area with macOS HIG-compliant layout:
/// Sidebar (navigator) | Workspace Content | Inspector
public struct ContentView: View {
    @Bindable var appState: AppState
    let services: ServiceContainer
    @Bindable var project: DesignProject

    public init(
        appState: AppState,
        services: ServiceContainer,
        project: DesignProject
    ) {
        self.appState = appState
        self.services = services
        self.project = project
    }

    private var schematicViewModel: SchematicViewModel { project.schematicViewModel }
    private var layoutViewModel: LayoutEditorViewModel { project.layoutViewModel }
    private var waveformViewModel: WaveformViewModel { project.waveformViewModel }

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            VStack(spacing: 0) {
                workspaceContent
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

    // MARK: - Workspace Content

    @ViewBuilder
    private var workspaceContent: some View {
        switch appState.workspace {
        case .schematicCapture:
            schematicCaptureContent
        case .layout:
            layoutContent
        case .integration:
            integrationContent
        }
    }

    /// schematicCapture workspace: schematic or netlist editor + optional waveform panel
    @ViewBuilder
    private var schematicCaptureContent: some View {
        HSplitView {
            schematicEditorContent
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            if appState.showSimulationResults {
                WaveformResultView(viewModel: waveformViewModel)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var schematicEditorContent: some View {
        switch appState.schematicMode {
        case .visual:
            SchematicEditorView(viewModel: schematicViewModel)
        case .netlist:
            NetlistEditorView(appState: appState)
        }
    }

    /// layout workspace: layout editor (DRC built-in)
    private var layoutContent: some View {
        LayoutEditorView(viewModel: layoutViewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { layoutViewModel.fitAll() }
    }

    /// integration workspace: schematic + layout side by side
    @ViewBuilder
    private var integrationContent: some View {
        VStack(spacing: 0) {
            if project.isLayoutStale {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Layout is out of date. Regenerate to reflect schematic changes.")
                        .font(.caption)
                    Spacer()
                    Button("Regenerate") {
                        project.generateLayout(catalog: services.catalog)
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.1))
            }
            if let error = project.layoutGenerationError {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.red.opacity(0.1))
            }
            if !project.skippedComponents.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Skipped: \(project.skippedComponents.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let name = project.techName {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.blue.opacity(0.05))
            }
            HSplitView {
                SchematicEditorView(viewModel: schematicViewModel)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                LayoutEditorView(viewModel: layoutViewModel)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { layoutViewModel.fitAll() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: schematicViewModel.document.selection) { _, newSelection in
            syncSchematicToLayout(newSelection)
        }
        .onChange(of: layoutViewModel.selectedInstanceID) { _, instID in
            syncLayoutToSchematic(instID)
        }
    }

    // MARK: - Cross-Probe Sync

    private func syncSchematicToLayout(_ selection: Set<UUID>) {
        guard project.designUnit != nil else {
            layoutViewModel.highlightedInstanceIDs = []
            return
        }
        let crossProbe = project.crossProbe
        let instanceIDs: Set<UUID> = Set(
            selection.compactMap { crossProbe.instanceMapping[$0] }
        )
        layoutViewModel.highlightedInstanceIDs = instanceIDs
    }

    private func syncLayoutToSchematic(_ instanceID: UUID?) {
        guard let instID = instanceID,
              let compID = project.crossProbe.instanceToComponent[instID] else {
            schematicViewModel.highlightedIDs = []
            return
        }
        schematicViewModel.highlightedIDs = [compID]
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Workspace picker (center)
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                Picker("Workspace", selection: $appState.workspace) {
                    Label("Schematic", systemImage: "square.grid.3x3")
                        .tag(Workspace.schematicCapture)
                    Label("Layout", systemImage: "square.dashed")
                        .tag(Workspace.layout)
                    Label("Integration", systemImage: "rectangle.split.2x1")
                        .tag(Workspace.integration)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                if appState.workspace == .schematicCapture {
                    Picker("Mode", selection: $appState.schematicMode) {
                        Label("Visual", systemImage: "square.grid.3x3")
                            .tag(SchematicMode.visual)
                        Label("Netlist", systemImage: "doc.text")
                            .tag(SchematicMode.netlist)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
            }
        }

        // Context-dependent actions
        contextToolbarItems

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
            if appState.workspace == .schematicCapture {
                Button {
                    appState.showSimulationResults.toggle()
                } label: {
                    Label("Simulation Results",
                          systemImage: "rectangle.righthalf.inset.filled")
                }
                .disabled(appState.simulationResult == nil && !appState.isSimulating)
            }

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

    @ToolbarContentBuilder
    private var contextToolbarItems: some ToolbarContent {
        switch appState.workspace {
        case .schematicCapture:
            schematicToolbarItems
        case .layout, .integration:
            layoutToolbarItems
        }
    }

    // MARK: - Schematic Toolbar

    private var canGenerateLayout: Bool {
        !schematicViewModel.document.components.isEmpty
            && !schematicViewModel.document.wires.isEmpty
    }

    private var runButtonDisabled: Bool {
        if appState.isSimulating { return true }
        switch appState.schematicMode {
        case .visual:
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
        if appState.schematicMode == .visual {
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

        if appState.schematicMode == .netlist {
            ToolbarItem(placement: .status) {
                if let fileName = appState.spiceFileName {
                    Text(fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
                        switch appState.schematicMode {
                        case .visual:
                            await appState.runSchematicSimulation(
                                document: schematicViewModel.document,
                                analysisCommand: appState.selectedAnalysis,
                                generator: services.netlistGenerator,
                                service: services.simulationService
                            )
                        case .netlist:
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
    }

    // MARK: - Layout Toolbar

    @ToolbarContentBuilder
    private var layoutToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    project.generateLayout(catalog: services.catalog)
                    appState.workspace = .integration
                } label: {
                    Label("Generate Layout", systemImage: "cpu")
                }
                .disabled(!canGenerateLayout)

                Divider()

                Button {
                    loadTechFile()
                } label: {
                    if let name = project.techName {
                        Label("Tech: \(name)", systemImage: "checkmark")
                    } else {
                        Label("Load Tech File...", systemImage: "gearshape.2")
                    }
                }
            } label: {
                Label("Layout", systemImage: "cpu")
            }
            .help("Generate layout or load technology file")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                layoutViewModel.runDRC()
            } label: {
                Label("Run DRC", systemImage: "checkmark.shield")
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
        switch appState.workspace {
        case .schematicCapture:
            if appState.showSimulationResults {
                WaveformInspectorView(viewModel: waveformViewModel)
            } else {
                switch appState.schematicMode {
                case .visual:
                    PropertyInspector(viewModel: schematicViewModel)
                case .netlist:
                    NetlistInspectorView(appState: appState)
                }
            }
        case .layout:
            LayoutInspectorView(viewModel: layoutViewModel)
        case .integration:
            LayoutInspectorView(viewModel: layoutViewModel)
        }
    }

    // MARK: - Tech File Open

    private func loadTechFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "json")!,
            UTType(filenameExtension: "lef")!,
            UTType(filenameExtension: "lyp")!,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try project.loadTechFile(from: url)
                appState.log("Loaded tech: \(url.lastPathComponent)", kind: .success)
            } catch {
                appState.simulationError = "Failed to load tech: \(error.localizedDescription)"
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
            processSection
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

    // MARK: - Process

    @ViewBuilder
    private var processSection: some View {
        Section("Process") {
            if let technology = appState.processConfiguration.technology {
                LabeledContent("Name", value: technology.name)
                if let version = technology.version, !version.isEmpty {
                    LabeledContent("Version", value: version)
                }
                if let foundry = technology.foundry, !foundry.isEmpty {
                    LabeledContent("Foundry", value: foundry)
                }

                if !technology.cornerSet.corners.isEmpty {
                    Picker("Corner", selection: Binding<UUID?>(
                        get: { appState.processConfiguration.cornerID },
                        set: { appState.processConfiguration.cornerID = $0 }
                    )) {
                        Text("Default").tag(UUID?.none)
                        ForEach(technology.cornerSet.corners) { corner in
                            Text(corner.name).tag(Optional(corner.id))
                        }
                    }
                }

                TextField("Temp Override (C)", text: temperatureOverrideBinding)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Change...") { openProcessFile() }
                    Button("Clear") { clearProcessConfiguration() }
                }
            } else {
                Text("No process loaded")
                    .foregroundStyle(.secondary)
                Button("Load Process...") { openProcessFile() }
            }
        }
    }

    private var temperatureOverrideBinding: Binding<String> {
        Binding(
            get: {
                if let value = appState.processConfiguration.temperatureOverride {
                    return String(format: "%.4g", value)
                }
                return ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    appState.processConfiguration.temperatureOverride = nil
                    return
                }
                if let parsed = Double(trimmed) {
                    appState.processConfiguration.temperatureOverride = parsed
                }
            }
        )
    }

    private func openProcessFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "json")!,
            .plainText,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let technology = try JSONDecoder().decode(ProcessTechnology.self, from: data)
                appState.processConfiguration.technology = technology
                appState.processConfiguration.cornerID = technology.defaultCornerID
                appState.processConfiguration.resolveIncludes = true
                appState.log("Loaded process: \(technology.name)", kind: .success)
            } catch {
                appState.simulationError = "Failed to load process: \(error.localizedDescription)"
            }
        }
    }

    private func clearProcessConfiguration() {
        appState.processConfiguration = ProcessConfiguration()
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

// MARK: - Preview Helpers

@MainActor
private func makePreviewState(
    schematicMode: SchematicMode = .visual,
    analysis: AnalysisCommand = .op
) -> AppState {
    let state = AppState()
    state.workspace = .schematicCapture
    state.schematicMode = schematicMode
    state.selectedAnalysis = analysis
    return state
}

// MARK: - Previews

#Preview("OP — Voltage Divider") {
    ContentView(
        appState: makePreviewState(),
        services: ServiceContainer(),
        project: DesignProject(schematicViewModel: SchematicPreview.voltageDividerViewModel())
    )
    .frame(width: 1200, height: 800)
}

#Preview("OP — Diode Forward Bias") {
    ContentView(
        appState: makePreviewState(),
        services: ServiceContainer(),
        project: DesignProject(schematicViewModel: SchematicPreview.diodeForwardBiasViewModel())
    )
    .frame(width: 1200, height: 800)
}

#Preview("AC — RC Lowpass") {
    ContentView(
        appState: makePreviewState(analysis: .ac(ACSpec(
            scaleType: .decade, numberOfPoints: 20,
            startFrequency: 1, stopFrequency: 1e6
        ))),
        services: ServiceContainer(),
        project: DesignProject(schematicViewModel: SchematicPreview.rcLowpassViewModel())
    )
    .frame(width: 1200, height: 800)
}

#Preview("Tran — RC Loaded Step") {
    ContentView(
        appState: makePreviewState(analysis: .tran(TranSpec(stopTime: 2e-6, stepTime: 1e-9))),
        services: ServiceContainer(),
        project: DesignProject(schematicViewModel: SchematicPreview.rcLoadedStepViewModel())
    )
    .frame(width: 1200, height: 800)
}

#Preview("Tran — RLC Damped") {
    ContentView(
        appState: makePreviewState(analysis: .tran(TranSpec(stopTime: 500e-9, stepTime: 0.5e-9))),
        services: ServiceContainer(),
        project: DesignProject(schematicViewModel: SchematicPreview.rlcDampedViewModel())
    )
    .frame(width: 1200, height: 800)
}

#Preview("Tran — CMOS Inverter") {
    ContentView(
        appState: makePreviewState(analysis: .tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9))),
        services: ServiceContainer(),
        project: DesignProject(schematicViewModel: SchematicPreview.cmosInverterViewModel())
    )
    .frame(width: 1200, height: 800)
}

#Preview("Integration — CMOS Inverter with Layout") {
    let state = makePreviewState()
    state.workspace = .integration
    return ContentView(
        appState: state,
        services: ServiceContainer(),
        project: DesignProject.withGeneratedLayout(
            schematicViewModel: SchematicPreview.cmosInverterViewModel()
        )
    )
    .frame(width: 1200, height: 800)
}

#Preview("Layout — Voltage Divider") {
    let state = makePreviewState()
    state.workspace = .layout
    return ContentView(
        appState: state,
        services: ServiceContainer(),
        project: DesignProject.withGeneratedLayout(
            schematicViewModel: SchematicPreview.voltageDividerViewModel()
        )
    )
    .frame(width: 1200, height: 800)
}

#Preview("Integration — Current Mirror with Layout") {
    let state = makePreviewState()
    state.workspace = .integration
    return ContentView(
        appState: state,
        services: ServiceContainer(),
        project: DesignProject.withGeneratedLayout(
            schematicViewModel: SchematicPreview.currentMirrorViewModel()
        )
    )
    .frame(width: 1200, height: 800)
}
