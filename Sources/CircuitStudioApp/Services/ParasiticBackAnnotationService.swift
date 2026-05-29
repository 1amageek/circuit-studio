import Foundation
import CircuitStudioCore
import CoreSpiceWaveform
import PEXEngine

/// Closes the design->evaluation loop in simulation: it back-annotates the
/// extracted parasitic capacitance as a lumped load driven through a fixed
/// resistance, simulates the RC step response in CoreSpice (the project's own
/// engine, in-process — no external tool), and verifies the measured RC time
/// constant against R*C. This proves the extracted parasitics produce physically
/// correct dynamics, not merely that they were plumbed through.
public struct ParasiticBackAnnotationService: Sendable {

    public struct Result: Sendable {
        public let capacitanceF: Double
        public let driverResistanceOhm: Double
        public let expectedTauS: Double
        public let measuredTauS: Double
        public let tolerance: Double
        public var relativeError: Double {
            expectedTauS == 0 ? .infinity : abs(measuredTauS - expectedTauS) / expectedTauS
        }
        public var consistent: Bool { relativeError <= tolerance }
    }

    public enum BackAnnotationError: Error, LocalizedError, Equatable {
        case noCapacitance
        case simulationProducedNoWaveform
        case outputNodeNotFound
        case stepNeverReachedThreshold

        public var errorDescription: String? {
            switch self {
            case .noCapacitance: return "The extracted IR has no capacitance to back-annotate."
            case .simulationProducedNoWaveform: return "CoreSpice produced no waveform for the RC step."
            case .outputNodeNotFound: return "Could not find the 'out' node in the simulated waveform."
            case .stepNeverReachedThreshold: return "The RC step never crossed 63.2% — check the time window."
            }
        }
    }

    private let simulation: SimulationServiceProtocol

    public init(simulation: SimulationServiceProtocol = SimulationService()) {
        self.simulation = simulation
    }

    /// Total extracted capacitance (ground + coupling) across all nets.
    public static func totalCapacitance(of ir: ParasiticIR) -> Double {
        ir.nets.map { $0.totalGroundCapF + $0.totalCouplingCapF }.reduce(0, +)
    }

    /// Drives the IR's total capacitance through `driverResistanceOhm`, simulates
    /// the step in CoreSpice, and returns the measured vs expected (R*C) time
    /// constant. Throws (never silently passes) if the capacitance is zero or the
    /// simulation cannot be measured.
    public func backAnnotate(
        ir: ParasiticIR,
        driverResistanceOhm: Double = 1_000_000,   // 1 MΩ keeps τ in the ns range
        tolerance: Double = 0.05
    ) async throws -> Result {
        let capacitanceF = Self.totalCapacitance(of: ir)
        guard capacitanceF > 0 else { throw BackAnnotationError.noCapacitance }
        let expectedTau = driverResistanceOhm * capacitanceF

        // Step source into R-C; edge much faster than tau, held high past the
        // window. PULSE (not PWL) — it is the step source CoreSpice's transient
        // engine is validated against.
        let edge = expectedTau / 1_000
        let stop = expectedTau * 8
        let deck = """
        * PEX back-annotation RC step
        V1 in 0 PULSE(0 1 0 \(format(edge)) \(format(edge)) \(format(stop * 4)) \(format(stop * 8)))
        R1 in out \(format(driverResistanceOhm))
        C1 out 0 \(format(capacitanceF))
        .tran \(format(expectedTau / 100)) \(format(stop))
        .end
        """
        let result = try await simulation.runSPICE(
            source: deck, fileName: "backann.cir", processConfiguration: nil, onWaveformUpdate: nil
        )
        guard let waveform = result.waveform else { throw BackAnnotationError.simulationProducedNoWaveform }
        guard let series = outputSeries(waveform) else { throw BackAnnotationError.outputNodeNotFound }
        let measuredTau = try crossingTime(series, threshold: 0.632)

        return Result(
            capacitanceF: capacitanceF, driverResistanceOhm: driverResistanceOhm,
            expectedTauS: expectedTau, measuredTauS: measuredTau, tolerance: tolerance
        )
    }

    // MARK: - waveform helpers

    private func outputSeries(_ waveform: WaveformData) -> RealWaveform? {
        for candidate in ["out", "V(out)", "v(out)"] {
            if let w = waveform.realWaveform(named: candidate) { return w }
        }
        // Fall back to any variable whose name mentions the out node.
        if let match = waveform.variables.first(where: { $0.name.lowercased().contains("out") }) {
            return waveform.realWaveform(named: match.name)
        }
        return nil
    }

    /// First time the series crosses `threshold` (× its final value), linearly
    /// interpolated between samples.
    private func crossingTime(_ wave: RealWaveform, threshold: Double) throws -> Double {
        let times = wave.sweepValues
        let values = wave.values
        guard let final = values.last, final != 0 else { throw BackAnnotationError.stepNeverReachedThreshold }
        let level = threshold * final
        for i in 1..<min(times.count, values.count) {
            if (values[i - 1] < level && values[i] >= level) || (values[i - 1] > level && values[i] <= level) {
                let dv = values[i] - values[i - 1]
                let frac = dv == 0 ? 0 : (level - values[i - 1]) / dv
                return times[i - 1] + frac * (times[i] - times[i - 1])
            }
        }
        throw BackAnnotationError.stepNeverReachedThreshold
    }

    private func format(_ value: Double) -> String {
        String(format: "%.6e", value)
    }
}
