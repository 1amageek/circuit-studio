import Foundation
import CoreSpiceEvent
import CoreSpiceWaveform

/// Cross-checks a post-layout deck against an independent oracle (ngspice): it runs
/// the SAME netlist through CoreSpice (in-process) and ngspice (external) under the
/// same analysis command, and reports the maximum waveform divergence per probe.
///
/// This is how the Measure stage earns trust on the actual designs the flow
/// produces — not just the curated trust gate. The deck must stay within
/// CoreSpice's model envelope (level-1/2/3 + RLC), which a post-layout netlist
/// (level-1/3 design netlist + extracted parasitics) does; both tools then run the
/// identical deck.
///
/// ngspice is optional evidence: `ngspiceAvailable()` reports whether a binary is
/// reachable, so the caller can cross-check when it is present without a silent
/// fallback when it is not.
public struct PostLayoutOracleService: Sendable {

    /// Per-probe agreement between CoreSpice and the ngspice oracle.
    public struct ProbeAgreement: Sendable, Hashable, Codable {
        public let probe: String
        public let maxAbsoluteDeltaV: Double
        public let sampleCount: Int

        public init(probe: String, maxAbsoluteDeltaV: Double, sampleCount: Int) {
            self.probe = probe
            self.maxAbsoluteDeltaV = maxAbsoluteDeltaV
            self.sampleCount = sampleCount
        }
    }

    /// The overall CoreSpice-vs-ngspice agreement for a deck.
    public struct Agreement: Sendable, Hashable, Codable {
        public let probes: [ProbeAgreement]
        public let toleranceV: Double

        public init(probes: [ProbeAgreement], toleranceV: Double) {
            self.probes = probes
            self.toleranceV = toleranceV
        }

        /// The worst per-probe divergence (volts).
        public var maxDivergenceV: Double { probes.map(\.maxAbsoluteDeltaV).max() ?? .infinity }
        /// True when every probe agrees within tolerance.
        public var consistent: Bool { !probes.isEmpty && maxDivergenceV <= toleranceV }
    }

    public enum OracleError: Error, LocalizedError, Equatable {
        case noProbes
        case deckRequiresExternalModels
        case coreSpiceProducedNoWaveform
        case probeNotFound(probe: String, tool: String)

        public var errorDescription: String? {
            switch self {
            case .noProbes:
                return "The oracle cross-check needs at least one probe node."
            case .deckRequiresExternalModels:
                return "The deck needs models outside CoreSpice's envelope (e.g. BSIM), so CoreSpice cannot simulate it — the cross-check would compare ngspice against itself. Render the design within CoreSpice's level-1/2/3 + RLC envelope first."
            case .coreSpiceProducedNoWaveform:
                return "CoreSpice produced no waveform for the oracle deck."
            case .probeNotFound(let probe, let tool):
                return "Probe '\(probe)' was not found in the \(tool) waveform."
            }
        }
    }

    private let simulation: SimulationServiceProtocol
    private let external: ExternalSpiceSimulator

    public init(
        simulation: SimulationServiceProtocol = SimulationService(),
        external: ExternalSpiceSimulator = ExternalSpiceSimulator()
    ) {
        self.simulation = simulation
        self.external = external
    }

