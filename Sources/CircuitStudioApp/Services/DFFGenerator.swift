import Foundation

/// Builds a positive-edge-triggered D flip-flop as a gate-level netlist using NAND2 and
/// INV primitives. The physical implementation is selected later by the injected cell
/// library and layout profile, so this type owns topology rather than process data.
public struct DFFGenerator: Sendable {
    private let cellLibrary: CMOSGateLibrary

    public init(cellLibrary: CMOSGateLibrary) {
        self.cellLibrary = cellLibrary
    }

    public init() throws {
        self.init(cellLibrary: try CMOSGateLibrary.loadBundledDefault())
    }

    private func latch(prefix p: String, d: String, en: String, q: String) -> [GateLevelNetlist.Instance] {
        let db = "\(p)_db", nd = "\(p)_nd", ndb = "\(p)_ndb", qb = "\(p)_qb"
        let inv = cellLibrary.inverter(name: "inv")
        let nand = cellLibrary.nand(name: "nand2", inputs: ["A", "B"])
        var out: [GateLevelNetlist.Instance] = []
        out.append(GateLevelNetlist.Instance(name: "\(p)_inv", cell: inv, netMap: ["A": d, "Y": db]))
        out.append(GateLevelNetlist.Instance(name: "\(p)_nd", cell: nand, netMap: ["A": d, "B": en, "Y": nd]))
        out.append(GateLevelNetlist.Instance(name: "\(p)_ndb", cell: nand, netMap: ["A": db, "B": en, "Y": ndb]))
        out.append(GateLevelNetlist.Instance(name: "\(p)_q", cell: nand, netMap: ["A": nd, "B": qb, "Y": q]))
        out.append(GateLevelNetlist.Instance(name: "\(p)_qb", cell: nand, netMap: ["A": ndb, "B": q, "Y": qb]))
        return out
    }

    public func netlist(
        name: String = "dff",
        d: String = "D",
        clk: String = "CLK",
        q: String = "Q"
    ) -> GateLevelNetlist {
        GateLevelNetlist(
            name: name,
            instances: instances(prefix: name, d: d, clk: clk, q: q),
            inputs: [d, clk],
            output: q
        )
    }

    public func instances(prefix: String, d: String, clk: String, q: String) -> [GateLevelNetlist.Instance] {
        let clkb = "\(prefix)_clkb", m = "\(prefix)_m"
        var insts: [GateLevelNetlist.Instance] = [
            .init(name: "\(prefix)_clkinv", cell: cellLibrary.inverter(name: "inv"), netMap: ["A": clk, "Y": clkb]),
        ]
        insts += latch(prefix: "\(prefix)_m", d: d, en: clkb, q: m)
        insts += latch(prefix: "\(prefix)_s", d: m, en: clk, q: q)
        return insts
    }
}
