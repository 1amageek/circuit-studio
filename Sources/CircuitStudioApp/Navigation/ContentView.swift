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

    /// Published while key focus is inside an editor subtree; the Delete-key
    /// router stands down in that state so the focused canvas keeps handling
    /// Delete itself (including mid-drawing vertex retraction).
    @FocusedValue(\.editorCommands) private var focusedEditorCommands
    @State private var lastLayoutGenerationLogSignature: String?

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
        .background(DeleteKeyRouterView(action: routedDeleteAction))
        .onChange(of: appState.streamingWaveformVersion) { _, _ in
            if let waveform = appState.streamingWaveform {
                waveformViewModel.updateStreaming(waveform: waveform)
            }
        }
        .onChange(of: appState.focusedWaveformVersion) { _, _ in
            guard let waveform = appState.focusedWaveform else { return }
            waveformViewModel.load(waveform: waveform)
            // Terminal-component trace names only match live runs of the open
            // schematic; overlay/history traces carry corner suffixes that the
            // filter would empty out.
            if appState.focusedWaveformSource == .liveRun {
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
            wireCellDescent()
            logLayoutGenerationAvailability(context: "content-appear")
        }
        .onChange(of: layoutGenerationLogSignature) { _, _ in
            logLayoutGenerationAvailability(context: "state-changed")
        }
        .sheet(isPresented: $appState.isNewCellSheetPresented) {
            NewCellSheet(appState: appState, project: project)
        }
    }

    /// Routes a double-click on a placed cell instance to opening that cell:
    /// the schematic canvas reports the instance's cell name, and the session
    /// switches every editor pane to it. A dangling reference surfaces as a
    /// logged error rather than silently doing nothing.
    private func wireCellDescent() {
        project.cellDescendAction = { cellName in
            do {
                try project.activateCell(named: cellName)
                appState.workspace = .schematicCapture
                appState.schematicMode = .visual
                appState.navigatorTab = .schematic
            } catch {
                appState.log(
                    "Could not open cell '\(cellName)': \(error.localizedDescription)",
                    kind: .error
                )
            }
        }
    }

    /// Delete verb for the window-level key router. Nil while an editor
    /// subtree holds focus (its canvas handles Delete itself) and for
    /// workspaces without an unambiguous canvas target.
    private var routedDeleteAction: RoutedDeleteAction? {
        RoutedDeleteCommand.resolve(
            workspace: appState.workspace,
            schematicMode: appState.schematicMode,
            editorHasKeyFocus: focusedEditorCommands != nil,
            schematic: schematicViewModel,
            layout: layoutViewModel
        )
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
            schematicWorkspaceContent
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

    /// Schematic workspace: the editor, with the waveform pane split below it
    /// once a run has produced a result (edit -> run -> inspect in one view).
    @ViewBuilder
    private var schematicWorkspaceContent: some View {
        if appState.showWaveformPane {
            VSplitView {
                schematicEditorContent
                    .frame(minHeight: 200, maxHeight: .infinity)
                waveformPane
                    .frame(minHeight: 160, idealHeight: 280)
            }
        } else {
            schematicEditorContent
        }
    }

    @ViewBuilder
    private var schematicEditorContent: some View {
        switch appState.schematicMode {
        case .visual:
            SchematicEditorView(viewModel: schematicViewModel)
                .focusedValue(\.editorCommands, schematicEditorCommands)
        case .netlist:
            NetlistEditorView(appState: appState)
        }
    }

    // MARK: - Edit Menu Commands

    /// Edit-menu operations for the schematic canvas. The view model's
    /// mutating operations do not record undo themselves, so each mutating
    /// command snapshots the document first, matching the canvas key handlers.
    private var schematicEditorCommands: EditorCommands {
        EditorCommands(
            canUndo: schematicViewModel.canUndo,
            canRedo: schematicViewModel.canRedo,
            undo: { schematicViewModel.undo() },
            redo: { schematicViewModel.redo() },
            cut: {
                schematicViewModel.recordForUndo()
                schematicViewModel.cutSelection()
            },
            copy: { schematicViewModel.copySelection() },
            paste: {
                schematicViewModel.recordForUndo()
                schematicViewModel.paste(at: nil)
            },
            duplicate: {
                schematicViewModel.recordForUndo()
                schematicViewModel.duplicate()
            },
            delete: {
                schematicViewModel.recordForUndo()
                schematicViewModel.deleteSelection()
            },
            selectAll: { schematicViewModel.selectAll() }
        )
    }

    /// Edit-menu operations for the layout canvas. Cut/copy/paste stay nil —
    /// the layout editor has no pasteboard support yet, so the menu items
    /// show as disabled while this editor has focus.
    private var layoutEditorCommands: EditorCommands {
        EditorCommands(
            canUndo: layoutViewModel.canUndo,
            canRedo: layoutViewModel.canRedo,
            undo: { layoutViewModel.undo() },
            redo: { layoutViewModel.redo() },
            duplicate: { layoutViewModel.duplicateSelectedShapesByGridStep() },
            delete: { layoutViewModel.deleteSelection() },
            selectAll: { layoutViewModel.selectAllShapes() }
        )
    }

    private var waveformPane: some View {
        VStack(spacing: 0) {
            PaneSectionHeader("Waveform") {
                Button {
                    appState.showWaveformPane = false
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide Waveform Pane")
            }
            WaveformResultView(viewModel: waveformViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var layoutContent: some View {
        if !project.layoutHasContent {
            layoutEmptyState
        } else {
            VStack(spacing: 0) {
                integrationStatusBanners
                LayoutEditorView(viewModel: layoutViewModel)
                    .focusedValue(\.editorCommands, layoutEditorCommands)
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
                    services.layoutPersistenceService.generateLayout(
                        project: project,
                        appState: appState,
                        designFlow: services.designFlowService,
                        catalog: services.catalog
                    )
                } label: {
                    Label("Generate from Schematic", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canGenerateLayout)
                .help(generateLayoutHelp)

                if let reason = layoutGenerationAvailability.reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                if let error = project.layoutGenerationError {
                    Label(error, systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            logLayoutGenerationAvailability(context: "layout-empty-state")
        }
    }

    @ViewBuilder
    private var integrationContent: some View {
        VStack(spacing: 0) {
            integrationStatusBanners
            HSplitView {
                SchematicEditorView(viewModel: schematicViewModel)
                    .focusedValue(\.editorCommands, schematicEditorCommands)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                LayoutEditorView(viewModel: layoutViewModel)
                    .focusedValue(\.editorCommands, layoutEditorCommands)
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
                    services.layoutPersistenceService.generateLayout(
                        project: project,
                        appState: appState,
                        designFlow: services.designFlowService,
                        catalog: services.catalog
                    )
                }
                .controlSize(.small)
                .disabled(!canGenerateLayout)
                .help(generateLayoutHelp)
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
                documentTitleLabel
                simulationStatusBadge
            }
        }

        ToolbarItem(placement: .primaryAction) {
            runOrStopButton
        }

        if appState.workspace == .layout || appState.workspace == .integration {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    services.layoutPersistenceService.generateLayout(
                        project: project,
                        appState: appState,
                        designFlow: services.designFlowService,
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

    /// Document name with an Xcode-style edited marker when there are
    /// unsaved netlist or schematic changes.
    private var documentTitleLabel: some View {
        let isDirty = appState.isNetlistDirty || project.hasUnsavedChanges
        return HStack(spacing: 4) {
            Text(documentTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            if isDirty {
                Text("— Edited")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .help(isDirty ? "Unsaved changes — press Cmd-S to save" : "All changes saved")
        .accessibilityLabel(isDirty ? "\(documentTitle), edited" : documentTitle)
    }

    private var documentTitle: String {
        appState.projectRootURL?.lastPathComponent
            ?? appState.spiceFileName
            ?? project.designName
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

    private var layoutGenerationPreflightReport: LayoutGenerationPreflightReport {
        makeLayoutGenerationPreflightReport(context: "ui")
    }

    private var layoutGenerationAvailability: LayoutGenerationAvailability {
        layoutGenerationPreflightReport.availability
    }

    /// Mirrors the menu command's enablement in App.swift.
    private var canGenerateLayout: Bool {
        layoutGenerationAvailability.isAvailable
    }

    /// Tooltip explaining what layout generation does, or why it is disabled.
    private var generateLayoutHelp: String {
        layoutGenerationAvailability.help
    }

    private var layoutGenerationLogSignature: String {
        layoutGenerationPreflightReport.signature
    }

    private func makeLayoutGenerationPreflightReport(context: String) -> LayoutGenerationPreflightReport {
        LayoutGenerationPreflightReport.make(
            context: context,
            project: project,
            projectRootURL: appState.projectRootURL,
            selectedFileURL: appState.selectedFileURL,
            projectService: services.projectService,
            catalog: services.catalog,
            workspace: appState.workspace.rawValue,
            netlistMaterialization: LayoutGenerationNetlistMaterializationSnapshot(
                appState.netlistSchematicMaterializationState
            )
        )
    }

    private func logLayoutGenerationAvailability(context: String) {
        guard appState.workspace == .layout || appState.workspace == .integration else { return }
        let signature = layoutGenerationLogSignature
        guard signature != lastLayoutGenerationLogSignature else { return }
        lastLayoutGenerationLogSignature = signature

        LayoutGenerationDiagnosticsLogger.log(report: makeLayoutGenerationPreflightReport(context: context))
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
            await appState.runActiveSimulation(
                schematicDocument: schematicViewModel.document,
                library: project.cellLibrary,
                service: services.designFlowService
            )
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
