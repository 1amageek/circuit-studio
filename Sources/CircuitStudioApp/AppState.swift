import SwiftUI
import CircuitStudioCore
import CoreSpiceWaveform

/// Editor mode for the main content area.
public enum EditorMode: Hashable, Sendable {
    case netlist
    case schematic
    case waveform
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
    public var simulationResult: SimulationResult?
    public var simulationError: String?

    public init() {}

    /// Load a SPICE file from disk.
    public func loadSPICEFile(url: URL) throws {
        let source = try String(contentsOf: url, encoding: .utf8)
        spiceSource = source
        spiceFileName = url.lastPathComponent
        selectedFileURL = url
        simulationResult = nil
        simulationError = nil
    }

    /// Run simulation using the loaded SPICE source.
    public func runSimulation(service: SimulationService) async {
        guard !spiceSource.isEmpty else {
            simulationError = "No SPICE source loaded"
            return
        }

        isSimulating = true
        simulationError = nil

        do {
            let result = try await service.runSPICE(
                source: spiceSource,
                fileName: spiceFileName
            )
            simulationResult = result
        } catch {
            simulationError = error.localizedDescription
        }

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

        do {
            let result = try await service.runAnalysis(
                source: spiceSource,
                fileName: spiceFileName,
                command: command
            )
            simulationResult = result
        } catch {
            simulationError = error.localizedDescription
        }

        isSimulating = false
    }
}
