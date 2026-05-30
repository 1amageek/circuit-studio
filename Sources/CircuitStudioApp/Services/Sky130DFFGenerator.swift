import Foundation

/// Builds a positive-edge-triggered D flip-flop as a GATE-LEVEL netlist (NAND2 + INV) —
/// the system then places & routes it automatically (the latch feedback and clock fanout
/// are handled by the generalized router). A master/slave pair of NAND gated D-latches
/// with a clock inverter; Q takes D on each rising clk edge.
///
///   clkb = INV(clk)
///   master latch (transparent clk=0):  m  = D latched when clkb=1
///   slave  latch (transparent clk=1):  Q  = m latched when clk =1
public struct Sky130DFFGenerator: Sendable {

    public init() {}

    /// A gated D-latch built from NAND2s + an inverter, transparent when `en`=1.
    /// Returns its instances (named under `p`) and the latch output net.
    private func latch(prefix p: String, d: String, en: String, q: String) -> [GateLevelNetlist.Instance] {
        let db = "\(p)_db", nd = "\(p)_nd", ndb = "\(p)_ndb", qb = "\(p)_qb"
        let inv: CMOSGateNetlist = .inverter(name: "inv")
        let nand: CMOSGateNetlist = .nand(name: "nand2", inputs: ["A", "B"])
        var out: [GateLevelNetlist.Instance] = []
        out.append(GateLevelNetlist.Instance(name: "\(p)_inv", cell: inv, netMap: ["A": d, "Y": db]))
        out.append(GateLevelNetlist.Instance(name: "\(p)_nd", cell: nand, netMap: ["A": d, "B": en, "Y": nd]))
        out.append(GateLevelNetlist.Instance(name: "\(p)_ndb", cell: nand, netMap: ["A": db, "B": en, "Y": ndb]))
        out.append(GateLevelNetlist.Instance(name: "\(p)_q", cell: nand, netMap: ["A": nd, "B": qb, "Y": q]))
        out.append(GateLevelNetlist.Instance(name: "\(p)_qb", cell: nand, netMap: ["A": ndb, "B": q, "Y": qb]))
        return out
    }

    /// The gate-level DFF netlist (inputs D, clk; output Q).
    public func netlist(name: String = "dff", d: String = "D", clk: String = "CLK",
                        q: String = "Q") -> GateLevelNetlist {
        var insts: [GateLevelNetlist.Instance] = [
            .init(name: "clkinv", cell: .inverter(name: "inv"), netMap: ["A": clk, "Y": "clkb"]),
        ]
        insts += latch(prefix: "m", d: d, en: "clkb", q: "m")   // master, transparent clk=0
        insts += latch(prefix: "s", d: "m", en: clk, q: q)      // slave, transparent clk=1
        return GateLevelNetlist(name: name, instances: insts, inputs: [d, clk], output: q)
    }
}
