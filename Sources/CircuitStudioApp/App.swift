import SwiftUI
import AppKit
import CircuitStudioCore
import WaveformViewer
import SchematicEditor
import LayoutEditor

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
            CommandGroup(replacing: .newItem) {
                Button("New Project...") {
                    newProject()
                }
                .keyboardShortcut("n")

                Divider()

                Button("Open...") {
                    openSPICEFile()
                }
                .keyboardShortcut("o")

                Button("Open Folder...") {
                    openFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("Save") {
                    saveAction()
                }
                .keyboardShortcut("s")
                .disabled(appState.spiceSource.isEmpty && appState.projectRootURL == nil)
            }
        }
    }

    // MARK: - File Operations

    private func newProject() {
        let panel = NSSavePanel()
        panel.title = "New Project"
        panel.nameFieldLabel = "Project Name:"
        panel.nameFieldStringValue = "Untitled"
        panel.canCreateDirectories = true
        // Prompt user to choose a location; we create a directory there.
        panel.allowedContentTypes = [.folder]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            // Create directory if it doesn't exist
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
            try services.projectService.createProject(at: url)

            // Set up app state
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

            // Detect and load .xcircuite/ project config
            if services.projectService.isProject(url) {
                loadProjectConfig(from: url)
            }

            // Auto-detect .cir files in the project root
            autoLoadNetlist(from: url)
        } catch {
            appState.simulationError = "Failed to open folder: \(error.localizedDescription)"
        }
    }

    private func loadProjectConfig(from projectRoot: URL) {
        // Load workspace config
        do {
            let config = try services.projectService.loadWorkspaceConfig(projectRoot: projectRoot)
            appState.apply(config)
        } catch {
            appState.log("Could not load workspace config: \(error.localizedDescription)", kind: .warning)
        }

        // Load schematic placement
        do {
            let placement = try services.projectService.loadSchematicPlacement(projectRoot: projectRoot)
            project.apply(placement)
            appState.spiceSource = placement.sourceNetlist
        } catch {
            // Not an error — placement may not exist yet
        }

        // Load simulation config
        do {
            let config = try services.projectService.loadSimulationConfig(projectRoot: projectRoot)
            appState.apply(config)
        } catch {
            // Not an error — config may not exist yet
        }
    }

    private func autoLoadNetlist(from projectRoot: URL) {
        // Look for top.cir or any .cir file
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
            // Workspace config
            try services.projectService.saveWorkspaceConfig(
                appState.workspaceConfig(),
                projectRoot: projectRoot
            )

            // Schematic placement
            try services.projectService.saveSchematicPlacement(
                project.schematicPlacement(sourceNetlist: appState.spiceSource),
                projectRoot: projectRoot
            )

            // Simulation config
            try services.projectService.saveSimulationConfig(
                appState.simulationConfig(),
                projectRoot: projectRoot
            )

            // Netlist
            if !appState.spiceSource.isEmpty {
                let fileName = appState.spiceFileName ?? "top.cir"
                try services.projectService.saveNetlist(
                    appState.spiceSource,
                    fileName: fileName,
                    projectRoot: projectRoot
                )
            }

            // Layout (if generated)
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
}
