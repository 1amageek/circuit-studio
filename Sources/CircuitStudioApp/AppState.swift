import SwiftUI
import AppKit
import CircuitStudioCore
import CoreSpiceWaveform

/// Editor mode for the main content area.
public enum EditorMode: Hashable, Sendable {
    case netlist
    case schematic
    case waveform
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
    public var activeEditor: EditorMode = .netlist
    public var showInspector: Bool = false

    // Project
    public var projectRootURL: URL?
    public var projectRoot: FileNode?
    public var selectedFileURL: URL?

    // SPICE source
    public var spiceSource: String = ""
    public var spiceFileName: String?

    // Simulation
    public var isSimulating: Bool = false
    public var simulationStatus: String?
    public var simulationResult: SimulationResult?
    public var simulationError: String?
    public var selectedAnalysis: AnalysisCommand = .op

    // Console
    public var consoleEntries: [ConsoleEntry] = []
    public var showConsole: Bool = false

    // Live parsing
    public var netlistInfo: NetlistInfo?
    private var parseTask: Task<Void, Never>?

    public init() {}

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
    public func cancelSimulation(service: SimulationService) {
        guard let jobID = service.activeJobID else { return }
        service.cancel(jobID: jobID)
        log("Simulation cancelled", kind: .warning)
    }

    /// Load a SPICE file from disk.
    public func loadSPICEFile(url: URL) throws {
        let source = try String(contentsOf: url, encoding: .utf8)
        spiceSource = source
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
        parseTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let info = await service.parse(source: source, fileName: fileName)
            guard !Task.isCancelled else { return }
            self.netlistInfo = info
        }
    }

    /// Save the current SPICE source to the already-selected file, or prompt with Save As.
    public func saveSPICEFile() throws {
        if let url = selectedFileURL {
            try spiceSource.write(to: url, atomically: true, encoding: .utf8)
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
            selectedFileURL = url
            spiceFileName = url.lastPathComponent
            log("Saved \(url.lastPathComponent)", kind: .success)
        } catch {
            log("Failed to save: \(error.localizedDescription)", kind: .error)
        }
    }

    /// Run simulation using the loaded SPICE source.
    public func runSimulation(service: SimulationService) async {
        guard !spiceSource.isEmpty else {
            simulationError = "No SPICE source loaded"
            return
        }

        isSimulating = true
        simulationError = nil
        clearConsole()
        showConsole = true

        let start = Date()
        log("Running simulation...")

        do {
            let result = try await service.runSPICE(
                source: spiceSource,
                fileName: spiceFileName
            )
            simulationResult = result
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))
            log("Completed (\(elapsed)s)", kind: .success)
        } catch {
            log(error.localizedDescription, kind: .error)
            simulationError = error.localizedDescription
        }

        simulationStatus = nil
        isSimulating = false
    }

    /// Run simulation from a schematic document by generating a SPICE netlist.
    public func runSchematicSimulation(
        document: SchematicDocument,
        analysisCommand: AnalysisCommand,
        generator: NetlistGenerator,
        service: SimulationService
    ) async {
        isSimulating = true
        simulationError = nil
        clearConsole()
        showConsole = true

        let start = Date()

        log("Generating netlist...")
        let testbench = Testbench(
            name: "Quick",
            analysisCommands: [analysisCommand]
        )
        let source = generator.generate(from: document, testbench: testbench)
        log(source, kind: .output)

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

        do {
            let result = try await service.runSPICE(source: source, fileName: "schematic.cir")
            simulationResult = result
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))
            log("Completed (\(elapsed)s)", kind: .success)
        } catch {
            log(error.localizedDescription, kind: .error)
            simulationError = error.localizedDescription
        }

        simulationStatus = nil
        isSimulating = false
    }

    /// Run a specific analysis command.
    public func runAnalysis(command: AnalysisCommand, service: SimulationService) async {
        guard !spiceSource.isEmpty else {
            simulationError = "No SPICE source loaded"
            return
        }

        isSimulating = true
        simulationError = nil
        clearConsole()
        showConsole = true

        let start = Date()
        log("Running analysis...")

        do {
            let result = try await service.runAnalysis(
                source: spiceSource,
                fileName: spiceFileName,
                command: command
            )
            simulationResult = result
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))
            log("Completed (\(elapsed)s)", kind: .success)
        } catch {
            log(error.localizedDescription, kind: .error)
            simulationError = error.localizedDescription
        }

        simulationStatus = nil
        isSimulating = false
    }
}
