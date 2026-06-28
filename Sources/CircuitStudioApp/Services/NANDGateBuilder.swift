import Foundation

/// Accumulates a combinational gate-level netlist from NAND2 / NOR2 / INV primitives,
/// auto-naming instances and internal nodes — the construction library larger datapaths
/// (the CPU core) are built with. Callers name only the nets that carry meaning (inputs,
/// outputs, register d/q); temporaries are private `_n…` nodes that never collide with
/// caller nets. Instance names are opaque (`g…`); LVS matches by topology, not by name.
public final class NANDGateBuilder {

    public private(set) var instances: [GateLevelNetlist.Instance] = []
    private var gateCount = 0
    private var nodeCount = 0
    private let cellLibrary: CMOSGateLibrary

    public init(cellLibrary: CMOSGateLibrary = .bundledDefault) {
        self.cellLibrary = cellLibrary
    }

    private func gateName() -> String { defer { gateCount += 1 }; return "g\(gateCount)" }

    /// A fresh unique internal net (prefixed `_` so it never collides with a caller net).
    public func node(_ hint: String = "n") -> String { defer { nodeCount += 1 }; return "_\(hint)\(nodeCount)" }

    // MARK: - primitives

    public func nand(_ a: String, _ b: String, _ y: String) {
        instances.append(.init(
            name: gateName(),
            cell: cellLibrary.nand(name: "nand2", inputs: ["A", "B"]),
            netMap: ["A": a, "B": b, "Y": y]
        ))
    }
    public func nor(_ a: String, _ b: String, _ y: String) {
        instances.append(.init(
            name: gateName(),
            cell: cellLibrary.nor(name: "nor2", inputs: ["A", "B"]),
            netMap: ["A": a, "B": b, "Y": y]
        ))
    }
    public func inv(_ a: String, _ y: String) {
        instances.append(.init(
            name: gateName(),
            cell: cellLibrary.inverter(name: "inv"),
            netMap: ["A": a, "Y": y]
        ))
    }

    // MARK: - composites

    public func and2(_ a: String, _ b: String, _ y: String) { let t = node("and"); nand(a, b, t); inv(t, y) }
    public func or2(_ a: String, _ b: String, _ y: String) { let t = node("or"); nor(a, b, t); inv(t, y) }

    /// y = AND of all inputs (left-folded and2; a single input is buffered).
    public func andN(_ ins: [String], _ y: String) {
        precondition(!ins.isEmpty, "andN needs at least one input")
        if ins.count == 1 { let t = node("buf"); inv(ins[0], t); inv(t, y); return }
        var acc = ins[0]
        for i in 1..<ins.count {
            let out = i == ins.count - 1 ? y : node("a")
            and2(acc, ins[i], out)
            acc = out
        }
    }

    /// y = a XOR b, 4 NAND2.
    public func xor(_ a: String, _ b: String, _ y: String) {
        let n1 = node("x"), n2 = node("x"), n3 = node("x")
        nand(a, b, n1); nand(a, n1, n2); nand(b, n1, n3); nand(n2, n3, y)
    }

    /// y = sel ? b : a = (a & ~sel) | (b & sel), 3 NAND2 (caller supplies ~sel).
    public func mux2(a: String, b: String, sel: String, nsel: String, _ y: String) {
        let t0 = node("m"), t1 = node("m")
        nand(a, nsel, t0); nand(b, sel, t1); nand(t0, t1, y)
    }

    /// (sum, cout) = a + b + cin, 9 NAND2.
    public func fullAdder(_ a: String, _ b: String, _ cin: String, sum: String, cout: String) {
        let n1 = node("fa"), n2 = node("fa"), n3 = node("fa"), x1 = node("fa")
        let m1 = node("fa"), m2 = node("fa"), m3 = node("fa")
        nand(a, b, n1); nand(a, n1, n2); nand(b, n1, n3); nand(n2, n3, x1)
        nand(x1, cin, m1); nand(x1, m1, m2); nand(cin, m1, m3); nand(m2, m3, sum); nand(n1, m1, cout)
    }
}
