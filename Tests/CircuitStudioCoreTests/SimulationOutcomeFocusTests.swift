import Foundation
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore

/// After a run finishes, the UI must land on the outcome: the waveform pane
/// in the main editor area for a plottable result, the debug-area console
/// (where the error was logged) for a failure.
@Suite("Simulation Outcome Focus Tests")
@MainActor
struct SimulationOutcomeFocusTests {

    @Test(.timeLimit(.minutes(2)))
    func completedTransientRunShowsWaveformPane() async throws {
        let appState = AppState()
        appState.spiceSource = try NewProjectTemplate.cmosInverter().netlist
        appState.spiceFileName = "top.cir"

        let service = DesignFlowService(
            netlistGenerator: NetlistGenerator(catalog: .standard())
        )
        await appState.runSimulation(service: service)

        #expect(appState.simulationError == nil)
        #expect((appState.simulationResult?.waveform?.pointCount ?? 0) > 1)
        #expect(appState.showWaveformPane)
        #expect(appState.editorDestination == .waveform)
        // The debug area was auto-opened at run start; the outcome pane replaces it.
        #expect(!appState.showDebugArea)
    }

    @Test(.timeLimit(.minutes(2)))
    func failedRunKeepsConsoleFocused() async throws {
        let appState = AppState()
        appState.spiceSource = """
        * Unparsable element should fail the run
        R1 in out
        .tran 1n 10n
        .end
        """
        appState.spiceFileName = "broken.cir"

        let service = DesignFlowService(
            netlistGenerator: NetlistGenerator(catalog: .standard())
        )
        await appState.runSimulation(service: service)

        #expect(appState.simulationError != nil)
        #expect(appState.showDebugArea)
        #expect(appState.debugAreaTab == .console)
        #expect(!appState.showWaveformPane)
    }

    @Test
    func waveformPaneRoundTripsThroughWorkspaceConfig() {
        let appState = AppState()
        appState.showWaveformPane = true
        appState.showDebugArea = true
        appState.debugAreaTab = .console

        let config = appState.workspaceConfig()
        #expect(config.panels.simulationResults)
        #expect(config.panels.console)

        let restored = AppState()
        restored.apply(config)
        #expect(restored.showWaveformPane)
        #expect(restored.showDebugArea)
        #expect(restored.debugAreaTab == .console)
        #expect(restored.editorDestination == .schematic(.netlist))
    }
}
