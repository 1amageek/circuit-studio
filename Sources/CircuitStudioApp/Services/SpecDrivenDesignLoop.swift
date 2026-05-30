import Foundation
import CircuitStudioCore
import CoreSpiceWaveform

/// Closes the agent design loop (roadmap "Mountain A") on a measurable spec: each
/// iteration simulates the current design in CoreSpice, measures a metric, and — when
/// the design misses its `PerformanceSpec` — edits a tunable parameter toward the
/// target (the agent decision) via the structured `DesignFlowDesignEditService`, then
/// re-simulates. Unlike the fixed-candidate signoff loop, the next edit is COMPUTED
/// from the measured failure, so the loop is genuinely failure-driven.
///
/// The Measure stage it relies on is the one validated against ngspice
/// (see `PostLayoutOracleService` / the trust gate), so the loop optimizes against
/// trustworthy physics rather than an unchecked model.
public struct SpecDrivenDesignLoop: Sendable {

    /// The parameter the controller adjusts, and how it pushes the metric.
    public struct Tunable: Sendable, Hashable {
        public enum Effect: String, Sendable, Hashable, Codable {
            /// A larger parameter value reduces the metric (e.g. wider FET → less delay).
            case largerReducesMetric
            /// A larger parameter value raises the metric.
            case largerRaisesMetric
        }
        public let componentNames: [String]
        public let parameter: String
        public let effect: Effect
        public let stepFactor: Double
        public let minValue: Double
        public let maxValue: Double

        public init(
            componentNames: [String],
            parameter: String,
            effect: Effect,
            stepFactor: Double,
            minValue: Double,
            maxValue: Double
        ) {
            self.componentNames = componentNames
            self.parameter = parameter
            self.effect = effect
            self.stepFactor = stepFactor
            self.minValue = minValue
            self.maxValue = maxValue
        }
    }

    public struct Iteration: Sendable, Hashable {
        public let index: Int
        public let parameterValue: Double
        public let measuredMetric: Double
        public let shortfall: Double
        public let met: Bool
    }

    public struct Outcome: Sendable {
        public let converged: Bool
        public let iterations: [Iteration]
        public let finalSpec: DesignFlowDesignSpec
    }

    public enum LoopError: Error, LocalizedError, Equatable {
        case nonPositiveBudget
        case emptyTunable
        case simulationProducedNoWaveform(iteration: Int)
        case parameterNotFound(component: String, parameter: String)
        case probeNotFound(node: String)
        case edgeNotFound(node: String)

        public var errorDescription: String? {
            switch self {
            case .nonPositiveBudget: return "The design loop requires maxIterations >= 1."
            case .emptyTunable: return "The tunable must name at least one component."
            case .simulationProducedNoWaveform(let i): return "Iteration \(i) produced no waveform."
            case .parameterNotFound(let c, let p): return "Component \(c) has no parameter '\(p)'."
            case .probeNotFound(let n): return "Node '\(n)' was not found in the waveform."
            case .edgeNotFound(let n): return "Node '\(n)' never crossed the threshold."
            }
        }
    }

    private let simulation: SimulationServiceProtocol
    private let editor: DesignFlowDesignEditService
    private let netlistGenerator: NetlistGenerator

    public init(
        simulation: SimulationServiceProtocol = SimulationService(),
        editor: DesignFlowDesignEditService = DesignFlowDesignEditService(),
        netlistGenerator: NetlistGenerator = NetlistGenerator()
    ) {
        self.simulation = simulation
        self.editor = editor
        self.netlistGenerator = netlistGenerator
    }

    /// Drives `initial` toward `spec`: simulate → measure → (if failing) edit the
    /// tunable toward the target → repeat, until the spec is met or the budget /
    /// parameter bounds are exhausted. `measure` extracts the metric from the
    /// simulated waveform. Throws (never silently passes) on a missing waveform/probe.
    public func run(
        initial: DesignFlowDesignSpec,
        tunable: Tunable,
        spec: PerformanceSpec,
        maxIterations: Int,
        catalog: DeviceCatalog = .standard(),
        measure: @Sendable (WaveformData) throws -> Double
    ) async throws -> Outcome {
        guard maxIterations >= 1 else { throw LoopError.nonPositiveBudget }
        guard !tunable.componentNames.isEmpty else { throw LoopError.emptyTunable }

        var design = initial
        var parameterValue = try currentParameter(of: design, tunable: tunable)
        var iterations: [Iteration] = []

        for index in 0..<maxIterations {
            let built = try design.build(catalog: catalog)
            let netlist = netlistGenerator.generate(
                from: built.schematic, title: built.title, testbench: built.testbench
            )
            let result = try await simulation.runSPICE(
                source: netlist, fileName: "spec-loop-\(index).cir",
                processConfiguration: nil, onWaveformUpdate: nil
            )
            guard let waveform = result.waveform else {
                throw LoopError.simulationProducedNoWaveform(iteration: index)
            }
            let metric = try measure(waveform)
            let met = spec.isMet(by: metric)
            iterations.append(Iteration(
                index: index, parameterValue: parameterValue,
                measuredMetric: metric, shortfall: spec.shortfall(of: metric), met: met
            ))
            if met {
                return Outcome(converged: true, iterations: iterations, finalSpec: design)
            }

            // Agent decision: move the tunable toward the target. Stop if a bound is
            // hit (the step cannot change the value any further).
            let next = nextParameter(current: parameterValue, spec: spec, tunable: tunable)
            guard next != parameterValue else { break }
            parameterValue = next
            design = try apply(parameterValue: next, to: design, tunable: tunable, catalog: catalog)
        }
        return Outcome(converged: false, iterations: iterations, finalSpec: design)
    }

