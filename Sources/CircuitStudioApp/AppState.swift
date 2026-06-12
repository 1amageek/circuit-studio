import SwiftUI
import AppKit
import CircuitStudioCore
import CoreSpiceWaveform
import Synchronization

/// Design flow workspace defining the panel layout and available actions.
public enum Workspace: String, Hashable, Sendable, Codable {
    /// Circuit design & simulation: schematic or netlist editor + waveform viewer
    case schematicCapture
    /// Physical layout editing with DRC
    case layout
    /// Side-by-side schematic + layout for SDL/LVS workflows
    case integration
    /// Manifest-backed run review: stages, gates, artifacts and
    /// approval decisions over the .xcircuite ledger
    case review
}

/// Sub-mode within the schematicCapture workspace.
public enum SchematicMode: String, Hashable, Sendable, Codable {
    /// Visual schematic editor (SchematicEditorView)
    case visual
    /// Text-based SPICE netlist editor (NetlistEditorView)
    case netlist
}

/// Active tab in the navigator (left sidebar). Mirrors Xcode's navigator pattern.
public enum NavigatorTab: String, Hashable, Sendable, Codable, CaseIterable {
    case project
    case schematic
    case layout
    case issues
    case simulation
}

/// Active tab in the inspector (right sidebar). Mirrors Xcode's inspector pattern.
public enum InspectorTab: String, Hashable, Sendable, Codable, CaseIterable {
    case properties
    case process
    case analysis
    case waveform
}

/// Active tab in the debug area (bottom). Mirrors Xcode's debug area.
public enum DebugAreaTab: String, Hashable, Sendable, Codable, CaseIterable {
    case console
    case issues
}

/// A single entry in the simulation console.
public struct ConsoleEntry: Identifiable, Sendable {
    public enum Kind: Sendable {
        case info
        case warning
        case error
        case success
        case output
    }

    public let id: UUID
    public let timestamp: Date
    public let message: String
    public let kind: Kind

    public init(message: String, kind: Kind = .info) {
        self.id = UUID()
        self.timestamp = Date()
        self.message = message
        self.kind = kind
    }
}

/// Application-wide state.
@Observable
@MainActor
public final class AppState {
    // Navigation
    public var workspace: Workspace = .schematicCapture
    public var schematicMode: SchematicMode = .netlist

    // Pane visibility
    public var showInspector: Bool = false
    public var showDebugArea: Bool = false
    /// Waveform pane split below the editor in the main content area.
    public var showWaveformPane: Bool = false

    // Pane-tab selection
    public var navigatorTab: NavigatorTab = .project
    public var inspectorTab: InspectorTab = .properties
    public var debugAreaTab: DebugAreaTab = .console

    // Project
    public var projectRootURL: URL?
    public var projectRoot: FileNode?
    public var selectedFileURL: URL?

    // SPICE source
    public var spiceSource: String = ""
    public var spiceFileName: String?
    /// Source content as of the last load or save — the dirty baseline.
    public var lastSavedSpiceSource: String = ""

    /// True when the SPICE source differs from the last loaded/saved content.
    public var isNetlistDirty: Bool {
        spiceSource != lastSavedSpiceSource
    }

    // Simulation
    public var isSimulating: Bool = false
    public var simulationStatus: String?
    public var simulationResult: SimulationResult?
    public var simulationError: String?
    public var selectedAnalysis: AnalysisCommand = .op
    public var processConfiguration: ProcessConfiguration = ProcessConfiguration()
    public var isRunningPEX: Bool = false
    public var pexOutputNetlistURL: URL?

    /// Partial waveform data received during a running transient simulation.
    /// Updated progressively as timesteps complete.
    public var streamingWaveform: WaveformData?
    /// Incremented each time `streamingWaveform` is updated, for observation.
    public var streamingWaveformVersion: Int = 0

    // Console
    public var consoleEntries: [ConsoleEntry] = []

    // Live parsing
    public var netlistInfo: NetlistInfo?
    private var parseTask: Task<Void, Never>?

    public init() {}

    // MARK: - Project Config Extraction / Restoration

    /// Extracts current workspace state for persistence.
    public func workspaceConfig() -> WorkspaceConfig {
        WorkspaceConfig(
            activeWorkspace: workspace.rawValue,
            schematicMode: schematicMode.rawValue,
            panels: WorkspaceConfig.PanelState(
                inspector: showInspector,
                console: showDebugArea && debugAreaTab == .console,
                simulationResults: showWaveformPane
            )
        )
    }

