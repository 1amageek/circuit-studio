import Foundation
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore

/// After a run finishes, the debug area must land on the pane that holds
/// the outcome: the waveform tab for a plottable result, the console (where
/// the error was logged) for a failure.
@Suite("Simulation Debug Area Focus Tests")
@MainActor
struct SimulationDebugAreaFocusTests {

    @Test(.timeLimit(.minutes(2)))
    func completedTransientRunFocusesWaveformTab() async throws {
        let appState = AppState()
        appState.spiceSource = NewProjectTemplate.cmosInverter().netlist
        appState.spiceFileName = "top.cir"

        let service = DesignFlowService(
            netlistGenerator: NetlistGenerator(catalog: .standard())
        )
        await appState.runSimulation(service: service)

        #expect(appState.simulationError == nil)
        #expect((appState.simulationResult?.waveform?.pointCount ?? 0) > 1)
        #expect(appState.showDebugArea)
        #expect(appState.debugAreaTab == .waveform)
    }

    @Test(.timeLimit(.minutes(2)))
    func failedRunKeepsConsoleTabFocused() async throws {
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
    }
}
