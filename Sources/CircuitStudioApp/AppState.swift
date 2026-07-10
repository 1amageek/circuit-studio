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
    case cells
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

/// In-memory status of deriving a visual schematic from the loaded SPICE deck.
public enum NetlistSchematicMaterializationState: Sendable, Equatable {
    case none
    case succeeded(String)
    case failed(String)
}

/// Where the waveform shown in the waveform pane came from. The
/// terminal-component trace filter only applies to live runs, whose trace
/// names match the open schematic.
public enum FocusedWaveformSource: Sendable {
    case liveRun
    case overlay
    case history
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

    /// New Cell sheet (File > New Cell…), presented by ContentView.
    public var isNewCellSheetPresented: Bool = false

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
    public var netlistSchematicMaterializationState: NetlistSchematicMaterializationState = .none

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

    // Corner matrix
    /// One stable generic PVT instance per session — `CornerSet.genericPVT()`
    /// mints fresh corner UUIDs on every call, so selection must reference
    /// a single stored set.
    public let genericCornerSet: CornerSet = .genericPVT()
    /// Corners (by ID, within `availableCorners`) selected for matrix runs.
    public var selectedCornerIDs: Set<UUID> = []
    /// In-session projection cache of runs already persisted in `.xcircuite`.
    public var runHistory: [AnalysisRunBatch] = []

    // Focused waveform (what the waveform pane shows)
    public var focusedWaveform: WaveformData?
    public var focusedWaveformSource: FocusedWaveformSource = .liveRun
    /// Incremented each time `focusedWaveform` is set, for observation.
    public var focusedWaveformVersion: Int = 0

    /// Corners offered for matrix runs: the loaded technology's corners,
    /// or the built-in generic PVT set when no technology defines any.
    public var availableCorners: [Corner] {
        if let corners = processConfiguration.technology?.cornerSet.corners, !corners.isEmpty {
            return corners
        }
        return genericCornerSet.corners
    }

    /// True when no technology corner library is loaded and the generic
    /// (temperature-only) corners are in effect.
    public var usesGenericCorners: Bool {
        (processConfiguration.technology?.cornerSet.corners.isEmpty ?? true)
    }

