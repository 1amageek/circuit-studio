import Foundation
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore

/// The agent design loop (Mountain A): a failure-driven loop that sizes a CMOS
/// inverter to meet a propagation-delay spec — simulate in CoreSpice, measure the
/// delay, and (when it misses) widen the FETs via a structured edit, then re-simulate.
/// Pure CoreSpice (no external tool), so it runs everywhere.
@Suite("Spec-driven design loop (Mountain A)")
struct SpecDrivenDesignLoopTests {

    private func inverterSpec(width: Double) -> DesignFlowDesignSpec {
        DesignFlowDesignSpec(
            name: "inverter",
            title: "CMOS inverter delay loop",
            components: [
                DesignFlowDesignSpec.Component(name: "VDD", deviceKindID: "vsource", parameters: ["dc": 1.8]),
                DesignFlowDesignSpec.Component(name: "VIN", deviceKindID: "vsource", parameters: [
                    "pulse_v1": 0, "pulse_v2": 1.8, "pulse_td": 2e-9,
                    "pulse_tr": 0.5e-9, "pulse_tf": 0.5e-9, "pulse_pw": 20e-9, "pulse_per": 40e-9,
                ]),
                DesignFlowDesignSpec.Component(name: "MN", deviceKindID: "nmos_l1",
                    parameters: ["w": width, "l": 0.15e-6], modelPresetID: "generic_nmos"),
                DesignFlowDesignSpec.Component(name: "MP", deviceKindID: "pmos_l1",
                    parameters: ["w": width, "l": 0.15e-6], modelPresetID: "generic_pmos"),
                DesignFlowDesignSpec.Component(name: "CL", deviceKindID: "capacitor", parameters: ["c": 50e-15]),
                DesignFlowDesignSpec.Component(name: "GND1", deviceKindID: "ground"),
            ],
            nets: [
                DesignFlowDesignSpec.Net(name: "vdd", terminals: [
                    DesignFlowDesignSpec.Terminal(component: "VDD", port: "pos"),
                    DesignFlowDesignSpec.Terminal(component: "MP", port: "source"),
                    DesignFlowDesignSpec.Terminal(component: "MP", port: "bulk"),
                ]),
                DesignFlowDesignSpec.Net(name: "in", terminals: [
                    DesignFlowDesignSpec.Terminal(component: "VIN", port: "pos"),
                    DesignFlowDesignSpec.Terminal(component: "MN", port: "gate"),
                    DesignFlowDesignSpec.Terminal(component: "MP", port: "gate"),
                ]),
                DesignFlowDesignSpec.Net(name: "out", terminals: [
                    DesignFlowDesignSpec.Terminal(component: "MN", port: "drain"),
                    DesignFlowDesignSpec.Terminal(component: "MP", port: "drain"),
                    DesignFlowDesignSpec.Terminal(component: "CL", port: "pos"),
                ]),
                DesignFlowDesignSpec.Net(name: "0", terminals: [
                    DesignFlowDesignSpec.Terminal(component: "VDD", port: "neg"),
                    DesignFlowDesignSpec.Terminal(component: "VIN", port: "neg"),
                    DesignFlowDesignSpec.Terminal(component: "MN", port: "source"),
                    DesignFlowDesignSpec.Terminal(component: "MN", port: "bulk"),
                    DesignFlowDesignSpec.Terminal(component: "CL", port: "neg"),
                    DesignFlowDesignSpec.Terminal(component: "GND1", port: "gnd"),
                ]),
            ],
            analyses: [DesignFlowDesignSpec.Analysis(kind: .tran, stopTime: 30e-9, stepTime: 0.02e-9)],
            pexIR: nil
        )
    }

    @Test(.timeLimit(.minutes(2)))
    func sizesInverterToMeetDelaySpec() async throws {
        // A narrow inverter into a 50 fF load misses the delay target; the loop must
        // widen the FETs (failure-driven) until it meets the spec.
        let initial = inverterSpec(width: 0.3e-6)
        let spec = PerformanceSpec(metric: .propagationDelaySeconds, comparison: .atMost, target: 0.2e-9)
        let tunable = SpecDrivenDesignLoop.Tunable(
            componentNames: ["MN", "MP"],
            parameter: "w",
            effect: .largerReducesMetric,
            stepFactor: 1.7,
            minValue: 0.1e-6,
            maxValue: 20e-6
        )

        let outcome = try await SpecDrivenDesignLoop().run(
            initial: initial, tunable: tunable, spec: spec, maxIterations: 10
        ) { waveform in
            try SpecDrivenDesignLoop.propagationDelay(
                in: waveform, from: "in", to: "out", thresholdV: 0.9
            )
        }

        // It converged, and only by actually doing work (the first design failed).
        #expect(outcome.converged, "iterations: \(outcome.iterations.map { ($0.parameterValue, $0.measuredMetric, $0.met) })")
        let first = try #require(outcome.iterations.first)
        let last = try #require(outcome.iterations.last)
        #expect(first.met == false, "the initial narrow design should miss the spec")
        #expect(last.met == true)
        #expect(spec.isMet(by: last.measuredMetric))
        // The edit was failure-driven: the FETs widened and the delay fell.
        #expect(last.parameterValue > first.parameterValue)
        #expect(last.measuredMetric < first.measuredMetric)
    }

    @Test("A non-positive budget fails loud")
    func nonPositiveBudgetFailsLoud() async {
        await #expect(throws: SpecDrivenDesignLoop.LoopError.nonPositiveBudget) {
            _ = try await SpecDrivenDesignLoop().run(
                initial: inverterSpec(width: 1e-6),
                tunable: SpecDrivenDesignLoop.Tunable(
                    componentNames: ["MN"], parameter: "w", effect: .largerReducesMetric,
                    stepFactor: 1.5, minValue: 0.1e-6, maxValue: 10e-6
                ),
                spec: PerformanceSpec(metric: .propagationDelaySeconds, comparison: .atMost, target: 1e-9),
                maxIterations: 0
            ) { _ in 0 }
        }
    }
}
