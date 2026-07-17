import Foundation
import CircuitStudioCore
import CoreSpiceEvent
import CoreSpiceWaveform
import STAEngine

public protocol TimingPathValidating: Sendable {
    func validate(
        path: STAPath,
        in netlist: SequentialNetlist,
        launchSlew: Double,
        toleranceFraction: Double
    ) async throws -> STAvsSPICEValidator.Result
}

/// The trust anchor for the timing axis: it re-simulates the STA critical path's actual
/// gate chain in CoreSpice and compares the measured end-to-end delay against the sum of
/// arc delays the canonical STA result predicted. Each stage is driven by the previous,
/// its side inputs held at their non-controlling value (so the same arcs are exercised),
/// and each net loaded with the exact capacitance STA assumed — so the comparison isolates
/// the STA abstraction (NLDM interpolation + slew/load propagation), not the model. CoreSpice
/// itself is the ngspice-validated oracle (G5), so agreement here closes the chain
/// ngspice ⟷ CoreSpice ⟷ STA.
public struct STAvsSPICEValidator: TimingPathValidating {

    public enum ValidatorError: Error, LocalizedError, Equatable {
        case emptyPath
        case instanceNotFound(String)
        case noWaveform
        case probeMissing(String)
        case delayNotObserved

        public var errorDescription: String? {
            switch self {
            case .emptyPath: return "The critical path has no stages to validate."
            case .instanceNotFound(let n): return "Path stage instance '\(n)' is not in the netlist."
            case .noWaveform: return "CoreSpice produced no waveform for the path deck."
            case .probeMissing(let n): return "Path-deck waveform is missing probe '\(n)'."
            case .delayNotObserved: return "The path output edge was not observed in SPICE."
            }
        }
    }

    public struct Result: Sendable, Hashable {
        public let staDelay: Double      // sum of STA arc delays along the path
        public let spiceDelay: Double    // measured end-to-end SPICE delay of the same chain
        public let relativeError: Double // |spice - sta| / spice
        public let tolerance: Double
        public var agrees: Bool { relativeError <= tolerance }
    }

    private let model: Level1DeviceModel
    private let simulation: any SimulationRunning
    private let logic = GateLevelLogicSimulator()

    public init(model: Level1DeviceModel,
                simulation: any SimulationRunning = SimulationService()) {
        self.model = model
        self.simulation = simulation
    }

    public init(simulation: any SimulationRunning = SimulationService()) throws {
        self.init(model: try Level1DeviceModel.loadBundledDefault(), simulation: simulation)
    }

    /// Maximum stages per simulated segment. A deep inverting chain's transient Newton solve
    /// stops converging once it is more than a couple of stages long, but stage delays
    /// TELESCOPE (Σ per-stage 50→50 = end-to-end 50→50), so validating gate-pair segments
    /// and summing their SPICE delays measures the exact same end-to-end delay — still
    /// exercising real slew propagation through each pair — while every segment converges.
    private let maxStagesPerSegment = 2

    public func validate(
        path: STAPath,
        in netlist: SequentialNetlist,
        launchSlew: Double,
        toleranceFraction: Double = 0.15
    ) async throws -> Result {
        guard !path.stages.isEmpty else { throw ValidatorError.emptyPath }
        let byName = Dictionary(uniqueKeysWithValues: netlist.combinational.map { ($0.name, $0) })

        var spiceTotal = 0.0
        var start = 0
        while start < path.stages.count {
            let end = min(start + maxStagesPerSegment, path.stages.count)
            let segment = Array(path.stages[start..<end])
            // Input slew entering this segment is the slew STA propagated to its first net.
            let segmentInputSlew = start == 0 ? launchSlew : path.stages[start - 1].outputSlew
            spiceTotal += try await simulateSegment(segment, launchSlew: segmentInputSlew, byName: byName)
            start = end
        }

        let sta = path.stages.reduce(0) { $0 + $1.delay }
        let denom = abs(spiceTotal) > 1e-15 ? abs(spiceTotal) : 1e-15
        return Result(staDelay: sta, spiceDelay: spiceTotal,
                      relativeError: abs(spiceTotal - sta) / denom, tolerance: toleranceFraction)
    }

