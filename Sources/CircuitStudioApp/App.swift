import SwiftUI
import AppKit
import CircuitStudioCore
import WaveformViewer
import SchematicEditor
import LayoutEditor
import LayoutIO
import UniformTypeIdentifiers

public struct CircuitStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var services = ServiceContainer()
    @State private var project = StudioSession()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView(
                appState: appState,
                services: services,
                project: project
            )
            .frame(minWidth: 800, minHeight: 500)
            .onAppear { wireTerminationGuard() }
        }
        .defaultSize(width: 1200, height: 700)
        .commands {
            fileCommands
            EditMenuCommands()
            viewCommands
            workspaceCommands
            simulationCommands
            layoutCommands
        }
    }

    // MARK: - File Menu

    @CommandsBuilder
    private var fileCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Cell...") { appState.isNewCellSheetPresented = true }
                .keyboardShortcut("n")
            Button("New Project...") { newProject() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Open...") { openSPICEFile() }
                .keyboardShortcut("o")
            Button("Open Folder...") { openFolder() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            openRecentMenu
            Divider()
            Button("Save") { saveAction() }
                .keyboardShortcut("s")
                .disabled(appState.spiceSource.isEmpty && appState.projectRootURL == nil)
            Divider()
            Button("Export Layout...") { exportLayout() }
                .disabled(!project.layoutHasContent)
            Button("Export Waveform...") { project.waveformViewModel.exportWaveform() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(project.waveformViewModel.waveformData == nil)
        }
    }

    private var openRecentMenu: some View {
        Menu("Open Recent") {
            ForEach(services.recentDocumentsStore.documents) { document in
                Button(document.displayName) { openRecent(document) }
                    .help(document.abbreviatedPath)
            }
            Divider()
            Button("Clear Menu") {
                do {
                    try services.recentDocumentsStore.clear()
                } catch {
                    appState.log(
                        "Failed to clear recent documents: \(error.localizedDescription)",
                        kind: .error
                    )
                }
            }
            .disabled(services.recentDocumentsStore.documents.isEmpty)
        }
    }

    // MARK: - View Menu (panes + navigator tabs)

    @CommandsBuilder
    private var viewCommands: some Commands {
        CommandGroup(after: .toolbar) {
            Button(appState.showInspector ? "Hide Inspector" : "Show Inspector") {
                appState.showInspector.toggle()
            }
            .keyboardShortcut("0", modifiers: [.command, .option])

            Button(appState.showDebugArea ? "Hide Debug Area" : "Show Debug Area") {
                appState.showDebugArea.toggle()
            }
            .keyboardShortcut("y", modifiers: [.command, .shift])

            Divider()

            ForEach(NavigatorTab.allCases, id: \.self) { tab in
                Button("Show \(navigatorTabTitle(tab))") {
                    appState.navigatorTab = tab
                }
                .keyboardShortcut(navigatorTabShortcut(tab), modifiers: .command)
            }
        }
    }

    private func navigatorTabTitle(_ tab: NavigatorTab) -> String {
        switch tab {
        case .project: return "Project Navigator"
        case .cells: return "Cells Navigator"
        case .schematic: return "Schematic Navigator"
        case .layout: return "Layout Navigator"
        case .issues: return "Issues Navigator"
        case .simulation: return "Simulation Navigator"
        }
    }

    private func navigatorTabShortcut(_ tab: NavigatorTab) -> KeyEquivalent {
        switch tab {
        case .project: return "1"
        case .cells: return "2"
        case .schematic: return "3"
        case .layout: return "4"
        case .issues: return "5"
        case .simulation: return "6"
        }
    }

    // MARK: - Workspace Menu

    @CommandsBuilder
    private var workspaceCommands: some Commands {
        CommandMenu("Workspace") {
            Button("Schematic Capture") { appState.workspace = .schematicCapture }
                .keyboardShortcut("1", modifiers: [.command, .control])
            Button("Layout") { appState.workspace = .layout }
                .keyboardShortcut("2", modifiers: [.command, .control])
            Button("Integration") { appState.workspace = .integration }
                .keyboardShortcut("3", modifiers: [.command, .control])
            Button("Review") { appState.workspace = .review }
                .keyboardShortcut("4", modifiers: [.command, .control])
            Divider()
            // ⌃⌘ to leave ⇧⌘N free for File > New Project.
            Button("Visual Mode") { appState.schematicMode = .visual }
                .keyboardShortcut("v", modifiers: [.command, .control])
                .disabled(appState.workspace != .schematicCapture)
            Button("Netlist Mode") { appState.schematicMode = .netlist }
                .keyboardShortcut("n", modifiers: [.command, .control])
                .disabled(appState.workspace != .schematicCapture)
        }
    }

    // MARK: - Simulation Menu

    @CommandsBuilder
    private var simulationCommands: some Commands {
        CommandMenu("Simulation") {
            Button("Run") { runActiveSimulation() }
                .keyboardShortcut("r")
                .disabled(runDisabled)
            Button("Stop") { appState.cancelSimulation(service: services.designFlowService) }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!appState.isSimulating)
            Divider()
            Button("Operating Point") {
                appState.selectedAnalysis = .op
            }
            Button("Transient (1ms)") {
                appState.selectedAnalysis = .tran(TranSpec(stopTime: 1e-3, stepTime: 10e-6))
            }
            Button("AC Sweep (1Hz–1MHz)") {
                appState.selectedAnalysis = .ac(ACSpec(
                    scaleType: .decade, numberOfPoints: 20,
                    startFrequency: 1, stopFrequency: 1e6
                ))
            }
            Button("DC Sweep (V1, 0–5V)") {
                appState.selectedAnalysis = .dcSweep(DCSweepSpec(
                    source: "V1", startValue: 0, stopValue: 5, stepValue: 0.1
                ))
            }
        }
    }

    private var runDisabled: Bool {
        if appState.isSimulating { return true }
        guard appState.workspace == .schematicCapture else { return true }
        switch appState.schematicMode {
        case .visual:
            return project.schematicViewModel.document.components.isEmpty
                || project.schematicViewModel.hasErrors
        case .netlist:
            if appState.spiceSource.isEmpty { return true }
            guard let info = appState.netlistInfo else { return true }
            return info.hasErrors || info.components.isEmpty
        }
    }

    private func runActiveSimulation() {
        Task { @MainActor in
            switch appState.schematicMode {
            case .visual:
                await appState.runSchematicSimulation(
                    document: project.schematicViewModel.document,
                    library: project.cellLibrary,
                    analysisCommand: appState.selectedAnalysis,
                    service: services.designFlowService
                )
            case .netlist:
                await appState.runSimulation(service: services.designFlowService)
            }
        }
    }

    // MARK: - Layout Menu

    @CommandsBuilder
    private var layoutCommands: some Commands {
        CommandMenu("Layout") {
            Button("Generate Layout") {
                services.layoutPersistenceService.generateLayout(
                    project: project,
                    appState: appState,
                    designFlow: services.designFlowService,
                    catalog: services.catalog
                )
                appState.workspace = .integration
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(!canGenerateLayout)

            Button("Run DRC") {
                project.layoutViewModel.runDRC()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Run PEX") {
                Task { @MainActor in
                    await runPEXAndExportCircuit()
                }
            }
            .keyboardShortcut("x", modifiers: [.command, .shift])
            .disabled(runPEXDisabled)

            Divider()

            Button(project.techName.map { "Load Tech File... (current: \($0))" } ?? "Load Tech File...") {
                loadTechFile()
            }
        }
    }

    private var canGenerateLayout: Bool {
        !project.schematicViewModel.document.components.isEmpty
            && !project.schematicViewModel.document.wires.isEmpty
    }

    private var runPEXDisabled: Bool {
        appState.isRunningPEX || appState.projectRootURL == nil || project.designUnit == nil
    }

    // MARK: - File Operations

    private func newProject() {
        let panel = NSSavePanel()
        panel.title = "New Project"
        panel.nameFieldLabel = "Project Name:"
        panel.nameFieldStringValue = "Untitled"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.folder]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
            try services.projectService.createProject(at: url)
            try services.projectService.installTemplate(
                try NewProjectTemplate.cmosInverter(),
                forProjectAt: url
            )

            let root = try services.fileSystemService.scanDirectory(at: url)
            appState.projectRootURL = url
            appState.projectRoot = root
            appState.spiceSource = ""
            appState.lastSavedSpiceSource = ""
            appState.spiceFileName = nil
            appState.selectedFileURL = nil
            appState.simulationResult = nil
            appState.simulationError = nil

            loadProjectConfig(from: url)
            autoLoadNetlist(from: url)
            noteRecent(url, kind: .projectFolder)

            appState.log(
                "Created project at \(url.lastPathComponent) with the CMOS inverter sample",
                kind: .success
            )
        } catch {
            appState.log("Failed to create project: \(error.localizedDescription)", kind: .error)
        }
    }

    private func openSPICEFile() {
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
                noteRecent(url, kind: .netlistFile)
            } catch {
                appState.simulationError = "Failed to load file: \(error.localizedDescription)"
            }
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try openProjectFolder(at: url)
            noteRecent(url, kind: .projectFolder)
        } catch {
            appState.simulationError = "Failed to open folder: \(error.localizedDescription)"
        }
    }

    private func openProjectFolder(at url: URL) throws {
        let root = try services.fileSystemService.scanDirectory(at: url)
        appState.projectRootURL = url
        appState.projectRoot = root

        if services.projectService.isProject(url) {
            loadProjectConfig(from: url)
        }

        autoLoadNetlist(from: url)
    }

    // MARK: - Open Recent

    private func openRecent(_ document: RecentDocument) {
        do {
            let url = try services.recentDocumentsStore.beginAccess(to: document)
            switch document.kind {
            case .projectFolder:
                try openProjectFolder(at: url)
            case .netlistFile:
                try appState.loadSPICEFile(url: url)
            }
            noteRecent(url, kind: document.kind)
        } catch {
            appState.log(
                "Failed to open \(document.displayName): \(error.localizedDescription)",
                kind: .error
            )
            removeRecent(document)
        }
    }

    private func noteRecent(_ url: URL, kind: RecentDocument.Kind) {
        do {
            try services.recentDocumentsStore.noteOpened(url, kind: kind)
        } catch {
            appState.log(
                "Could not add \(url.lastPathComponent) to Open Recent: \(error.localizedDescription)",
                kind: .warning
            )
        }
    }

    private func removeRecent(_ document: RecentDocument) {
        do {
            try services.recentDocumentsStore.remove(document)
            appState.log(
                "Removed \(document.displayName) from Open Recent",
                kind: .warning
            )
        } catch {
            appState.log(
                "Could not update Open Recent: \(error.localizedDescription)",
                kind: .warning
            )
        }
    }

    private func loadProjectConfig(from projectRoot: URL) {
        do {
            try services.projectService.ensurePEXProjectFiles(forProjectAt: projectRoot)
        } catch {
            appState.log("Could not prepare PEX files: \(error.localizedDescription)", kind: .warning)
        }

        do {
            let config = try services.projectService.loadWorkspaceConfig(forProjectAt: projectRoot)
            appState.apply(config)
        } catch {
            appState.log("Could not load workspace config: \(error.localizedDescription)", kind: .warning)
        }

        loadCells(from: projectRoot)

        do {
            let config = try services.projectService.loadSimulationConfig(forProjectAt: projectRoot)
            appState.apply(config)
        } catch {
            // Not an error — config may not exist yet
        }

        var restoredLayouts: [String] = []
        for workspace in project.cells {
            do {
                if try services.layoutPersistenceService.restoreLayout(
                    into: workspace,
                    fromProjectAt: projectRoot
                ) {
                    restoredLayouts.append(workspace.name)
                }
            } catch {
                appState.log(
                    "Could not restore the saved layout of \(workspace.name): \(error.localizedDescription)",
                    kind: .warning
                )
            }
        }
        if !restoredLayouts.isEmpty {
            appState.log("Restored layout: \(restoredLayouts.joined(separator: ", "))", kind: .info)
        }
    }

    /// Rebuilds the session's cell set from `cells/` and the project
    /// manifest. A project without cells resets the session to a single
    /// empty cell so content from a previously open project never leaks in.
    private func loadCells(from projectRoot: URL) {
        do {
            let cellNames = try services.projectService.listCellNames(forProjectAt: projectRoot)
            guard !cellNames.isEmpty else {
                try project.replaceCells(
                    [(name: StudioSession.defaultCellName, schematic: SchematicDocument())],
                    topCell: StudioSession.defaultCellName,
                    activeCell: StudioSession.defaultCellName
                )
                return
            }

            var loaded: [(name: String, schematic: SchematicDocument)] = []
            for name in cellNames {
                let document = try services.projectService.loadCellSchematic(
                    cellName: name,
                    forProjectAt: projectRoot
                )
                loaded.append((name: name, schematic: document))
            }

            let manifest = try services.projectService.loadProjectManifestIfPresent(forProjectAt: projectRoot)
            var topCell = manifest?.topCell ?? cellNames[0]
            if !cellNames.contains(topCell) {
                appState.log(
                    "Manifest top cell '\(topCell)' does not exist; using '\(cellNames[0])'",
                    kind: .warning
                )
                topCell = cellNames[0]
            }
            var activeCell = manifest?.activeCell ?? topCell
            if !cellNames.contains(activeCell) {
                appState.log(
                    "Manifest active cell '\(activeCell)' does not exist; using '\(topCell)'",
                    kind: .warning
                )
                activeCell = topCell
            }

            try project.replaceCells(loaded, topCell: topCell, activeCell: activeCell)
        } catch {
            appState.log("Could not load project cells: \(error.localizedDescription)", kind: .error)
        }
    }

    private func autoLoadNetlist(from projectRoot: URL) {
        let topCir = projectRoot.appending(path: "top.cir")
        if FileManager.default.fileExists(atPath: topCir.path(percentEncoded: false)) {
            do {
                try appState.loadSPICEFile(url: topCir)
            } catch {
                appState.log("Failed to load top.cir: \(error.localizedDescription)", kind: .warning)
            }
        }
    }

    // MARK: - Save

    /// Hands the quit guard live closures over the session state so
    /// quitting with unsaved netlist, schematic, or layout changes prompts
    /// instead of silently discarding work.
    private func wireTerminationGuard() {
        appDelegate.hasUnsavedChanges = {
            appState.isNetlistDirty || project.hasUnsavedChanges
        }
        appDelegate.performSave = { saveAction() }
    }

    private func saveAction() {
        if let projectRoot = appState.projectRootURL {
            saveProject(projectRoot: projectRoot)
        } else {
            do {
                try appState.saveSPICEFile()
            } catch {
                appState.log("Save failed: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    private func saveProject(projectRoot: URL) {
        do {
            try services.projectService.ensurePEXProjectFiles(forProjectAt: projectRoot)

            try services.projectService.saveWorkspaceConfig(
                appState.workspaceConfig(),
                forProjectAt: projectRoot
            )

            // Mirror the session's cell set onto disk: prune directories of
            // removed cells, then write every cell's schematic.
            let onDiskCells = try services.projectService.listCellNames(forProjectAt: projectRoot)
            let sessionCellNames = Set(project.cells.map(\.name))
            for stale in onDiskCells where !sessionCellNames.contains(stale) {
                try services.projectService.removeCellDirectory(
                    cellName: stale,
                    forProjectAt: projectRoot
                )
            }
            for workspace in project.cells {
                try services.projectService.saveCellSchematic(
                    workspace.schematicViewModel.document,
                    cellName: workspace.name,
                    forProjectAt: projectRoot
                )
            }
            try services.projectService.saveProjectManifest(
                ProjectManifest(
                    topCell: project.topCellName,
                    activeCell: project.activeCellName
                ),
                forProjectAt: projectRoot
            )

            try services.projectService.saveSimulationConfig(
                appState.simulationConfig(),
                forProjectAt: projectRoot
            )

            if !appState.spiceSource.isEmpty {
                let fileName = appState.spiceFileName ?? "top.cir"
                try services.projectService.saveNetlist(
                    appState.spiceSource,
                    named: fileName,
                    inProjectAt: projectRoot
                )
            }

            try services.layoutPersistenceService.persistAllLayouts(
                of: project,
                toProjectAt: projectRoot
            )

            appState.lastSavedSpiceSource = appState.spiceSource
            for workspace in project.cells {
                workspace.markSchematicSaved()
            }
            appState.log("Project saved", kind: .success)
        } catch {
            appState.log("Save failed: \(error.localizedDescription)", kind: .error)
        }
    }

    // MARK: - Export

    /// Saves the current layout as a GDS or OASIS file at a user-chosen
    /// location — the save path for layouts outside an open project, and
    /// the tapeout handoff for layouts inside one.
    private func exportLayout() {
        let panel = NSSavePanel()
        panel.title = "Export Layout"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "gds")!,
            UTType(filenameExtension: "oas")!,
        ]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue =
            (appState.projectRootURL?.lastPathComponent ?? project.designName) + ".gds"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let format: LayoutFileFormat = url.pathExtension.lowercased() == "oas" ? .oasis : .gds
        do {
            let converter = MaskDataFormatConverter(tech: project.layoutViewModel.tech)
            try converter.exportDocument(
                project.layoutViewModel.editor.document,
                to: url,
                format: format
            )
            appState.log("Exported layout to \(url.lastPathComponent)", kind: .success)
        } catch {
            appState.log("Layout export failed: \(error.localizedDescription)", kind: .error)
        }
    }

    // MARK: - Tech File

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

    // MARK: - PEX

    @MainActor
    private func runPEXAndExportCircuit() async {
        guard let projectRoot = appState.projectRootURL else {
            appState.log("Open a project folder before running PEX.", kind: .warning)
            return
        }
        guard project.designUnit != nil else {
            appState.log("Generate layout before running PEX.", kind: .warning)
            return
        }
        guard !appState.spiceSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appState.log("Netlist is empty.", kind: .warning)
            return
        }

        appState.isRunningPEX = true
        appState.showDebugArea = true
        appState.debugAreaTab = .console
        appState.log("Preparing PEX inputs...", kind: .info)
        defer { appState.isRunningPEX = false }

        do {
            try services.projectService.ensurePEXProjectFiles(forProjectAt: projectRoot)
            let config = try services.projectService.loadPEXProjectConfig(forProjectAt: projectRoot)

            try services.projectService.saveNetlist(
                appState.spiceSource,
                toProjectRelativePath: config.inputs.netlist,
                inProjectAt: projectRoot
            )
            try services.projectService.saveLayout(
                document: project.layoutViewModel.editor.document,
                tech: project.layoutViewModel.tech,
                toProjectRelativePath: config.inputs.layout,
                inProjectAt: projectRoot
            )

            appState.log("Running pexengine extract...", kind: .info)
            let designFlowService = services.designFlowService
            let configURL = services.projectService.pexTOMLURL(inProjectAt: projectRoot)
            let extraction = try await Task.detached(priority: .userInitiated) {
                try await designFlowService.runPEXExtraction(DesignFlowPEXExtractionRequest(
                    configURL: configURL,
                    workingDirectory: projectRoot,
                    cornerID: config.normalizedCorners.first ?? "tt_25c_1v0",
                    executablePath: config.executablePath
                ))
            }.value

            if let result = extraction.commandResult, !result.standardOutput.isEmpty {
                appState.log(result.standardOutput, kind: .output)
            }
            if let result = extraction.commandResult, !result.standardError.isEmpty {
                appState.log(result.standardError, kind: .warning)
            }
            for diagnostic in extraction.ir.diagnostics {
                appState.log(diagnostic.message, kind: .warning)
            }

            let postNetlistURL = try writePostPEXNetlist(
                projectRoot: projectRoot,
                baseNetlist: appState.spiceSource,
                parasitics: extraction.ir
            )
            appState.pexOutputNetlistURL = postNetlistURL
            appState.log(
                "PEX complete. Loaded \(extraction.ir.elements.count) parasitics from \(extraction.manifestURL.lastPathComponent) and wrote \(postNetlistURL.lastPathComponent)",
                kind: .success
            )
        } catch {
            appState.log("PEX failed: \(error.localizedDescription)", kind: .error)
        }
    }

    private func writePostPEXNetlist(
        projectRoot: URL,
        baseNetlist: String,
        parasitics: PEXParasiticIR
    ) throws -> URL {
        let outputURL = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "pex")
            .appending(path: "post_pex.cir")
        let parent = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let postLayoutNetlist = services.designFlowService.buildPostLayoutNetlist(
            baseNetlist: baseNetlist,
            parasitics: parasitics
        )
        try postLayoutNetlist.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }
}
