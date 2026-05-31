import Foundation

/// Path-based static timing analysis on a `SequentialNetlist`: it builds the timing graph
/// (flip-flop Q outputs and primary inputs launch; flip-flop D inputs capture), propagates
/// per-edge (rise/fall) arrival times and slews through each cell's NLDM arcs from the
/// `TimingLibrary`, and reports setup/hold slack, the achievable clock frequency, and the
/// critical path. The library it reads is SPICE-characterized and SPICE-validated, so the
/// abstraction is anchored to physics rather than assumed.
///
/// Modeling scope (BC1): single clock, zero skew, ideal interconnect (wire load = 0 — real
/// RC arrives with PEX back-annotation). A constant input (a rail-tied gate pin) carries no
/// arc. Min/max arrival are reduced within one process corner (path-length min/max), giving
/// a setup verdict (latest) and a hold estimate (earliest).
public struct StaticTimingAnalyzer: Sendable {

    public enum STAError: Error, LocalizedError, Equatable {
        case combinationalCycle
        case noSequentialEndpoints

        public var errorDescription: String? {
            switch self {
            case .combinationalCycle: return "STA found a combinational cycle (no flip-flop breaks the loop)."
            case .noSequentialEndpoints: return "STA found no flip-flop data endpoints to constrain."
            }
        }
    }

    /// Arrival/required at a primary input (its launch condition).
    public struct InputDrive: Sendable, Hashable {
        public var arrival: Double
        public var slew: Double
        public init(arrival: Double = 0, slew: Double) { self.arrival = arrival; self.slew = slew }
    }

    /// A rise/fall pair (arrival or slew), per edge.
    private struct EdgePair: Sendable {
        var rise: Double
        var fall: Double
        func at(_ e: TimingEdge) -> Double { e == .rise ? rise : fall }
        mutating func set(_ e: TimingEdge, _ v: Double) { if e == .rise { rise = v } else { fall = v } }
        static func both(_ v: Double) -> EdgePair { EdgePair(rise: v, fall: v) }
    }

    /// A backpointer for critical-path tracing: which stage produced an output edge.
    private struct Pred: Sendable {
        let instanceIndex: Int
        let inputPin: String
        let inputNet: String
        let inputEdge: TimingEdge
        let stageDelay: Double
        let outputSlew: Double
        let load: Double
    }

    private let library: TimingLibrary
    public init(library: TimingLibrary) { self.library = library }

