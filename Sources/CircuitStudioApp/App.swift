import SwiftUI
import AppKit
import CircuitStudioCore
import WaveformViewer
import SchematicEditor
import LayoutEditor
import UniformTypeIdentifiers

public struct CircuitStudioApp: App {
    @State private var appState = AppState()
    @State private var services = ServiceContainer()
    @State private var project = DesignProject()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView(
                appState: appState,
                services: services,
                project: project
            )
            .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 1200, height: 700)
        .commands {
            fileCommands
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
            Button("New Project...") { newProject() }
                .keyboardShortcut("n")
            Divider()
            Button("Open...") { openSPICEFile() }
                .keyboardShortcut("o")
            Button("Open Folder...") { openFolder() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Save") { saveAction() }
                .keyboardShortcut("s")
                .disabled(appState.spiceSource.isEmpty && appState.projectRootURL == nil)
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
        case .schematic: return "Schematic Navigator"
        case .layout: return "Layout Navigator"
        case .issues: return "Issues Navigator"
        case .simulation: return "Simulation Navigator"
        }
    }

    private func navigatorTabShortcut(_ tab: NavigatorTab) -> KeyEquivalent {
        switch tab {
        case .project: return "1"
        case .schematic: return "2"
        case .layout: return "3"
        case .issues: return "4"
        case .simulation: return "5"
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
            Divider()
            Button("Visual Mode") { appState.schematicMode = .visual }
                .keyboardShortcut("V", modifiers: [.command, .shift])
                .disabled(appState.workspace != .schematicCapture)
            Button("Netlist Mode") { appState.schematicMode = .netlist }
                .keyboardShortcut("N", modifiers: [.command, .shift])
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
                project.generateLayout(service: services.designFlowService, catalog: services.catalog)
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

            let root = try services.fileSystemService.scanDirectory(at: url)
            appState.projectRootURL = url
            appState.projectRoot = root
            appState.spiceSource = ""
            appState.spiceFileName = nil
            appState.selectedFileURL = nil
            appState.simulationResult = nil
            appState.simulationError = nil

            appState.log("Created project at \(url.lastPathComponent)", kind: .success)
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
            let root = try services.fileSystemService.scanDirectory(at: url)
            appState.projectRootURL = url
            appState.projectRoot = root

            if services.projectService.isProject(url) {
                loadProjectConfig(from: url)
            }

            autoLoadNetlist(from: url)
        } catch {
            appState.simulationError = "Failed to open folder: \(error.localizedDescription)"
        }
    }

    private func loadProjectConfig(from projectRoot: URL) {
        do {
            try services.projectService.ensurePEXProjectFiles(projectRoot: projectRoot)
        } catch {
            appState.log("Could not prepare PEX files: \(error.localizedDescription)", kind: .warning)
        }

        do {
            let config = try services.projectService.loadWorkspaceConfig(projectRoot: projectRoot)
            appState.apply(config)
        } catch {
            appState.log("Could not load workspace config: \(error.localizedDescription)", kind: .warning)
        }

        do {
            let placement = try services.projectService.loadSchematicPlacement(projectRoot: projectRoot)
            project.apply(placement)
            appState.spiceSource = placement.sourceNetlist
        } catch {
            // Not an error — placement may not exist yet
        }

        do {
            let config = try services.projectService.loadSimulationConfig(projectRoot: projectRoot)
            appState.apply(config)
        } catch {
            // Not an error — config may not exist yet
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
            try services.projectService.ensurePEXProjectFiles(projectRoot: projectRoot)

            try services.projectService.saveWorkspaceConfig(
                appState.workspaceConfig(),
                projectRoot: projectRoot
            )

            try services.projectService.saveSchematicPlacement(
                project.schematicPlacement(sourceNetlist: appState.spiceSource),
                projectRoot: projectRoot
            )

            try services.projectService.saveSimulationConfig(
                appState.simulationConfig(),
                projectRoot: projectRoot
            )

            if !appState.spiceSource.isEmpty {
                let fileName = appState.spiceFileName ?? "top.cir"
                try services.projectService.saveNetlist(
                    appState.spiceSource,
                    fileName: fileName,
                    projectRoot: projectRoot
                )
            }

            if project.designUnit != nil {
                try services.projectService.saveLayout(
                    document: project.layoutViewModel.editor.document,
                    tech: project.layoutViewModel.tech,
                    to: "top.oas",
                    projectRoot: projectRoot
                )
            }

            appState.log("Project saved", kind: .success)
        } catch {
            appState.log("Save failed: \(error.localizedDescription)", kind: .error)
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
            try services.projectService.ensurePEXProjectFiles(projectRoot: projectRoot)
            let config = try services.projectService.loadPEXProjectConfig(projectRoot: projectRoot)

            try services.projectService.saveNetlist(
                appState.spiceSource,
                relativePath: config.inputs.netlist,
                projectRoot: projectRoot
            )
            try services.projectService.saveLayout(
                document: project.layoutViewModel.editor.document,
                tech: project.layoutViewModel.tech,
                relativePath: config.inputs.layout,
                projectRoot: projectRoot
            )

            appState.log("Running pexengine extract...", kind: .info)
            let designFlowService = services.designFlowService
            let configPath = services.projectService.pexConfigPath(projectRoot: projectRoot)
            let extraction = try await Task.detached(priority: .userInitiated) {
                try designFlowService.runPEXExtraction(DesignFlowPEXExtractionRequest(
                    configURL: configPath,
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
                "PEX complete. Loaded \(extraction.ir.elements.count) parasitics from \(extraction.artifacts.manifestURL.lastPathComponent) and wrote \(postNetlistURL.lastPathComponent)",
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
