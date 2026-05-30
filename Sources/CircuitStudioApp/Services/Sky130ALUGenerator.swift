import Foundation

/// Builds an N-bit ALU: `result = f(A, B)` chosen by a 2-bit `op` — ADD / SUB share one
/// ripple-carry adder (the subtrahend is conditionally inverted and the carry-in is the
/// "+1"), bitwise AND / OR are computed in parallel, and a per-bit function-select MUX
/// picks the active result. Built entirely from NAND2 / NOR2 / INV primitives, so it is a
/// pure DATA description the cell synthesizer can place & route — its truth table is
/// checked by the logic simulator and the geometry by real Sky130 DRC + Netgen LVS.
///
/// `op` encoding (op1, op0): 00 = ADD, 01 = SUB, 10 = AND, 11 = OR.
public struct Sky130ALUGenerator: Sendable {

    public let bits: Int

    public init(bits: Int = 4) { self.bits = bits }

    // MARK: - primitive instances

    private func nand(_ name: String, _ a: String, _ b: String, _ y: String) -> GateLevelNetlist.Instance {
        .init(name: name, cell: .nand(name: "nand2", inputs: ["A", "B"]), netMap: ["A": a, "B": b, "Y": y])
    }
    private func nor(_ name: String, _ a: String, _ b: String, _ y: String) -> GateLevelNetlist.Instance {
        .init(name: name, cell: .nor(name: "nor2", inputs: ["A", "B"]), netMap: ["A": a, "B": b, "Y": y])
    }
    private func inv(_ name: String, _ a: String, _ y: String) -> GateLevelNetlist.Instance {
        .init(name: name, cell: .inverter(name: "inv"), netMap: ["A": a, "Y": y])
    }

    // MARK: - composite combinational blocks (NAND2 only)

    /// y = a XOR b, 4 NAND2.
    private func xor(_ p: String, _ a: String, _ b: String, _ y: String) -> [GateLevelNetlist.Instance] {
        let n1 = "\(p)_n1", n2 = "\(p)_n2", n3 = "\(p)_n3"
        return [nand("\(p)_1", a, b, n1), nand("\(p)_2", a, n1, n2),
                nand("\(p)_3", b, n1, n3), nand("\(p)_4", n2, n3, y)]
    }

    /// (sum, cout) = a + b + cin, 9 NAND2 (two XORs + carry).
    private func fullAdder(_ p: String, _ a: String, _ b: String, _ cin: String,
                           _ sum: String, _ cout: String) -> [GateLevelNetlist.Instance] {
        let n1 = "\(p)_n1", n2 = "\(p)_n2", n3 = "\(p)_n3", x1 = "\(p)_x1"
        let m1 = "\(p)_m1", m2 = "\(p)_m2", m3 = "\(p)_m3"
        return [
            nand("\(p)_1", a, b, n1), nand("\(p)_2", a, n1, n2), nand("\(p)_3", b, n1, n3),
            nand("\(p)_4", n2, n3, x1), nand("\(p)_5", x1, cin, m1), nand("\(p)_6", x1, m1, m2),
            nand("\(p)_7", cin, m1, m3), nand("\(p)_8", m2, m3, sum), nand("\(p)_9", n1, m1, cout),
        ]
    }

    /// y = sel ? b : a = (a & ~sel) | (b & sel), 3 NAND2 (caller supplies ~sel as `nsel`).
    private func mux2(_ p: String, a: String, b: String, sel: String, nsel: String, y: String) -> [GateLevelNetlist.Instance] {
        let t0 = "\(p)_t0", t1 = "\(p)_t1"
        return [nand("\(p)_0", a, nsel, t0), nand("\(p)_1", b, sel, t1), nand("\(p)_2", t0, t1, y)]
    }

    // MARK: - assembly

    private func bus(_ name: String) -> [String] { (0..<bits).map { "\(name)\($0)" } }

    /// The flat gate-level netlist (inputs A[], B[], op0, op1; outputs result[]).
    public func gateLevelNetlist(name: String = "alu") -> GateLevelNetlist {
        let a = bus("a"), b = bus("b")
        let op0 = "op0", op1 = "op1"
        var insts: [GateLevelNetlist.Instance] = [
            inv("inv_op0", op0, "op0b"),   // shared inverted selects for the MUXes
            inv("inv_op1", op1, "op1b"),
        ]
        var result: [String] = []
        var carry = op0   // adder carry-in: 0 for ADD, 1 for SUB (the two's-complement "+1")
        for i in 0..<bits {
            // Conditionally invert B for subtract: bx = b XOR op0.
            insts += xor("bx\(i)", b[i], op0, "bx\(i)_y")
            // Arithmetic: a + bx + carry.
            let cout = i == bits - 1 ? "alu_cout" : "c\(i + 1)"
            insts += fullAdder("fa\(i)", a[i], "bx\(i)_y", carry, "sum\(i)", cout)
            carry = cout
            // Logic: AND = INV(NAND), OR = INV(NOR).
            insts.append(nand("nand_and\(i)", a[i], b[i], "and\(i)_n"))
            insts.append(inv("and\(i)", "and\(i)_n", "and\(i)_y"))
            insts.append(nor("nor_or\(i)", a[i], b[i], "or\(i)_n"))
            insts.append(inv("or\(i)", "or\(i)_n", "or\(i)_y"))
            // Function select: logic = op0 ? or : and; result = op1 ? logic : sum.
            insts += mux2("lm\(i)", a: "and\(i)_y", b: "or\(i)_y", sel: op0, nsel: "op0b", y: "lm\(i)_y")
            insts += mux2("rm\(i)", a: "sum\(i)", b: "lm\(i)_y", sel: op1, nsel: "op1b", y: "r\(i)")
            result.append("r\(i)")
        }
        return GateLevelNetlist(name: name, instances: insts, inputs: a + b + [op0, op1], outputs: result)
    }

    /// A purely-combinational sequential model (no registers) for truth-table simulation.
    public func combinationalModel(name: String = "alu") -> SequentialNetlist {
        let gl = gateLevelNetlist(name: name)
        return SequentialNetlist(name: name, combinational: gl.instances, dffs: [],
                                 inputs: gl.inputs, outputs: gl.outputs)
    }
}
