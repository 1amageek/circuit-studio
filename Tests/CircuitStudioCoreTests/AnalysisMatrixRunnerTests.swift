import CoreSpiceWaveform
import Foundation
import Synchronization
import Testing

@testable import CircuitStudioCore

@Suite("Analysis Matrix Runner Tests")
struct AnalysisMatrixRunnerTests {

    @Test("Cells expand analysis-major and apply each corner's conditions")
    func cellsExpandAnalysisMajorAndApplyCornerConditions() async throws {
        let service = ScriptedSimulationService()
        let runner = AnalysisMatrixRunner(simulationService: service)
        let fast = Corner(name: "fast", temperature: -40.0)
        let slow = Corner(name: "slow", temperature: 125.0)
        let request = AnalysisMatrixRequest(
            source: "* netlist",
            fileName: "test.cir",
            corners: [fast, slow],
            analyses: [.op, .tran(TranSpec(stopTime: 1e-6))]
        )

        let streamed: Mutex<[UUID]> = Mutex([])
        let records = await runner.run(request) { record in
            streamed.withLock { $0.append(record.id) }
        }

        try #require(records.count == 4)
        #expect(records.map(\.cornerName) == ["fast", "slow", "fast", "slow"])
        #expect(records.map { $0.analysis.mnemonic } == ["OP", "OP", "TRAN", "TRAN"])
        #expect(records.map(\.temperature) == [-40.0, 125.0, -40.0, 125.0])
        #expect(records.allSatisfy { $0.status == .completed })
        #expect(streamed.withLock { $0 } == records.map(\.id))

        let calls = service.calls
        try #require(calls.count == 4)
        // A generic corner (no technology) must arrive as a temperature
        // override on the configuration handed to the service.
        #expect(calls[0].configuration?.temperatureOverride == -40.0)
        #expect(calls[1].configuration?.temperatureOverride == 125.0)
    }

    @Test("A failed cell records its reason and the matrix continues")
    func failedCellRecordsReasonAndMatrixContinues() async throws {
        let service = ScriptedSimulationService(failingIndices: [0])
        let runner = AnalysisMatrixRunner(simulationService: service)
        let request = AnalysisMatrixRequest(
            source: "* netlist",
            fileName: "test.cir",
            corners: [Corner(name: "typical", temperature: 27.0)],
            analyses: [.op, .tran(TranSpec(stopTime: 1e-6))]
        )

        let records = await runner.run(request)

        try #require(records.count == 2)
        #expect(records[0].status == .failed)
        #expect(records[0].failureReason?.contains("Scripted failure") == true)
        #expect(records[1].status == .completed)
        #expect(service.calls.count == 2)
    }

    @Test("Cancellation stops the matrix and accounts for every remaining cell")
    func cancellationStopsMatrixAndAccountsForRemainingCells() async throws {
        let service = ScriptedSimulationService(cancellingIndices: [1])
        let runner = AnalysisMatrixRunner(simulationService: service)
        let fast = Corner(name: "fast", temperature: -40.0)
        let slow = Corner(name: "slow", temperature: 125.0)
        let request = AnalysisMatrixRequest(
            source: "* netlist",
            fileName: "test.cir",
            corners: [fast, slow],
            analyses: [.op, .tran(TranSpec(stopTime: 1e-6))]
        )

        let records = await runner.run(request)

        try #require(records.count == 4)
        #expect(records[0].status == .completed)
        #expect(records[1].status == .cancelled)
        #expect(records[2].status == .cancelled)
        #expect(records[2].failureReason == "Cancelled before start")
        #expect(records[3].status == .cancelled)
        #expect(records[3].failureReason == "Cancelled before start")
        // No cell after the cancellation point may reach the simulator.
        #expect(service.calls.count == 2)
    }

    @Test("Empty corner list runs each analysis once on the base configuration")
    func emptyCornerListRunsEachAnalysisOnceOnBase() async throws {
        let service = ScriptedSimulationService()
        let runner = AnalysisMatrixRunner(simulationService: service)
        let request = AnalysisMatrixRequest(
            source: "* netlist",
            fileName: "test.cir",
            analyses: [.op]
        )

        let records = await runner.run(request)

        try #require(records.count == 1)
        #expect(records[0].cornerName == nil)
        #expect(records[0].temperature == nil)
        #expect(records[0].status == .completed)
        try #require(service.calls.count == 1)
        #expect(service.calls[0].configuration == nil)
    }
}

// MARK: - Test Double

private enum ScriptedAction {
    case succeed
    case fail
    case cancel
}

/// Records every `runAnalysis` call and fails or cancels at scripted
/// call indices so matrix control flow can be exercised deterministically.
private final class ScriptedSimulationService: SimulationServiceProtocol, Sendable {
    struct Call: Sendable {
        let command: AnalysisCommand
        let configuration: ProcessConfiguration?
    }

    private struct State: Sendable {
        var calls: [Call] = []
        var failingIndices: Set<Int>
        var cancellingIndices: Set<Int>
    }

    private let state: Mutex<State>

    init(failingIndices: Set<Int> = [], cancellingIndices: Set<Int> = []) {
        self.state = Mutex(State(
            failingIndices: failingIndices,
            cancellingIndices: cancellingIndices
        ))
    }

    var calls: [Call] {
        state.withLock { $0.calls }
    }

    func runSPICE(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration?,
        onWaveformUpdate: (@Sendable (WaveformData) -> Void)?
    ) async throws -> SimulationResult {
        throw StudioError.simulationFailure("runSPICE is not part of matrix execution")
    }

    func runAnalysis(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration?,
        command: AnalysisCommand
    ) async throws -> SimulationResult {
        let action: ScriptedAction = state.withLock { state in
            let index = state.calls.count
            state.calls.append(Call(command: command, configuration: processConfiguration))
            if state.cancellingIndices.contains(index) { return .cancel }
            if state.failingIndices.contains(index) { return .fail }
            return .succeed
        }
        switch action {
        case .succeed:
            return SimulationResult(experimentID: UUID(), status: .completed)
        case .fail:
            throw StudioError.simulationFailure("Scripted failure")
        case .cancel:
            throw StudioError.cancelled
        }
    }

    func cancel(jobID: UUID) {}

    func events(jobID: UUID) -> AsyncStream<SimulationEvent> {
        AsyncStream { $0.finish() }
    }
}
