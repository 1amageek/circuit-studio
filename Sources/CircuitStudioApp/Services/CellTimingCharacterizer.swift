import Foundation
import CircuitStudioCore
import CoreSpiceEvent
import CoreSpiceWaveform

/// Characterizes a `CMOSGateNetlist` cell into an NLDM `CellTiming` by simulating it in
/// CoreSpice: for each input→output arc it sweeps a grid of input slew × output load,
/// drives the pin with a ramped pulse (other pins held at their non-controlling value so
/// the arc is sensitised), and measures the 50%→50% propagation delay and the 20%↔80%
/// output transition. The cell-delay and output-slew LUTs it fills are exactly what the
/// `StaticTimingAnalyzer` interpolates — produced from physics, not assumed.
public struct CellTimingCharacterizer: Sendable {

    public enum CharacterizeError: Error, LocalizedError, Equatable {
        case noWaveform(cell: String, pin: String)
        case probeMissing(node: String)
        case edgeNotObserved(cell: String, pin: String, detail: String)
        case unsensitizable(cell: String, pin: String)

        public var errorDescription: String? {
            switch self {
            case .noWaveform(let c, let p): return "CoreSpice produced no waveform characterizing \(c).\(p)."
            case .probeMissing(let n): return "Characterization waveform is missing probe '\(n)'."
            case .edgeNotObserved(let c, let p, let d): return "No \(d) edge observed for \(c).\(p)."
            case .unsensitizable(let c, let p): return "Could not sensitise an arc through \(c).\(p)."
            }
        }
    }

    private let model: Level1DeviceModel
    private let simulation: SimulationServiceProtocol
    private let inputSlews: [Double]
    private let outputLoads: [Double]
    private let logic = GateLevelLogicSimulator()

    public init(
        model: Level1DeviceModel,
        simulation: SimulationServiceProtocol = SimulationService(),
        inputSlews: [Double] = [20e-12, 80e-12, 320e-12],
        outputLoads: [Double] = [0.5e-15, 2e-15, 8e-15]
    ) {
        self.model = model
        self.simulation = simulation
        self.inputSlews = inputSlews
        self.outputLoads = outputLoads
    }

    public init(
        simulation: SimulationServiceProtocol = SimulationService(),
        inputSlews: [Double] = [20e-12, 80e-12, 320e-12],
        outputLoads: [Double] = [0.5e-15, 2e-15, 8e-15]
    ) throws {
        self.init(
            model: try Level1DeviceModel.loadBundledDefault(),
            simulation: simulation,
            inputSlews: inputSlews,
            outputLoads: outputLoads
        )
    }

    /// Characterize every input pin of `cell` into a `CellTiming`.
    public func characterize(_ cell: CMOSGateNetlist) async throws -> CellTiming {
        let pins = orderedPins(cell)
        var arcs: [TimingArc] = []
        var caps: [String: Double] = [:]
        for pin in pins {
            arcs.append(try await characterizeArc(cell, pin: pin))
            caps[pin] = model.inputCapacitance(of: cell, pin: pin)
        }
        return CellTiming(cellName: cell.name, inputCapacitance: caps, arcs: arcs)
    }

    // MARK: - one arc

    private func characterizeArc(_ cell: CMOSGateNetlist, pin: String) async throws -> TimingArc {
        let sideValues = try sensitizingSideValues(cell, pin: pin)
        var dRise = grid(), dFall = grid(), tRise = grid(), tFall = grid()
        for (i, slew) in inputSlews.enumerated() {
            for (j, load) in outputLoads.enumerated() {
                let m = try await measure(cell, pin: pin, sideValues: sideValues, slew: slew, load: load)
                dFall[i][j] = m.delayFall; dRise[i][j] = m.delayRise
                tFall[i][j] = m.slewFall; tRise[i][j] = m.slewRise
            }
        }
        return TimingArc(
            inputPin: pin, sense: .negativeUnate,
            delayRise: try TimingLUT(inputSlews: inputSlews, outputLoads: outputLoads, values: dRise),
            delayFall: try TimingLUT(inputSlews: inputSlews, outputLoads: outputLoads, values: dFall),
            transitionRise: try TimingLUT(inputSlews: inputSlews, outputLoads: outputLoads, values: tRise),
            transitionFall: try TimingLUT(inputSlews: inputSlews, outputLoads: outputLoads, values: tFall))
    }

    private struct ArcMeasurement { let delayRise, delayFall, slewRise, slewFall: Double }

