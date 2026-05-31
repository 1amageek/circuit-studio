import Foundation

/// Closes timing by failure-driven gate sizing: each iteration runs STA at the target clock
/// period and, while setup fails, upsizes the slowest cell on the critical path to the next
/// drive strength (stronger drive → less delay into its load) and re-analyses. The next edit
/// is COMPUTED from the measured failure (the reported critical path), not guessed — the
/// Decide stage of the loop on the timing axis. The library it reads is SPICE-characterized
/// and SPICE-validated (BC1.2/BC1.3), so the loop optimizes against trustworthy physics.
public struct TimingDrivenClosureLoop: Sendable {

    public enum ClosureError: Error, LocalizedError, Equatable {
        case nonPositiveBudget
        case variantMissingFromLibrary(String)

        public var errorDescription: String? {
            switch self {
            case .nonPositiveBudget: return "Timing closure requires maxIterations >= 1."
            case .variantMissingFromLibrary(let n): return "Sized variant '\(n)' is not in the timing library."
            }
        }
    }

    public struct Iteration: Sendable, Hashable {
        public let index: Int
        public let worstSetupSlack: Double
        public let minPeriod: Double
        public let met: Bool
        public let upsizedInstance: String?   // the cell upsized to reach the NEXT iteration
        public let upsizedTo: String?
    }

    public struct Outcome: Sendable {
        public let converged: Bool
        public let iterations: [Iteration]
        public let netlist: SequentialNetlist   // the (possibly resized) closed netlist
        public let report: TimingReport
    }

    private let library: TimingLibrary
    private let defaultInputSlew: Double

    public init(library: TimingLibrary, defaultInputSlew: Double = 50e-12) {
        self.library = library
        self.defaultInputSlew = defaultInputSlew
    }

    public func close(
        _ netlist: SequentialNetlist, targetPeriod: Double, maxIterations: Int
    ) throws -> Outcome {
        guard maxIterations >= 1 else { throw ClosureError.nonPositiveBudget }
        let analyzer = StaticTimingAnalyzer(library: library)
        var current = netlist
        var iterations: [Iteration] = []

        for index in 0..<maxIterations {
            let report = try analyzer.analyze(current, clockPeriod: targetPeriod, defaultInputSlew: defaultInputSlew)
            if report.setupMet {
                iterations.append(Iteration(index: index, worstSetupSlack: report.worstSetupSlack,
                                            minPeriod: report.minPeriod, met: true,
                                            upsizedInstance: nil, upsizedTo: nil))
                return Outcome(converged: true, iterations: iterations, netlist: current, report: report)
            }

            // Decide: upsize the slowest critical-path cell that still has a larger rung.
            let candidate = report.criticalPath.stages
                .compactMap { stage -> (stage: TimingStage, next: (name: String, relativeFactor: Double))? in
                    CellSizing.nextLarger(of: stage.cell).map { (stage, $0) }
                }
                .max(by: { $0.stage.stageDelay < $1.stage.stageDelay })

            guard let pick = candidate else {
                // Nothing left to upsize: report the unconverged result honestly.
                iterations.append(Iteration(index: index, worstSetupSlack: report.worstSetupSlack,
                                            minPeriod: report.minPeriod, met: false,
                                            upsizedInstance: nil, upsizedTo: nil))
                return Outcome(converged: false, iterations: iterations, netlist: current, report: report)
            }
            guard library.cells[pick.next.name] != nil else {
                throw ClosureError.variantMissingFromLibrary(pick.next.name)
            }
            iterations.append(Iteration(index: index, worstSetupSlack: report.worstSetupSlack,
                                        minPeriod: report.minPeriod, met: false,
                                        upsizedInstance: pick.stage.instance, upsizedTo: pick.next.name))
            current = upsize(current, instance: pick.stage.instance,
                             relativeFactor: pick.next.relativeFactor, newName: pick.next.name)
        }

        let report = try analyzer.analyze(current, clockPeriod: targetPeriod, defaultInputSlew: defaultInputSlew)
        return Outcome(converged: report.setupMet, iterations: iterations, netlist: current, report: report)
    }

    /// Replace one instance's cell with a stronger-drive variant (same topology, wider FETs).
    private func upsize(
        _ netlist: SequentialNetlist, instance: String, relativeFactor: Double, newName: String
    ) -> SequentialNetlist {
        let resized = netlist.combinational.map { inst -> GateLevelNetlist.Instance in
            guard inst.name == instance else { return inst }
            let bigger = inst.cell.scaled(widthFactor: relativeFactor, name: newName)
            return GateLevelNetlist.Instance(name: inst.name, cell: bigger, netMap: inst.netMap)
        }
        return SequentialNetlist(name: netlist.name, combinational: resized, dffs: netlist.dffs,
                                 inputs: netlist.inputs, outputs: netlist.outputs,
                                 clock: netlist.clock, vpwr: netlist.vpwr, vgnd: netlist.vgnd)
    }
}