    /// Simulate one short chain segment and return its measured 50%→50% delay (the input
    /// edge of the first stage to the output edge of the last).
    private func simulateSegment(
        _ stages: [STAPathStage], launchSlew rawSlew: Double, byName: [String: GateLevelNetlist.Instance]
    ) async throws -> Double {
        let vdd = model.supplyVoltage
        let mid = vdd / 2
        let launchSlew = max(rawSlew, 5e-12)
        let edgeTime = launchSlew / 0.6
        let delay = 1e-9
        let segmentDelay = stages.reduce(0) { $0 + $1.delay }
        let settle = max(2e-9, 25 * abs(segmentDelay) + 20 * launchSlew)
        let period = 2 * (delay + edgeTime + settle)
        let stop = delay + edgeTime + settle + 1e-9
        let step = max(0.3e-12, launchSlew / 100)
        let startEdge = stages.first?.inputEdge ?? .rise
        let startHigh = startEdge == .fall

        var lines = ["* validate path segment"]
        lines.append("VDD vdd 0 dc \(eng(vdd))")
        lines.append("VIN din 0 PULSE(\(eng(startHigh ? vdd : 0)) \(eng(startHigh ? 0 : vdd)) \(eng(delay)) \(eng(edgeTime)) \(eng(edgeTime)) \(eng(settle)) \(eng(period)))")
        for (i, stage) in stages.enumerated() {
            guard let inst = byName[stage.instance] else { throw ValidatorError.instanceNotFound(stage.instance) }
            let inputNode = i == 0 ? "din" : "n\(i - 1)"
            let outputNode = "n\(i)"
            lines += emitStage(inst.cell, index: i, controllingPin: stage.inputPin,
                               inputNode: inputNode, outputNode: outputNode, vdd: vdd)
            lines.append("Cs\(i) \(outputNode) 0 \(eng(max(stage.load, 1e-18)))")
        }
        // Seed the operating point with bare node names (the parser reads `.nodeset name =
        // value`, not `V(name)`): each sensitized stage inverts, so the nodes alternate.
        let dinDC = startHigh ? vdd : 0.0, notDinDC = startHigh ? 0.0 : vdd
        for i in 0..<stages.count { lines.append(".nodeset n\(i)=\(eng(i % 2 == 0 ? notDinDC : dinDC))") }
        lines.append(model.nmosCard)
        lines.append(model.pmosCard)
        let deck = lines.joined(separator: "\n") + "\n"

        let result = try await simulation.runAnalysis(
            source: deck, fileName: "segment.cir", processConfiguration: nil,
            command: .tran(TranSpec(stopTime: stop, stepTime: step)))
        guard let wave = result.waveform else { throw ValidatorError.noWaveform }
        let finalNode = "n\(stages.count - 1)"
        guard let inW = probe("din", in: wave) else { throw ValidatorError.probeMissing("din") }
        guard let outW = probe(finalNode, in: wave) else { throw ValidatorError.probeMissing(finalNode) }

        let inDir: WaveformTiming.Direction = startEdge == .rise ? .rising : .falling
        let outDir: WaveformTiming.Direction = stages.last?.outputEdge == .rise ? .rising : .falling
        guard let segmentSpice = WaveformTiming.propagationDelay(
            inputTimes: inW.sweepValues, inputValues: inW.values,
            outputTimes: outW.sweepValues, outputValues: outW.values,
            mid: mid, inputDirection: inDir, outputDirection: outDir, after: delay / 2)
        else { throw ValidatorError.delayNotObserved }
        return segmentSpice
    }

    // MARK: - deck emission

    private func emitStage(
        _ cell: CMOSGateNetlist, index i: Int, controllingPin: String,
        inputNode: String, outputNode: String, vdd: Double
    ) -> [String] {
        let sideValues = sensitizingSideValues(cell, pin: controllingPin)
        func node(_ local: String) -> String {
            if local == cell.vpwr { return "vdd" }
            if local == cell.vgnd { return "0" }
            if local == cell.output { return outputNode }
            if local == controllingPin { return inputNode }
            return "s\(i)_\(local)"   // side pins + internal nodes, uniquified per stage
        }
        var lines: [String] = []
        for (side, value) in sideValues.sorted(by: { $0.key < $1.key }) {
            lines.append("V\(i)_\(side) s\(i)_\(side) 0 dc \(eng(value ? vdd : 0))")
        }
        for d in cell.devices {
            let m = d.kind == .nmos ? model.nmosModelName : model.pmosModelName
            let bulk = d.kind == .nmos ? "0" : "vdd"
            lines.append("M\(i)_\(d.name) \(node(d.drain)) \(node(d.gate)) \(node(d.source)) \(bulk) \(m) W=\(d.width)u L=\(d.length)u")
        }
        return lines
    }

    private func sensitizingSideValues(_ cell: CMOSGateNetlist, pin: String) -> [String: Bool] {
        let others = orderedPins(cell).filter { $0 != pin }
        for combo in 0..<(1 << others.count) {
            var assign: [String: Bool] = [:]
            for (k, p) in others.enumerated() { assign[p] = (combo >> k) & 1 == 1 }
            let low = logic.cellOutput(cell) { $0 == pin ? false : (assign[$0] ?? false) }
            let high = logic.cellOutput(cell) { $0 == pin ? true : (assign[$0] ?? false) }
            if low != high { return assign }
        }
        return [:]   // a single-input cell has no side pins
    }

    private func orderedPins(_ cell: CMOSGateNetlist) -> [String] {
        var seen = Set<String>(), order: [String] = []
        for d in cell.devices where d.gate != cell.vpwr && d.gate != cell.vgnd && !seen.contains(d.gate) {
            seen.insert(d.gate); order.append(d.gate)
        }
        return order
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