    /// Whether an ngspice binary is reachable (`NGSPICE_BIN`, or `ngspice` on PATH).
    public static func ngspiceAvailable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> Bool {
        let configured = environment["NGSPICE_BIN"] ?? "ngspice"
        if configured.contains("/") {
            return fileManager.isExecutableFile(atPath: configured)
        }
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = "\(directory)/\(configured)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return true
            }
        }
        return false
    }

    /// Runs `deck` (without its own analysis line — `command` drives both tools) in
    /// CoreSpice and ngspice, and returns the per-probe agreement. Throws (never
    /// silently passes) when a probe is missing from either tool's output.
    public func crossCheck(
        deck: String,
        command: AnalysisCommand,
        probes: [String],
        toleranceV: Double = 0.1
    ) async throws -> Agreement {
        guard !probes.isEmpty else { throw OracleError.noProbes }

        // If the deck needs external models, CoreSpice's own runAnalysis would itself
        // route to ngspice — the cross-check would silently compare ngspice against
        // ngspice and always "agree". Refuse loudly instead of reporting false trust.
        if external.requiresExternalSimulation(source: deck, fileName: "oracle.cir", processConfiguration: nil) {
            throw OracleError.deckRequiresExternalModels
        }

        let csResult = try await simulation.runAnalysis(
            source: deck, fileName: "oracle.cir", processConfiguration: nil, command: command
        )
        guard let csWave = csResult.waveform else { throw OracleError.coreSpiceProducedNoWaveform }

        let ngWave = try await external.run(
            source: deck, fileName: "oracle.cir", processConfiguration: nil,
            command: command, cancellation: CancellationToken()
        )

        var agreements: [ProbeAgreement] = []
        for probe in probes {
            guard let cs = resolveProbe(probe, in: csWave) else {
                throw OracleError.probeNotFound(probe: probe, tool: "CoreSpice")
            }
            guard let ng = resolveProbe(probe, in: ngWave) else {
                throw OracleError.probeNotFound(probe: probe, tool: "ngspice")
            }
            let (delta, count) = maxAbsoluteDelta(cs, ng)
            agreements.append(ProbeAgreement(probe: probe, maxAbsoluteDeltaV: delta, sampleCount: count))
        }
        return Agreement(probes: agreements, toleranceV: toleranceV)
    }

    // MARK: - waveform helpers

    /// Resolves a probe node to a real waveform across the two tools' naming
    /// conventions (CoreSpice keeps `out`/`V(out)`, ngspice lowercases to `v(out)`).
    private func resolveProbe(_ probe: String, in wave: WaveformData) -> RealWaveform? {
        let candidates = [probe, "V(\(probe))", "v(\(probe))", probe.lowercased(), probe.uppercased()]
        for candidate in candidates {
            if let waveform = wave.realWaveform(named: candidate) { return waveform }
        }
        let targets = Set([probe.lowercased(), "v(\(probe.lowercased()))"])
        if let match = wave.variables.first(where: { targets.contains($0.name.lowercased()) }) {
            return wave.realWaveform(named: match.name)
        }
        return nil
    }

    /// Max |V_cs - V_ng| over the overlapping time window, sampled on a uniform grid
    /// with linear interpolation (the two tools choose different time points).
    private func maxAbsoluteDelta(_ a: RealWaveform, _ b: RealWaveform, samples: Int = 200) -> (Double, Int) {
        let at = a.sweepValues, av = a.values
        let bt = b.sweepValues, bv = b.values
        guard let a0 = at.first, let a1 = at.last, let b0 = bt.first, let b1 = bt.last,
              !av.isEmpty, !bv.isEmpty else { return (.infinity, 0) }
        let t0 = max(a0, b0), t1 = min(a1, b1)
        guard t1 > t0 else { return (.infinity, 0) }
        var maxDelta = 0.0
        for i in 0...samples {
            let t = t0 + (t1 - t0) * Double(i) / Double(samples)
            maxDelta = max(maxDelta, abs(interpolate(at, av, t) - interpolate(bt, bv, t)))
        }
        return (maxDelta, samples + 1)
    }

    private func interpolate(_ ts: [Double], _ vs: [Double], _ t: Double) -> Double {
        if t <= ts[0] { return vs[0] }
        if t >= ts[ts.count - 1] { return vs[vs.count - 1] }
        for k in 1..<ts.count where ts[k] >= t {
            let dt = ts[k] - ts[k - 1]
            let fraction = dt == 0 ? 0 : (t - ts[k - 1]) / dt
            return vs[k - 1] + fraction * (vs[k] - vs[k - 1])
        }
        return vs[vs.count - 1]
    }
}
