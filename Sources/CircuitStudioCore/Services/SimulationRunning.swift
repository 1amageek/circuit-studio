import CoreSpice
import CoreSpiceWaveform
import Foundation

/// Runs cancellable simulations and exposes their structured event stream.
public protocol SimulationRunning: Sendable {
    func runSPICE(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration?,
        onWaveformUpdate: (@Sendable (WaveformData) -> Void)?
    ) async throws -> SimulationResult

    func runAnalysis(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration?,
        command: AnalysisCommand
    ) async throws -> SimulationResult

    func cancel(jobID: UUID)
    func events(jobID: UUID) -> AsyncStream<SimulationEvent>
    func shutdown()
}
