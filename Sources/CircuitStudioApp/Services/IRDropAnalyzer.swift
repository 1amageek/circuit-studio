import Foundation
import CircuitStudioCore
import CoreSpiceWaveform

/// Solves a `PowerGridModel` for static IR drop: it builds the rail network as a SPICE deck
/// (VPWR/VGND resistor ladders fed at VDD/ground, a current source per cell between the
/// rails) and runs a CoreSpice DC operating point, then reports the worst cell's effective
/// supply VDD − (V_vpwr − V_vgnd). CoreSpice is the ngspice-validated oracle, and
/// `IRDropValidator` cross-checks this very deck, so the IR-drop verdict rests on physics, not
/// a hand formula.
public struct IRDropAnalyzer: Sendable {

    public enum AnalyzerError: Error, LocalizedError, Equatable {
        case noTaps
        case noWaveform
        case nodeVoltageMissing(node: String)

        public var errorDescription: String? {
            switch self {
            case .noTaps: return "The power grid has no cell taps to analyze."
            case .noWaveform: return "CoreSpice produced no operating point for the power grid."
            case .nodeVoltageMissing(let n): return "Operating point is missing rail node '\(n)'."
            }
        }
    }

    private let simulation: SimulationServiceProtocol

    public init(simulation: SimulationServiceProtocol = SimulationService()) {
        self.simulation = simulation
    }

    /// Build the SPICE deck for `model` plus the (label, vpwrNode, vgndNode) of each tap. The
    /// validator reuses this so CoreSpice and ngspice solve the identical network.
    public func buildDeck(_ model: PowerGridModel) -> (deck: String, taps: [(label: String, vpwr: String, vgnd: String)]) {
        let sorted = model.taps.enumerated().sorted { $0.element.position < $1.element.position }
        var lines = ["* IR drop network for the power grid"]
        lines.append("VVDD vdd_src 0 dc \(eng(model.supplyVoltage))")

        var tapNodes: [(label: String, vpwr: String, vgnd: String)] = []
        var previous: (p: String, g: String, position: Double)? = nil
        for (order, item) in sorted.enumerated() {
            let p = "p\(order)", g = "g\(order)"
            tapNodes.append((label: item.element.label, vpwr: p, vgnd: g))
            if let prev = previous {
                let r = max(model.resistance(length: abs(item.element.position - prev.position)), 1e-6)
                lines.append("RP\(order) \(prev.p) \(p) \(eng(r))")
                lines.append("RG\(order) \(prev.g) \(g) \(eng(r))")
            } else {
                // Feed the first node from the supply / ground through the run to the feed point.
                let rFeed = max(model.resistance(length: abs(item.element.position - model.feedPosition)), 1e-6)
                lines.append("RPF \("vdd_src") \(p) \(eng(rFeed))")
                lines.append("RGF 0 \(g) \(eng(rFeed))")
            }
            // The cell draws its average current from VPWR to VGND at this tap.
            lines.append("I\(order) \(p) \(g) \(eng(item.element.current))")
            previous = (p, g, item.element.position)
        }
        return (lines.joined(separator: "\n") + "\n", tapNodes)
    }

    public func analyze(_ model: PowerGridModel, budgetFraction: Double = 0.05) async throws -> IRDropResult {
        guard !model.taps.isEmpty else { throw AnalyzerError.noTaps }
        let (deck, taps) = buildDeck(model)
        let result = try await simulation.runAnalysis(
            source: deck, fileName: "ir-drop.cir", processConfiguration: nil, command: .op)
        guard let wave = result.waveform else { throw AnalyzerError.noWaveform }

        var supplyByTap: [String: Double] = [:]
        var worst = (label: "", drop: -Double.infinity)
        for tap in taps {
            guard let vp = nodeVoltage(tap.vpwr, in: wave) else { throw AnalyzerError.nodeVoltageMissing(node: tap.vpwr) }
            guard let vg = nodeVoltage(tap.vgnd, in: wave) else { throw AnalyzerError.nodeVoltageMissing(node: tap.vgnd) }
            let effective = vp - vg
            let drop = model.supplyVoltage - effective
            supplyByTap[tap.label] = effective
            if drop > worst.drop { worst = (tap.label, drop) }
        }
        return IRDropResult(
            supplyVoltage: model.supplyVoltage,
            maxIRDropVolts: worst.drop,
            worstTapLabel: worst.label,
            budgetVolts: budgetFraction * model.supplyVoltage,
            effectiveSupplyByTap: supplyByTap)
    }

    private func nodeVoltage(_ node: String, in wave: WaveformData) -> Double? {
        for candidate in [node, "V(\(node))", "v(\(node))", node.lowercased(), node.uppercased()] {
            if let w = wave.realWaveform(named: candidate) { return w.values.last ?? w.values.first }
        }
        let targets: Set<String> = [node.lowercased(), "v(\(node.lowercased()))"]
        if let match = wave.variables.first(where: { targets.contains($0.name.lowercased()) }),
           let w = wave.realWaveform(named: match.name) {
            return w.values.last ?? w.values.first
        }
        return nil
    }

    private func eng(_ v: Double) -> String { String(format: "%.6g", v) }
}
