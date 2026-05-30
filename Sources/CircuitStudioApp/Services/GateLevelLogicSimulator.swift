import Foundation

/// A cycle-based gate-level logic simulator: it evaluates the combinational cells and
/// clocks the D flip-flops of a `SequentialNetlist`, producing an output trace. Cell
/// outputs are derived from the TRANSISTOR topology (the NMOS pull-down conducts ->
/// output is 0), so any static-CMOS cell is evaluated correctly — the same netlist that
/// is placed & routed is the one that is functionally checked against a golden trace.
public struct GateLevelLogicSimulator: Sendable {

    public enum SimError: Error, LocalizedError, Equatable {
        case combinationalLoop
        public var errorDescription: String? {
            switch self {
            case .combinationalLoop: return "Combinational logic did not settle (a loop without a flip-flop)."
            }
        }
    }

    public init() {}

    /// The boolean output of a static-CMOS cell given a value for each gate net.
    /// Output is 0 iff the NMOS network connects the output to VGND through on devices.
    public func cellOutput(_ cell: CMOSGateNetlist, gateValue: (String) -> Bool) -> Bool {
        var parent: [String: String] = [:]
        func root(_ x: String) -> String {
            var r = x
            while let p = parent[r], p != r { r = p }
            var n = x
            while let p = parent[n], p != r { parent[n] = r; n = p }
            return r
        }
        func union(_ a: String, _ b: String) { parent[root(a)] = root(b) }
        for net in Set(cell.devices.flatMap { [$0.source, $0.drain] }).union([cell.output, cell.vgnd]) {
            parent[net] = net
        }
        for d in cell.nmos where gateValue(d.gate) { union(d.source, d.drain) }
        return root(cell.output) != root(cell.vgnd)
    }

    /// Simulate `netlist` over the given per-cycle primary-input vectors. DFF outputs hold
    /// state across cycles; each cycle settles the combinational logic with the current
    /// state, samples the outputs, then clocks (q <- d). Returns the output net values
    /// per cycle.
    public func simulate(_ netlist: SequentialNetlist, cycles: [[String: Bool]]) throws -> [[String: Bool]] {
        var state: [String: Bool] = [:]                 // dff name -> stored q
        for dff in netlist.dffs { state[dff.name] = false }

        var trace: [[String: Bool]] = []
        for inputVector in cycles {
            var net: [String: Bool] = [netlist.vpwr: true, netlist.vgnd: false]
            for (k, v) in inputVector { net[k] = v }
            for dff in netlist.dffs { net[dff.q] = state[dff.name] }   // present state

            try settle(netlist.combinational, into: &net)

            var out: [String: Bool] = [:]
            for o in netlist.outputs { out[o] = net[o] ?? false }
            trace.append(out)

            var next = state
            for dff in netlist.dffs { next[dff.name] = net[dff.d] ?? false }   // q <- d on the edge
            state = next
        }
        return trace
    }

    /// Iterate the combinational cells to a fixed point (acyclic, since feedback runs
    /// through DFFs). Throws if it fails to settle — a combinational loop, never silent.
    private func settle(_ instances: [GateLevelNetlist.Instance], into net: inout [String: Bool]) throws {
        for _ in 0...(instances.count + 1) {
            var changed = false
            for inst in instances {
                let value = cellOutput(inst.cell) { local in net[inst.net(local)] ?? false }
                let outNet = inst.net(inst.cell.output)
                if net[outNet] != value { net[outNet] = value; changed = true }
            }
            if !changed { return }
        }
        throw SimError.combinationalLoop
    }
}
