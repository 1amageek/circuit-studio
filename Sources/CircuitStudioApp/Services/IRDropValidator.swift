import Foundation
import CircuitStudioCore
import CoreSpiceEvent
import CoreSpiceWaveform

/// The trust anchor for the IR-drop axis: it solves the SAME power-grid operating point in
/// BOTH CoreSpice and the ngspice oracle and compares the rail-node voltages. The cross-check
/// is single-point (`.op`), not the transient-window comparison the post-layout oracle does,
/// so it fits a DC power network. Agreement means CoreSpice solves the IR network identically
/// to ngspice, so the IR-drop verdict is scored by physics. Gated on an available ngspice.
public struct IRDropValidator: Sendable {

    public enum ValidatorError: Error, LocalizedError, Equatable {
        case noWaveform(tool: String)
        case nodeMissing(tool: String, node: String)

        public var errorDescription: String? {
            switch self {
            case .noWaveform(let t): return "\(t) produced no operating point for the IR network."
            case .nodeMissing(let t, let n): return "\(t) operating point is missing rail node '\(n)'."
            }
        }
    }

    public struct Agreement: Sendable, Hashable {
        public struct NodeDelta: Sendable, Hashable {
            public let node: String
            public let coreSpiceVolts: Double
            public let ngspiceVolts: Double
            public var deltaVolts: Double { abs(coreSpiceVolts - ngspiceVolts) }
        }
        public let nodes: [NodeDelta]
        public let toleranceV: Double
        public var maxDivergenceV: Double { nodes.map(\.deltaVolts).max() ?? .infinity }
        public var consistent: Bool { !nodes.isEmpty && maxDivergenceV <= toleranceV }
    }

    private let analyzer: IRDropAnalyzer
    private let simulation: any SimulationRunning
    private let external: ExternalSpiceSimulator

    public init(analyzer: IRDropAnalyzer = IRDropAnalyzer(),
                simulation: any SimulationRunning = SimulationService(),
                external: ExternalSpiceSimulator = ExternalSpiceSimulator()) {
        self.analyzer = analyzer
        self.simulation = simulation
        self.external = external
    }

    public static func ngspiceAvailable() -> Bool { PostLayoutOracleService.ngspiceAvailable() }

    public func validate(_ model: PowerGridModel, toleranceV: Double = 5e-3) async throws -> Agreement {
        let (deck, taps) = analyzer.buildDeck(model)
        let probes = taps.flatMap { [$0.vpwr, $0.vgnd] }

        let csResult = try await simulation.runAnalysis(source: deck, fileName: "ir-op.cir", processConfiguration: nil, command: .op)
        guard let csWave = csResult.waveform else { throw ValidatorError.noWaveform(tool: "CoreSpice") }
        let ngWave = try await external.run(source: deck, fileName: "ir-op.cir", processConfiguration: nil, command: .op, cancellation: CancellationToken())

        var deltas: [Agreement.NodeDelta] = []
        for node in probes {
            guard let cs = nodeVoltage(node, in: csWave) else { throw ValidatorError.nodeMissing(tool: "CoreSpice", node: node) }
            guard let ng = nodeVoltage(node, in: ngWave) else { throw ValidatorError.nodeMissing(tool: "ngspice", node: node) }
            deltas.append(Agreement.NodeDelta(node: node, coreSpiceVolts: cs, ngspiceVolts: ng))
        }
        return Agreement(nodes: deltas, toleranceV: toleranceV)
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
}