    private func measure(
        _ cell: CMOSGateNetlist, pin: String, sideValues: [String: Bool], slew: Double, load: Double
    ) async throws -> ArcMeasurement {
        let vdd = model.supplyVoltage
        let mid = vdd / 2, lo = 0.2 * vdd, hi = 0.8 * vdd
        let edgeTime = slew / 0.6                 // 0→100% ramp giving a 20–80% slew of `slew`
        let high = max(2e-9, 10 * slew)           // output settle time per level
        let delay = 1e-9
        let stop = delay + edgeTime + high + edgeTime + high + 1e-9
        let step = max(0.5e-12, slew / 60)
        let outputNode = cell.output

        let deck = buildDeck(cell, pin: pin, sideValues: sideValues, vdd: vdd,
                             edgeTime: edgeTime, delay: delay, high: high, load: load)
        let result = try await simulation.runAnalysis(
            source: deck, fileName: "char-\(cell.name)-\(pin).cir", processConfiguration: nil,
            command: .tran(TranSpec(stopTime: stop, stepTime: step)))
        guard let wave = result.waveform else { throw CharacterizeError.noWaveform(cell: cell.name, pin: pin) }

        guard let inW = probe(pin, in: wave) else { throw CharacterizeError.probeMissing(node: pin) }
        guard let outW = probe(outputNode, in: wave) else { throw CharacterizeError.probeMissing(node: outputNode) }
        let it = inW.sweepValues, iv = inW.values, ot = outW.sweepValues, ov = outW.values

        // Window boundaries: the input rises in the first half (after `fallWindow`, before
        // `riseWindow`) and falls in the second half (after `riseWindow`). Measuring within
        // these windows — not relative to the input 50% crossing — keeps the output edge in
        // view even when a slow input lets the output switch before the input reaches 50%.
        let fallWindow = delay / 2
        guard let riseWindow = WaveformTiming.crossing(times: it, values: iv, threshold: mid, direction: .rising, after: fallWindow) else {
            throw CharacterizeError.edgeNotObserved(cell: cell.name, pin: pin, detail: "input-rise")
        }

        // Rising input -> output falls.
        guard let delayFall = WaveformTiming.propagationDelay(
            inputTimes: it, inputValues: iv, outputTimes: ot, outputValues: ov,
            mid: mid, inputDirection: .rising, outputDirection: .falling, after: fallWindow),
              let slewFall = WaveformTiming.transition(times: ot, values: ov, lower: lo, upper: hi, direction: .falling, after: fallWindow)
        else { throw CharacterizeError.edgeNotObserved(cell: cell.name, pin: pin, detail: "output-fall") }

        // Falling input -> output rises.
        guard let delayRise = WaveformTiming.propagationDelay(
            inputTimes: it, inputValues: iv, outputTimes: ot, outputValues: ov,
            mid: mid, inputDirection: .falling, outputDirection: .rising, after: riseWindow),
              let slewRise = WaveformTiming.transition(times: ot, values: ov, lower: lo, upper: hi, direction: .rising, after: riseWindow)
        else { throw CharacterizeError.edgeNotObserved(cell: cell.name, pin: pin, detail: "output-rise") }

        return ArcMeasurement(delayRise: delayRise, delayFall: delayFall, slewRise: slewRise, slewFall: slewFall)
    }

    // MARK: - deck

    private func buildDeck(
        _ cell: CMOSGateNetlist, pin: String, sideValues: [String: Bool], vdd: Double,
        edgeTime: Double, delay: Double, high: Double, load: Double
    ) -> String {
        func node(_ local: String) -> String {
            if local == cell.vpwr { return "vdd" }
            if local == cell.vgnd { return "0" }
            return local
        }
        var lines = ["* characterize \(cell.name) arc \(pin)"]
        lines.append("VDD vdd 0 dc \(eng(vdd))")
        for (side, value) in sideValues.sorted(by: { $0.key < $1.key }) {
            lines.append("V_\(side) \(side) 0 dc \(eng(value ? vdd : 0))")
        }
        let period = 2 * (delay + edgeTime + high)
        lines.append("VIN \(pin) 0 PULSE(0 \(eng(vdd)) \(eng(delay)) \(eng(edgeTime)) \(eng(edgeTime)) \(eng(high)) \(eng(period)))")
        for d in cell.devices {
            let m = d.kind == .nmos ? model.nmosModelName : model.pmosModelName
            let bulk = d.kind == .nmos ? "0" : "vdd"
            lines.append("M\(d.name) \(node(d.drain)) \(node(d.gate)) \(node(d.source)) \(bulk) \(m) W=\(d.width)u L=\(d.length)u")
        }
        lines.append("CL \(node(cell.output)) 0 \(eng(load))")
        lines.append(model.nmosCard)
        lines.append(model.pmosCard)
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - helpers

    /// Side-pin values that make `cell`'s output depend on `pin` (so the arc is real).
    private func sensitizingSideValues(_ cell: CMOSGateNetlist, pin: String) throws -> [String: Bool] {
        let others = orderedPins(cell).filter { $0 != pin }
        for combo in 0..<(1 << others.count) {
            var assign: [String: Bool] = [:]
            for (k, p) in others.enumerated() { assign[p] = (combo >> k) & 1 == 1 }
            let low = logic.cellOutput(cell) { $0 == pin ? false : (assign[$0] ?? false) }
            let high = logic.cellOutput(cell) { $0 == pin ? true : (assign[$0] ?? false) }
            if low != high { return assign }
        }
        throw CharacterizeError.unsensitizable(cell: cell.name, pin: pin)
    }

    private func orderedPins(_ cell: CMOSGateNetlist) -> [String] {
        var seen = Set<String>(), order: [String] = []
        for d in cell.devices where d.gate != cell.vpwr && d.gate != cell.vgnd && !seen.contains(d.gate) {
            seen.insert(d.gate); order.append(d.gate)
        }
        return order
    }

    private func grid() -> [[Double]] {
        Array(repeating: Array(repeating: 0.0, count: outputLoads.count), count: inputSlews.count)
    }

    private func eng(_ v: Double) -> String { String(format: "%.6g", v) }

    private func probe(_ node: String, in wave: WaveformData) -> RealWaveform? {
        for candidate in [node, "V(\(node))", "v(\(node))", node.lowercased(), node.uppercased()] {
            if let w = wave.realWaveform(named: candidate) { return w }
        }
        let targets: Set<String> = [node.lowercased(), "v(\(node.lowercased()))"]
        if let match = wave.variables.first(where: { targets.contains($0.name.lowercased()) }) {
            return wave.realWaveform(named: match.name)
        }
        return nil
    }
}