    /// Extracts current simulation settings for persistence.
    public func simulationConfig() -> SimulationConfig {
        SimulationConfig(
            selectedAnalysis: selectedAnalysis,
            processConfiguration: processConfiguration
        )
    }

    /// Restores workspace state from a persisted config.
    public func apply(_ config: WorkspaceConfig) {
        workspace = Workspace(rawValue: config.activeWorkspace) ?? .schematicCapture
        schematicMode = SchematicMode(rawValue: config.schematicMode) ?? .netlist
        showInspector = config.panels.inspector
        showWaveformPane = config.panels.simulationResults
        if config.panels.console {
            showDebugArea = true
            debugAreaTab = .console
        } else {
            showDebugArea = false
        }
    }

    /// Restores simulation settings from a persisted config.
    public func apply(_ config: SimulationConfig) {
        selectedAnalysis = config.selectedAnalysis
        processConfiguration = config.processConfiguration
    }

    // MARK: - Console

    public func log(_ message: String, kind: ConsoleEntry.Kind = .info) {
        consoleEntries.append(ConsoleEntry(message: message, kind: kind))
        if kind == .info {
            simulationStatus = message
        }
    }

    public func clearConsole() {
        consoleEntries.removeAll()
        simulationStatus = nil
    }

    /// Cancel the currently running simulation.
    public func cancelSimulation(service: DesignFlowService) {
        guard service.cancelActiveSimulation() != nil else { return }
        log("Simulation cancelled", kind: .warning)
    }

    /// Load a SPICE file from disk.
    public func loadSPICEFile(url: URL) throws {
        let source = try String(contentsOf: url, encoding: .utf8)
        spiceSource = source
        lastSavedSpiceSource = source
        spiceFileName = url.lastPathComponent
        selectedFileURL = url
        simulationResult = nil
        simulationError = nil
    }

    // MARK: - Live Parsing

