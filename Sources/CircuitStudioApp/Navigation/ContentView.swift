import SwiftUI
import CircuitStudioCore
import SchematicEditor
import WaveformViewer
import LayoutEditor
import MacComponent

/// Main content area following Xcode's information architecture:
/// Navigator (tabbed) | Editor (jump bar + content + optional debug area) | Inspector (tabbed)
public struct ContentView: View {
    @Bindable var appState: AppState
    let services: ServiceContainer
    @Bindable var project: StudioSession

    public init(
        appState: AppState,
        services: ServiceContainer,
        project: StudioSession
    ) {
        self.appState = appState
        self.services = services
        self.project = project
    }

    /// Fixed inspector width: HSplitPane enforces min/max only during divider
    /// drags, so a fixed required width is the only way to keep the pane stable
    /// when it is shown or hidden.
    private static let inspectorWidth: CGFloat = 300

    private var schematicViewModel: SchematicViewModel { project.schematicViewModel }
    private var layoutViewModel: LayoutEditorViewModel { project.layoutViewModel }
    private var waveformViewModel: WaveformViewModel { project.waveformViewModel }

    public var body: some View {
        NavigationSplitView {
            NavigatorPane(appState: appState, services: services, project: project)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } detail: {
            HSplitPane {
                editorArea
                if appState.showInspector {
                    InspectorPane(appState: appState, services: services, project: project)
                        .frame(width: Self.inspectorWidth)
                }
            }
            .leadingPaneWidth(minimum: 300)
            .trailingPaneWidth(minimum: Self.inspectorWidth)
            .trailingPaneWidth(maximum: Self.inspectorWidth)
            .toolbar { toolbarContent }
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

    // MARK: - Editor Area

    @ViewBuilder
    private var editorArea: some View {
        VStack(spacing: 0) {
            EditorJumpBar(appState: appState)
            if appState.showDebugArea {
                VSplitView {
                    workspaceContent
                        .frame(minHeight: 200, maxHeight: .infinity)
                    DebugAreaPane(appState: appState, project: project)
                        .frame(minHeight: 120, idealHeight: 220)
                }
            } else {
                workspaceContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Workspace Content

    @ViewBuilder
    private var workspaceContent: some View {
        switch appState.workspace {
        case .schematicCapture:
            schematicEditorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .layout:
            layoutContent
        case .integration:
            integrationContent
        case .review:
            reviewContent
        }
    }

    @ViewBuilder
    private var reviewContent: some View {
        if let projectRoot = appState.projectRootURL {
            RunReviewView(projectRoot: projectRoot, reviewer: NSUserName())
        } else {
            ContentUnavailableView(
                "Open a project to review runs",
                systemImage: "checkmark.seal",
                description: Text("The review cockpit reads .xcircuite/runs of the open project.")
            )
        }
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

    @ViewBuilder
    private var layoutContent: some View {
        if project.designUnit == nil {
            layoutEmptyState
        } else {
            VStack(spacing: 0) {
                integrationStatusBanners
                LayoutEditorView(viewModel: layoutViewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { layoutViewModel.fitAll() }
            }
        }
    }

    private var layoutEmptyState: some View {
        ContentUnavailableView {
            Label("No Layout", systemImage: "square.dashed")
        } description: {
            Text("Generate a layout from the schematic to start physical design.")
        } actions: {
            VStack(spacing: 8) {
                Button {
                    project.generateLayout(
                        service: services.designFlowService,
                        catalog: services.catalog
                    )
                } label: {
                    Label("Generate from Schematic", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canGenerateLayout)
                .help(generateLayoutHelp)

                if !canGenerateLayout {
                    Text("Draw components and wires in the Schematic workspace first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = project.layoutGenerationError {
                    Label(error, systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var integrationContent: some View {
        VStack(spacing: 0) {
            integrationStatusBanners
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

    @ViewBuilder
    private var integrationStatusBanners: some View {
        if project.isLayoutStale {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Layout is out of date. Regenerate to reflect schematic changes.")
                    .font(.caption)
                Spacer()
                Button("Regenerate") {
                    project.generateLayout(service: services.designFlowService, catalog: services.catalog)
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

    // MARK: - Toolbar (slim, Xcode-style)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 12) {
                workspacePicker
                simulationStatusBadge
            }
        }

        ToolbarItem(placement: .primaryAction) {
            runOrStopButton
        }

        if appState.workspace == .layout || appState.workspace == .integration {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    project.generateLayout(
                        service: services.designFlowService,
                        catalog: services.catalog
                    )
                } label: {
                    Label("Generate Layout", systemImage: "wand.and.stars")
                }
                .disabled(!canGenerateLayout)
                .help(generateLayoutHelp)
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                appState.showDebugArea.toggle()
            } label: {
                Label("Debug Area", systemImage: "rectangle.bottomthird.inset.filled")
            }
            .keyboardShortcut("y", modifiers: [.command, .shift])
            .help("Show/Hide Debug Area")

            Button {
                appState.showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            .help("Show/Hide Inspector")
        }
    }

    private var workspacePicker: some View {
        Picker("Workspace", selection: $appState.workspace) {
            Text("Schematic").tag(Workspace.schematicCapture)
            Text("Layout").tag(Workspace.layout)
            Text("Integration").tag(Workspace.integration)
            Text("Review").tag(Workspace.review)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .help("Switch Workspace")
    }

    @ViewBuilder
    private var simulationStatusBadge: some View {
        if let status = appState.simulationStatus {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var runOrStopButton: some View {
        if appState.isSimulating {
            Button {
                appState.cancelSimulation(service: services.designFlowService)
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .keyboardShortcut(".", modifiers: .command)
            .help("Stop the running simulation (⌘.)")
        } else {
            Button {
                runActiveSimulation()
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .disabled(runButtonDisabled)
            .keyboardShortcut("r", modifiers: .command)
            .help("Simulate the schematic with the selected analysis (⌘R)")
        }
    }

    // MARK: - Run Logic

    /// Mirrors the menu command's enablement in App.swift.
    private var canGenerateLayout: Bool {
        !schematicViewModel.document.components.isEmpty
            && !schematicViewModel.document.wires.isEmpty
    }

    /// Tooltip explaining what layout generation does, or why it is disabled.
    private var generateLayoutHelp: String {
        if canGenerateLayout {
            return "Automatically place and route the schematic components into a physical layout, then run DRC (⇧⌘G)"
        }
        return "Layout generation needs a schematic with components and wires. Draw the circuit in the Schematic workspace first."
    }

    private var runButtonDisabled: Bool {
        guard appState.workspace == .schematicCapture else { return true }
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

    private func runActiveSimulation() {
        Task {
            switch appState.schematicMode {
            case .visual:
                await appState.runSchematicSimulation(
                    document: schematicViewModel.document,
                    analysisCommand: appState.selectedAnalysis,
                    service: services.designFlowService
                )
            case .netlist:
                await appState.runSimulation(service: services.designFlowService)
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
        project: StudioSession(schematicViewModel: SchematicPreview.voltageDividerViewModel())
    )
    .frame(width: 1200, height: 800)
}

#Preview("OP — Diode Forward Bias") {
    ContentView(
        appState: makePreviewState(),
        services: ServiceContainer(),
        project: StudioSession(schematicViewModel: SchematicPreview.diodeForwardBiasViewModel())
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
        project: StudioSession(schematicViewModel: SchematicPreview.rcLowpassViewModel())
    )
    .frame(width: 1200, height: 800)
}

#Preview("Tran — RC Loaded Step") {
    ContentView(
        appState: makePreviewState(analysis: .tran(TranSpec(stopTime: 2e-6, stepTime: 1e-9))),
        services: ServiceContainer(),
        project: StudioSession(schematicViewModel: SchematicPreview.rcLoadedStepViewModel())
    )
    .frame(width: 1200, height: 800)
}

#Preview("Tran — RLC Damped") {
    ContentView(
        appState: makePreviewState(analysis: .tran(TranSpec(stopTime: 500e-9, stepTime: 0.5e-9))),
        services: ServiceContainer(),
        project: StudioSession(schematicViewModel: SchematicPreview.rlcDampedViewModel())
    )
    .frame(width: 1200, height: 800)
}

#Preview("Tran — CMOS Inverter") {
    ContentView(
        appState: makePreviewState(analysis: .tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9))),
        services: ServiceContainer(),
        project: StudioSession(schematicViewModel: SchematicPreview.cmosInverterViewModel())
    )
    .frame(width: 1200, height: 800)
}

#Preview("Integration — CMOS Inverter with Layout") {
    let state = makePreviewState()
    state.workspace = .integration
    return ContentView(
        appState: state,
        services: ServiceContainer(),
        project: StudioSession.withGeneratedLayout(
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
        project: StudioSession.withGeneratedLayout(
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
        project: StudioSession.withGeneratedLayout(
            schematicViewModel: SchematicPreview.currentMirrorViewModel()
        )
    )
    .frame(width: 1200, height: 800)
}