    public func analyze(
        _ netlist: SequentialNetlist,
        clockPeriod: Double,
        defaultInputSlew: Double,
        primaryInputDrive: InputDrive? = nil
    ) throws -> TimingReport {
        let ff = try library.sequential()
        let rails: Set<String> = [netlist.vpwr, netlist.vgnd, netlist.clock]
        let qNets = Set(netlist.dffs.map(\.q))
        let primaryInputs = Set(netlist.inputs)

        // Per-cell timing, fetched once.
        var cellTimings: [String: CellTiming] = [:]
        for inst in netlist.combinational where cellTimings[inst.cell.name] == nil {
            cellTimings[inst.cell.name] = try library.cell(inst.cell.name)
        }

        // Net load = sum of sink input capacitances (ideal wires).
        var netLoad: [String: Double] = [:]
        for inst in netlist.combinational {
            let ct = cellTimings[inst.cell.name]
            for pin in Set(inst.cell.devices.map(\.gate)) {
                let net = inst.net(pin)
                guard !rails.contains(net) else { continue }
                netLoad[net, default: 0] += ct?.inputCapacitance[pin] ?? 0
            }
        }
        for dff in netlist.dffs { netLoad[dff.d, default: 0] += ff.dataCapacitance }

        // Topologically order combinational instances (sources: primary inputs, Q, rails).
        let order = try topologicalOrder(netlist, sources: primaryInputs.union(qNets).union(rails))

        var lateArr: [String: EdgePair] = [:], lateSlew: [String: EdgePair] = [:]
        var earlyArr: [String: EdgePair] = [:]
        var latePred: [String: [TimingEdge: Pred]] = [:]
        var launchDelayOf: [String: Double] = [:]

        // Launch the sources.
        for net in primaryInputs {
            let drive = primaryInputDrive ?? InputDrive(arrival: 0, slew: defaultInputSlew)
            lateArr[net] = .both(drive.arrival); earlyArr[net] = .both(drive.arrival)
            lateSlew[net] = .both(drive.slew)
            launchDelayOf[net] = 0
        }
        for dff in netlist.dffs {
            let load = netLoad[dff.q] ?? 0
            var arr = EdgePair(rise: 0, fall: 0), slew = EdgePair(rise: 0, fall: 0)
            for e in [TimingEdge.rise, .fall] {
                let delayLUT = ff.clkToQ(outputEdge: e)
                let transitionLUT = ff.qTransition(outputEdge: e)
                let characterizedClockSlew = delayLUT.inputSlews.first ?? defaultInputSlew
                arr.set(e, delayLUT.lookup(inputSlew: characterizedClockSlew, outputLoad: load))
                slew.set(e, transitionLUT.lookup(inputSlew: characterizedClockSlew, outputLoad: load))
            }
            lateArr[dff.q] = arr; earlyArr[dff.q] = arr; lateSlew[dff.q] = slew
            launchDelayOf[dff.q] = max(arr.rise, arr.fall)
        }

        // Propagate through the combinational DAG.
        for (index, inst) in order {
            guard let ct = cellTimings[inst.cell.name] else { continue }
            let outNet = inst.net(inst.cell.output)
            let load = netLoad[outNet] ?? 0
            var late = EdgePair(rise: -.infinity, fall: -.infinity)
            var slew = EdgePair(rise: 0, fall: 0)
            var early = EdgePair(rise: .infinity, fall: .infinity)
            var preds: [TimingEdge: Pred] = [:]

            for pin in Set(inst.cell.devices.map(\.gate)) {
                let inNet = inst.net(pin)
                guard !rails.contains(inNet) else { continue }      // constant input carries no arc
                guard let arc = ct.arc(fromInput: pin),
                      let inLate = lateArr[inNet], let inSlew = lateSlew[inNet],
                      let inEarly = earlyArr[inNet] else { continue }
                for outEdge in [TimingEdge.rise, .fall] {
                    let inEdge = arc.sense == .positiveUnate ? outEdge : outEdge.inverted
                    let s = inSlew.at(inEdge)
                    let d = arc.delay(outputEdge: outEdge).lookup(inputSlew: s, outputLoad: load)
                    let candLate = inLate.at(inEdge) + d
                    if candLate > late.at(outEdge) {
                        late.set(outEdge, candLate)
                        slew.set(outEdge, arc.transition(outputEdge: outEdge).lookup(inputSlew: s, outputLoad: load))
                        preds[outEdge] = Pred(instanceIndex: index, inputPin: pin, inputNet: inNet,
                                              inputEdge: inEdge, stageDelay: d, outputSlew: slew.at(outEdge), load: load)
                    }
                    let candEarly = inEarly.at(inEdge) + d
                    if candEarly < early.at(outEdge) { early.set(outEdge, candEarly) }
                }
            }
            // A gate with only constant inputs produces no transition; leave it unresolved.
            if late.rise == -.infinity && late.fall == -.infinity { continue }
            lateArr[outNet] = late; lateSlew[outNet] = slew; earlyArr[outNet] = early
            latePred[outNet] = preds
        }

        // Capture endpoints (flip-flop D pins).
        var endpoints: [EndpointSlack] = []
        var worstEndpoint: (slack: Double, net: String)? = nil
        for dff in netlist.dffs {
            guard let late = lateArr[dff.d] else { continue }
            let dataLate = max(late.rise, late.fall)
            let dataEarly = (earlyArr[dff.d]).map { min($0.rise, $0.fall) } ?? dataLate
            let required = clockPeriod - ff.setupTime
            let setupSlack = required - dataLate
            let holdSlack = dataEarly - ff.holdTime
            endpoints.append(EndpointSlack(endpoint: dff.d, dataArrival: dataLate, required: required,
                                           setupSlack: setupSlack, earliestArrival: dataEarly, holdSlack: holdSlack))
            if worstEndpoint == nil || setupSlack < worstEndpoint!.slack {
                worstEndpoint = (setupSlack, dff.d)
            }
        }
        guard let worst = worstEndpoint else { throw STAError.noSequentialEndpoints }

        let worstSetup = endpoints.map(\.setupSlack).min() ?? 0
        let worstHold = endpoints.map(\.holdSlack).min() ?? 0
        let minPeriod = (endpoints.map { $0.dataArrival + ff.setupTime }.max() ?? 0)
        let critical = tracePath(endpoint: worst.net, order: order, lateArr: lateArr, lateSlew: lateSlew,
                                 latePred: latePred, launchDelayOf: launchDelayOf)

        return TimingReport(clockPeriod: clockPeriod, worstSetupSlack: worstSetup, worstHoldSlack: worstHold,
                            minPeriod: minPeriod, criticalPath: critical, endpoints: endpoints)
    }