    /// Schedule a debounced parse of the current SPICE source.
    ///
    /// Cancels any pending parse and waits 300ms before parsing.
    /// This avoids redundant work while the user is typing.
    public func scheduleNetlistParse(service: NetlistParsingService) {
        parseTask?.cancel()
        let source = spiceSource
        let fileName = spiceFileName
        let process = processConfiguration.isEmpty ? nil : processConfiguration
        parseTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let info = await service.parse(
                source: source,
                fileName: fileName,
                processConfiguration: process
            )
            guard !Task.isCancelled else { return }
            self.netlistInfo = info
        }
    }

    /// Save the current SPICE source to the already-selected file, or prompt with Save As.
    public func saveSPICEFile() throws {
        if let url = selectedFileURL {
            try spiceSource.write(to: url, atomically: true, encoding: .utf8)
            lastSavedSpiceSource = spiceSource
            log("Saved \(url.lastPathComponent)", kind: .success)
        } else {
            saveSPICEFileAs()
        }
    }

    /// Show a save panel and write the SPICE source to a new file.
    public func saveSPICEFileAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "cir")!,
            .init(filenameExtension: "spice")!,
        ]
        panel.nameFieldStringValue = spiceFileName ?? "untitled.cir"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try spiceSource.write(to: url, atomically: true, encoding: .utf8)
            lastSavedSpiceSource = spiceSource
            selectedFileURL = url
            spiceFileName = url.lastPathComponent
            log("Saved \(url.lastPathComponent)", kind: .success)
        } catch {
            log("Failed to save: \(error.localizedDescription)", kind: .error)
        }
    }

    /// Run simulation using the loaded SPICE source.
    public func runSimulation(service: DesignFlowService) async {
        guard !spiceSource.isEmpty else {
            simulationError = "No SPICE source loaded"
            return
        }

        isSimulating = true
        simulationError = nil
        streamingWaveform = nil
        clearConsole()
        showDebugArea = true
        debugAreaTab = .console

        let start = Date()
        log("Running simulation...")
        let process = processConfiguration.isEmpty ? nil : processConfiguration

        // Bridge streaming callbacks from background queue to MainActor
        let (stream, continuation) = AsyncStream<WaveformData>.makeStream()
        let handler: @Sendable (WaveformData) -> Void = { waveform in
            continuation.yield(waveform)
        }

        let updateTask = Task {
            for await waveform in stream {
                self.streamingWaveform = waveform
                self.streamingWaveformVersion += 1
            }
        }

        do {
            let result = try await service.runSPICESimulation(DesignFlowSPICESimulationRequest(
                source: spiceSource,
                fileName: spiceFileName,
                processConfiguration: process,
                onWaveformUpdate: handler
            ))
            continuation.finish()
            _ = await updateTask.value
            simulationResult = result
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))
            log("Completed (\(elapsed)s)", kind: .success)
            focusSimulationOutcome(result)
        } catch {
            continuation.finish()
            updateTask.cancel()
            log(error.localizedDescription, kind: .error)
            simulationError = error.localizedDescription
        }

        streamingWaveform = nil
        simulationStatus = nil
        isSimulating = false
    }

    /// Brings up the waveform pane in the main editor area when a completed
    /// run produced a plottable waveform, and puts away the debug area that
    /// the run start opened. Runs without a waveform (e.g. operating point)
    /// and failed runs keep the console, where their output lives.
    private func focusSimulationOutcome(_ result: SimulationResult) {
        guard (result.waveform?.pointCount ?? 0) > 1 else { return }
        showWaveformPane = true
        showDebugArea = false
    }

    /// Run simulation from a schematic document by generating a SPICE netlist.
    public func runSchematicSimulation(
        document: SchematicDocument,
        analysisCommand: AnalysisCommand,
        service: DesignFlowService
    ) async {
        isSimulating = true
        simulationError = nil
        streamingWaveform = nil
        clearConsole()
        showDebugArea = true
        debugAreaTab = .console

        let start = Date()

        log("Generating netlist...")
        let testbench = Testbench(
            name: "Quick",
            analysisCommands: [analysisCommand]
        )
        let process = processConfiguration.isEmpty ? nil : processConfiguration
        let analysisName: String = {
            switch analysisCommand {
            case .op: return "Operating Point"
            case .tran: return "Transient"
            case .ac: return "AC"
            case .dcSweep: return "DC Sweep"
            case .noise: return "Noise"
            case .tf: return "Transfer Function"
            case .pz: return "Pole-Zero"
            }
        }()
        log("Running \(analysisName) analysis...")

        // Bridge streaming callbacks from background queue to MainActor
        let (stream, continuation) = AsyncStream<WaveformData>.makeStream()
        let handler: @Sendable (WaveformData) -> Void = { waveform in
            continuation.yield(waveform)
        }

        let updateTask = Task {
            for await waveform in stream {
                self.streamingWaveform = waveform
                self.streamingWaveformVersion += 1
            }
        }

        do {
            let flowResult = try await service.runSchematicSimulation(DesignFlowSchematicSimulationRequest(
                schematic: document,
                testbench: testbench,
                processConfiguration: process,
                onWaveformUpdate: handler
            ))
            log(flowResult.netlist, kind: .output)
            continuation.finish()
            _ = await updateTask.value
            simulationResult = flowResult.simulationResult
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))
            log("Completed (\(elapsed)s)", kind: .success)
            focusSimulationOutcome(flowResult.simulationResult)
        } catch {
            continuation.finish()
            updateTask.cancel()
            log(error.localizedDescription, kind: .error)
            simulationError = error.localizedDescription
        }

        streamingWaveform = nil
        simulationStatus = nil
        isSimulating = false
    }

    /// Run a specific analysis command.
    public func runAnalysis(command: AnalysisCommand, service: DesignFlowService) async {
        guard !spiceSource.isEmpty else {
            simulationError = "No SPICE source loaded"
            return
        }

        isSimulating = true
        simulationError = nil
        clearConsole()
        showDebugArea = true
        debugAreaTab = .console

        let start = Date()
        log("Running analysis...")

        do {
            let result = try await service.runAnalysis(
                source: spiceSource,
                fileName: spiceFileName,
                processConfiguration: processConfiguration.isEmpty ? nil : processConfiguration,
                command: command
            )
            simulationResult = result
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))
            log("Completed (\(elapsed)s)", kind: .success)
            focusSimulationOutcome(result)
        } catch {
            log(error.localizedDescription, kind: .error)
            simulationError = error.localizedDescription
        }

        simulationStatus = nil
        isSimulating = false
    }
}