    // MARK: - controller

    private func currentParameter(of spec: DesignFlowDesignSpec, tunable: Tunable) throws -> Double {
        let name = tunable.componentNames[0]
        guard let component = spec.components.first(where: { $0.name == name }),
              let value = component.parameters[tunable.parameter] else {
            throw LoopError.parameterNotFound(component: name, parameter: tunable.parameter)
        }
        return value
    }

    private func nextParameter(current: Double, spec performance: PerformanceSpec, tunable: Tunable) -> Double {
        // Only called while failing, so always move toward the target.
        let needToReduceMetric = performance.comparison == .atMost
        let increase: Bool
        switch tunable.effect {
        case .largerReducesMetric: increase = needToReduceMetric
        case .largerRaisesMetric: increase = !needToReduceMetric
        }
        let raw = increase ? current * tunable.stepFactor : current / tunable.stepFactor
        return min(tunable.maxValue, max(tunable.minValue, raw))
    }

    private func apply(
        parameterValue: Double,
        to spec: DesignFlowDesignSpec,
        tunable: Tunable,
        catalog: DeviceCatalog
    ) throws -> DesignFlowDesignSpec {
        let edits = tunable.componentNames.map { name in
            DesignFlowDesignEdit(
                kind: .setComponentParameters,
                componentName: name,
                parameters: [tunable.parameter: parameterValue]
            )
        }
        let result = try editor.apply(
            script: DesignFlowDesignEditScript(edits: edits), to: spec, catalog: catalog
        )
        return result.designSpec
    }

    // MARK: - metric: propagation delay

    /// Input→output propagation delay: the time between `inputNode` and `outputNode`
    /// first crossing `thresholdV`. Use as the `measure` closure for a delay spec.
    public static func propagationDelay(
        in waveform: WaveformData,
        from inputNode: String,
        to outputNode: String,
        thresholdV: Double
    ) throws -> Double {
        guard let inWave = resolveProbe(inputNode, in: waveform) else {
            throw LoopError.probeNotFound(node: inputNode)
        }
        guard let outWave = resolveProbe(outputNode, in: waveform) else {
            throw LoopError.probeNotFound(node: outputNode)
        }
        guard let tIn = firstCrossing(inWave, thresholdV: thresholdV) else {
            throw LoopError.edgeNotFound(node: inputNode)
        }
        guard let tOut = firstCrossing(outWave, thresholdV: thresholdV) else {
            throw LoopError.edgeNotFound(node: outputNode)
        }
        return abs(tOut - tIn)
    }

    private static func resolveProbe(_ node: String, in waveform: WaveformData) -> RealWaveform? {
        for candidate in [node, "V(\(node))", "v(\(node))", node.lowercased(), node.uppercased()] {
            if let waveform = waveform.realWaveform(named: candidate) { return waveform }
        }
        let targets: Set<String> = [node.lowercased(), "v(\(node.lowercased()))"]
        if let match = waveform.variables.first(where: { targets.contains($0.name.lowercased()) }) {
            return waveform.realWaveform(named: match.name)
        }
        return nil
    }

    private static func firstCrossing(_ wave: RealWaveform, thresholdV: Double) -> Double? {
        let times = wave.sweepValues
        let values = wave.values
        for i in 1..<min(times.count, values.count) {
            let a = values[i - 1], b = values[i]
            if (a < thresholdV && b >= thresholdV) || (a > thresholdV && b <= thresholdV) {
                let dv = b - a
                let fraction = dv == 0 ? 0 : (thresholdV - a) / dv
                return times[i - 1] + fraction * (times[i] - times[i - 1])
            }
        }
        return nil
    }
}