    // MARK: - critical path trace

    private func tracePath(
        endpoint: String, order: [(Int, GateLevelNetlist.Instance)],
        lateArr: [String: EdgePair], lateSlew: [String: EdgePair],
        latePred: [String: [TimingEdge: Pred]], launchDelayOf: [String: Double]
    ) -> TimingPath {
        let instances = Dictionary(uniqueKeysWithValues: order.map { ($0.0, $0.1) })
        var stages: [TimingStage] = []
        var net = endpoint
        // Start at the worse edge of the endpoint.
        var edge: TimingEdge = (lateArr[net]?.rise ?? -.infinity) >= (lateArr[net]?.fall ?? -.infinity) ? .rise : .fall
        let arrival = lateArr[net].map { max($0.rise, $0.fall) } ?? 0
        while let pred = latePred[net]?[edge], let inst = instances[pred.instanceIndex] {
            stages.append(TimingStage(
                instance: inst.name, cell: inst.cell.name, inputPin: pred.inputPin, inputNet: pred.inputNet,
                outputNet: net, inputEdge: pred.inputEdge, outputEdge: edge,
                stageDelay: pred.stageDelay, outputSlew: pred.outputSlew, load: pred.load))
            net = pred.inputNet
            edge = pred.inputEdge
        }
        stages.reverse()
        let start = net
        let startEdge = stages.first?.inputEdge ?? edge
        let launchSlew = (lateSlew[start]).map { $0.at(startEdge) } ?? 0
        return TimingPath(startpoint: start, endpoint: endpoint, launchDelay: launchDelayOf[start] ?? 0,
                          launchSlew: launchSlew, startEdge: startEdge, stages: stages, arrival: arrival)
    }

    // MARK: - topological order

    private func topologicalOrder(
        _ netlist: SequentialNetlist, sources: Set<String>
    ) throws -> [(Int, GateLevelNetlist.Instance)] {
        var available = sources
        var result: [(Int, GateLevelNetlist.Instance)] = []
        var remaining = Array(netlist.combinational.enumerated())
        while !remaining.isEmpty {
            let ready = remaining.filter { _, inst in
                Set(inst.cell.devices.map(\.gate)).allSatisfy { available.contains(inst.net($0)) }
            }
            if ready.isEmpty { throw STAError.combinationalCycle }
            for (i, inst) in ready {
                result.append((i, inst))
                available.insert(inst.net(inst.cell.output))
            }
            let readyIndices = Set(ready.map(\.offset))
            remaining.removeAll { readyIndices.contains($0.offset) }
        }
        return result
    }
}