    /// The selected corners in `availableCorners` order.
    public var selectedCorners: [Corner] {
        availableCorners.filter { selectedCornerIDs.contains($0.id) }
    }

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
            processConfiguration: processConfiguration,
            matrixCornerNames: selectedCorners.map(\.name)
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
        // Resolve by name after the configuration is in place, because
        // availableCorners depends on the restored technology.
        let names = Set(config.matrixCornerNames)
        selectedCornerIDs = Set(availableCorners.filter { names.contains($0.name) }.map(\.id))
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
        netlistSchematicMaterializationState = .none
        simulationResult = nil
        simulationError = nil
    }

    /// Clears the loaded SPICE file and its parse/simulation state.
    public func clearSPICEFile() {
        parseTask?.cancel()
        parseTask = nil
        spiceSource = ""
        lastSavedSpiceSource = ""
        spiceFileName = nil
        selectedFileURL = nil
        netlistSchematicMaterializationState = .none
        netlistInfo = nil
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
        panel.allowedContentTypes = FileContentTypes.spiceSave
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
    public func runSimulation(
        service: DesignFlowService,
        analysis: AnalysisCommand? = nil,
        recorder: (any SimulationRunRecording)? = nil
    ) async {
        await runSimulationRecorded(
            service: service,
            analysis: analysis,
            recorder: recorder,
            recordingContext: nil,
            startedAt: nil
        )
    }

    private func runSimulationRecorded(
        service: DesignFlowService,
        analysis: AnalysisCommand?,
        recorder: (any SimulationRunRecording)?,
        recordingContext: SimulationRunContext?,
        startedAt: Date?
    ) async {
        guard !spiceSource.isEmpty else {
            simulationError = "No SPICE source loaded"
            return
        }

        let executedAnalysis = analysis ?? selectedAnalysis
        let start = startedAt ?? Date()
        let activeRecordingContext: SimulationRunContext?
        do {
            if let recordingContext {
                activeRecordingContext = recordingContext
            } else {
                activeRecordingContext = try beginSimulationRecording(
                    recorder: recorder,
                    intent: "Run \(executedAnalysis.displayName) simulation.",
                    source: spiceSource,
                    fileName: spiceFileName,
                    startedAt: start
                )
            }
        } catch {
            simulationError = error.localizedDescription
            log(error.localizedDescription, kind: .error)
            return
        }

        isSimulating = true
        simulationError = nil
        streamingWaveform = nil
        clearConsole()
        showDebugArea = true
        debugAreaTab = .console

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
            let record = AnalysisRunRecord(
                analysis: executedAnalysis,
                status: result.status,
                result: result,
                failureReason: result.status == .failed ? result.logMessages.last : nil,
                startedAt: result.startedAt,
                finishedAt: result.finishedAt
            )
            if let recorder, let activeRecordingContext {
                try await recorder.complete(
                    context: activeRecordingContext,
                    source: spiceSource,
                    records: [record]
                )
            }
            runHistory.append(AnalysisRunBatch(
                runID: activeRecordingContext?.runID,
                startedAt: start,
                records: [record]
            ))
            applySimulationOutcome(result, startedAt: start)
        } catch {
            continuation.finish()
            updateTask.cancel()
            recordSimulationFailure(
                recorder: recorder,
                context: activeRecordingContext,
                reason: error.localizedDescription
            )
            log(error.localizedDescription, kind: .error)
            simulationError = error.localizedDescription
        }

        streamingWaveform = nil
        simulationStatus = nil
        isSimulating = false
    }

    /// Routes a waveform to the waveform pane. With `reveal`, also brings the
    /// pane up and puts away the debug area that a run start opened.
    public func focusWaveform(
        _ waveform: WaveformData,
        source: FocusedWaveformSource,
        reveal: Bool = true
    ) {
        focusedWaveform = waveform
        focusedWaveformSource = source
        focusedWaveformVersion += 1
        if reveal {
            showWaveformPane = true
            showDebugArea = false
        }
    }

    /// Brings up the waveform pane in the main editor area when a completed
    /// run produced a plottable waveform, and puts away the debug area that
    /// the run start opened. Runs without a waveform (e.g. operating point)
    /// and failed runs keep the console, where their output lives.
    private func focusSimulationOutcome(_ result: SimulationResult) {
        guard result.status == .completed else { return }
        guard let waveform = result.waveform else { return }
        focusWaveform(waveform, source: .liveRun, reveal: waveform.pointCount > 1)
    }

    /// Run simulation from a schematic document by generating a SPICE netlist.
    public func runSchematicSimulation(
        document: SchematicDocument,
        library: CellLibrary = CellLibrary(),
        analysisCommand: AnalysisCommand,
        service: DesignFlowService,
        recorder: (any SimulationRunRecording)? = nil
    ) async {
        await runSchematicSimulationRecorded(
            document: document,
            library: library,
            analysisCommand: analysisCommand,
            service: service,
            recorder: recorder,
            recordingContext: nil,
            startedAt: nil
        )
    }

    private func runSchematicSimulationRecorded(
        document: SchematicDocument,
        library: CellLibrary,
        analysisCommand: AnalysisCommand,
        service: DesignFlowService,
        recorder: (any SimulationRunRecording)?,
        recordingContext: SimulationRunContext?,
        startedAt: Date?
    ) async {
        let start = startedAt ?? Date()
        let activeRecordingContext: SimulationRunContext?
        do {
            if let recordingContext {
                activeRecordingContext = recordingContext
            } else {
                activeRecordingContext = try beginSimulationRecording(
                    recorder: recorder,
                    intent: "Run \(analysisCommand.displayName) schematic simulation.",
                    source: nil,
                    fileName: "schematic.cir",
                    startedAt: start
                )
            }
        } catch {
            simulationError = error.localizedDescription
            log(error.localizedDescription, kind: .error)
            return
        }

        isSimulating = true
        simulationError = nil
        streamingWaveform = nil
        clearConsole()
        showDebugArea = true
        debugAreaTab = .console

        log("Generating netlist...")
        let testbench = Testbench(
            name: "Quick",
            analysisCommands: [analysisCommand]
        )
        let process = processConfiguration.isEmpty ? nil : processConfiguration
        log("Running \(analysisCommand.displayName) analysis...")

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
                library: library,
                testbench: testbench,
                processConfiguration: process,
                onWaveformUpdate: handler
            ))
            log(flowResult.netlist, kind: .output)
            continuation.finish()
            _ = await updateTask.value
            let record = AnalysisRunRecord(
                analysis: analysisCommand,
                status: flowResult.simulationResult.status,
                result: flowResult.simulationResult,
                failureReason: flowResult.simulationResult.status == .failed
                    ? flowResult.simulationResult.logMessages.last
                    : nil,
                startedAt: flowResult.simulationResult.startedAt,
                finishedAt: flowResult.simulationResult.finishedAt
            )
            if let recorder, let activeRecordingContext {
                try await recorder.complete(
                    context: activeRecordingContext,
                    source: flowResult.netlist,
                    records: [record]
                )
            }
            runHistory.append(AnalysisRunBatch(
                runID: activeRecordingContext?.runID,
                startedAt: start,
                records: [record]
            ))
            applySimulationOutcome(flowResult.simulationResult, startedAt: start)
        } catch {
            continuation.finish()
            updateTask.cancel()
            recordSimulationFailure(
                recorder: recorder,
                context: activeRecordingContext,
                reason: error.localizedDescription
            )
            log(error.localizedDescription, kind: .error)
            simulationError = error.localizedDescription
        }

        streamingWaveform = nil
        simulationStatus = nil
        isSimulating = false
    }

    private func applySimulationOutcome(
        _ result: SimulationResult,
        startedAt: Date
    ) {
        simulationResult = result
        let elapsed = String(format: "%.2f", Date().timeIntervalSince(startedAt))
        switch result.status {
        case .completed:
            log("Completed (\(elapsed)s)", kind: .success)
        case .failed:
            let reason = result.logMessages.last ?? "Simulation failed."
            simulationError = reason
            log("Failed (\(elapsed)s): \(reason)", kind: .error)
        case .cancelled:
            log("Cancelled (\(elapsed)s)", kind: .warning)
        case .pending, .running:
            let reason = "Simulation returned without a terminal result."
            simulationError = reason
            log("Incomplete (\(elapsed)s): \(reason)", kind: .warning)
        }
        focusSimulationOutcome(result)
    }

    // MARK: - Matrix Runs

    /// The single entry point behind Run (⌘R): decides between a single
    /// analysis and an analysis × corner matrix based on the current
    /// editor mode, the analyses the source declares, and the selected
    /// corners.
    public func runActiveSimulation(
        schematicDocument: SchematicDocument,
        library: CellLibrary = CellLibrary(),
        service: DesignFlowService,
        recorder: any SimulationRunRecording
    ) async {
        let startedAt = Date()
        let initialSource = schematicMode == .netlist ? spiceSource : nil
        let initialFileName = schematicMode == .netlist ? spiceFileName : "schematic.cir"
        let recordingContext: SimulationRunContext
        do {
            recordingContext = try recorder.begin(
                projectRoot: try requiredProjectRootForSimulation(),
                intent: "Run the active simulation workflow.",
                source: initialSource,
                fileName: initialFileName,
                startedAt: startedAt
            )
        } catch {
            simulationError = error.localizedDescription
            log(error.localizedDescription, kind: .error)
            return
        }

        switch schematicMode {
        case .visual:
            let corners = selectedCorners
            guard !corners.isEmpty else {
                await runSchematicSimulationRecorded(
                    document: schematicDocument,
                    library: library,
                    analysisCommand: selectedAnalysis,
                    service: service,
                    recorder: recorder,
                    recordingContext: recordingContext,
                    startedAt: startedAt
                )
                return
            }
            // Generate once with the base configuration: each matrix cell's
            // corner configuration wins over any netlist .temp card in both
            // simulation paths, so the shared netlist stays corner-neutral.
            let testbench = Testbench(name: "Quick", analysisCommands: [selectedAnalysis])
            let netlist: String
            do {
                netlist = try service.generateNetlist(DesignFlowNetlistRequest(
                    schematic: schematicDocument,
                    library: library,
                    testbench: testbench,
                    processConfiguration: processConfiguration.isEmpty ? nil : processConfiguration
                ))
            } catch {
                recordSimulationFailure(
                    recorder: recorder,
                    context: recordingContext,
                    reason: error.localizedDescription
                )
                simulationError = error.localizedDescription
                log(error.localizedDescription, kind: .error)
                return
            }
            await runMatrixRecorded(
                source: netlist,
                fileName: "schematic.cir",
                analyses: [selectedAnalysis],
                service: service,
                recorder: recorder,
                recordingContext: recordingContext,
                startedAt: startedAt
            )

        case .netlist:
            guard !spiceSource.isEmpty else {
                simulationError = "No SPICE source loaded"
                recordSimulationFailure(
                    recorder: recorder,
                    context: recordingContext,
                    reason: "No SPICE source loaded"
                )
                return
            }
            let detected: [AnalysisCommand]
            do {
                detected = try await service.detectAnalyses(
                    source: spiceSource,
                    fileName: spiceFileName,
                    processConfiguration: processConfiguration.isEmpty ? nil : processConfiguration
                )
            } catch {
                recordSimulationFailure(
                    recorder: recorder,
                    context: recordingContext,
                    reason: error.localizedDescription
                )
                simulationError = error.localizedDescription
                log(error.localizedDescription, kind: .error)
                return
            }
            let analyses = detected.isEmpty ? [.op] : detected
            if selectedCorners.isEmpty && analyses.count <= 1 {
                await runSimulationRecorded(
                    service: service,
                    analysis: analyses.first ?? selectedAnalysis,
                    recorder: recorder,
                    recordingContext: recordingContext,
                    startedAt: startedAt
                )
                return
            }
            await runMatrixRecorded(
                source: spiceSource,
                fileName: spiceFileName,
                analyses: analyses,
                service: service,
                recorder: recorder,
                recordingContext: recordingContext,
                startedAt: startedAt
            )
        }
    }

    /// Runs every analysis on every selected corner and retains the batch
    /// in `runHistory`.
    public func runMatrix(
        source: String,
        fileName: String?,
        analyses: [AnalysisCommand],
        service: DesignFlowService,
        recorder: (any SimulationRunRecording)? = nil
    ) async {
        await runMatrixRecorded(
            source: source,
            fileName: fileName,
            analyses: analyses,
            service: service,
            recorder: recorder,
            recordingContext: nil,
            startedAt: nil
        )
    }

    private func runMatrixRecorded(
        source: String,
        fileName: String?,
        analyses: [AnalysisCommand],
        service: DesignFlowService,
        recorder: (any SimulationRunRecording)?,
        recordingContext: SimulationRunContext?,
        startedAt: Date?
    ) async {
        let start = startedAt ?? Date()
        let activeRecordingContext: SimulationRunContext?
        do {
            if let recordingContext {
                activeRecordingContext = recordingContext
            } else {
                activeRecordingContext = try beginSimulationRecording(
                    recorder: recorder,
                    intent: "Run an analysis and corner matrix.",
                    source: source,
                    fileName: fileName,
                    startedAt: start
                )
            }
        } catch {
            simulationError = error.localizedDescription
            log(error.localizedDescription, kind: .error)
            return
        }

        isSimulating = true
        simulationError = nil
        streamingWaveform = nil
        clearConsole()
        showDebugArea = true
        debugAreaTab = .console

        let corners = selectedCorners
        let runCount = analyses.count * max(corners.count, 1)
        if corners.isEmpty {
            log("Running \(analyses.count) analyses (\(runCount) runs)...")
        } else {
            log("Running \(analyses.count) analyses × \(corners.count) corners (\(runCount) runs)...")
        }

        let request = AnalysisMatrixRequest(
            source: source,
            fileName: fileName,
            baseConfiguration: processConfiguration.isEmpty ? nil : processConfiguration,
            corners: corners,
            analyses: analyses
        )

        // Bridge per-record callbacks from the runner to MainActor logging.
        let (stream, continuation) = AsyncStream<AnalysisRunRecord>.makeStream()
        let updateTask = Task {
            for await record in stream {
                self.appendRecordLog(record)
            }
        }

        let records = await service.runAnalysisMatrix(request) { record in
            continuation.yield(record)
        }
        continuation.finish()
        _ = await updateTask.value

        do {
            if let recorder, let activeRecordingContext {
                try await recorder.complete(
                    context: activeRecordingContext,
                    source: source,
                    records: records
                )
            }
        } catch {
            recordSimulationFailure(
                recorder: recorder,
                context: activeRecordingContext,
                reason: error.localizedDescription
            )
            log(error.localizedDescription, kind: .error)
            simulationError = error.localizedDescription
            streamingWaveform = nil
            simulationStatus = nil
            isSimulating = false
            return
        }
        let batch = AnalysisRunBatch(
            runID: activeRecordingContext?.runID,
            startedAt: start,
            records: records
        )
        runHistory.append(batch)

        let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))
        let completed = records.filter { $0.status == .completed }
        let failed = records.filter { $0.status == .failed }
        let cancelled = records.filter { $0.status == .cancelled }
        if !cancelled.isEmpty {
            log("Cancelled after \(completed.count)/\(records.count) runs (\(elapsed)s)", kind: .warning)
        } else if !failed.isEmpty {
            log("Completed with \(failed.count) failures out of \(records.count) runs (\(elapsed)s)", kind: .warning)
            simulationError = failed.first?.failureReason
        } else {
            log("Completed \(records.count) runs (\(elapsed)s)", kind: .success)
        }

        simulationResult = records.last(where: { $0.status == .completed })?.result
        focusBatchOutcome(batch)

        simulationStatus = nil
        isSimulating = false
    }

    private func beginSimulationRecording(
        recorder: (any SimulationRunRecording)?,
        intent: String,
        source: String?,
        fileName: String?,
        startedAt: Date
    ) throws -> SimulationRunContext? {
        guard let recorder else {
            return nil
        }
        return try recorder.begin(
            projectRoot: try requiredProjectRootForSimulation(),
            intent: intent,
            source: source,
            fileName: fileName,
            startedAt: startedAt
        )
    }

    private func requiredProjectRootForSimulation() throws -> URL {
        guard let projectRootURL else {
            throw SimulationRunRecordingError.projectRequired
        }
        return projectRootURL
    }

    private func recordSimulationFailure(
        recorder: (any SimulationRunRecording)?,
        context: SimulationRunContext?,
        reason: String
    ) {
        guard let recorder, let context else {
            return
        }
        do {
            try recorder.fail(context: context, reason: reason)
        } catch {
            log(
                "Failed to persist the simulation failure: \(error.localizedDescription)",
                kind: .error
            )
        }
    }

    private func appendRecordLog(_ record: AnalysisRunRecord) {
        let corner = record.cornerName.map { " [\($0)]" } ?? ""
        let temperature = record.temperature.map { String(format: " %.4g°C", $0) } ?? ""
        let label = "\(record.analysis.mnemonic)\(corner)\(temperature)"
        switch record.status {
        case .completed:
            log("✓ \(label)", kind: .success)
        case .failed:
            log("✗ \(label): \(record.failureReason ?? "Unknown failure")", kind: .error)
        case .cancelled:
            log("⊘ \(label): \(record.failureReason ?? "Cancelled")", kind: .warning)
        case .pending, .running:
            log("\(label): \(record.status.rawValue)")
        }
    }

    /// Picks what the waveform pane should show after a batch: a corner
    /// overlay when an analysis completed on 2+ corners, otherwise the first
    /// plottable single result. Matrix results focus as `.history`/`.overlay`
    /// so the live-run terminal filter never empties their traces.
    private func focusBatchOutcome(_ batch: AnalysisRunBatch) {
        var analysisOrder: [AnalysisCommand] = []
        var recordsByAnalysis: [AnalysisCommand: [AnalysisRunRecord]] = [:]
        for record in batch.records where record.status == .completed {
            guard let waveform = record.result?.waveform, waveform.pointCount > 0 else { continue }
            if recordsByAnalysis[record.analysis] == nil {
                analysisOrder.append(record.analysis)
            }
            recordsByAnalysis[record.analysis, default: []].append(record)
        }

        for analysis in analysisOrder {
            let records = recordsByAnalysis[analysis] ?? []
            let overlayable = records.filter { $0.cornerName != nil }
            if overlayable.count >= 2 {
                let sources = overlayable.compactMap { record -> CornerOverlayBuilder.Source? in
                    guard let cornerName = record.cornerName,
                          let waveform = record.result?.waveform else { return nil }
                    return CornerOverlayBuilder.Source(label: cornerName, waveform: waveform)
                }
                do {
                    let overlay = try CornerOverlayBuilder().build(sources: sources)
                    focusWaveform(overlay, source: .overlay)
                    return
                } catch {
                    log("Corner overlay failed: \(error.localizedDescription)", kind: .warning)
                }
            }
            if let waveform = records.first?.result?.waveform, waveform.pointCount > 1 {
                focusWaveform(waveform, source: .history)
                return
            }
        }
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
