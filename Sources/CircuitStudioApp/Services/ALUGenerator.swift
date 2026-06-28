import Foundation

/// Builds an N-bit ALU: result = f(A, B), selected by a 2-bit op. ADD and SUB share a
/// ripple-carry adder, bitwise AND and OR are computed in parallel, and a per-bit
/// function-select mux picks the active result.
public struct ALUGenerator: Sendable {
    public let bits: Int
    private let cellLibrary: CMOSGateLibrary

    public init(bits: Int = 4, cellLibrary: CMOSGateLibrary = .bundledDefault) {
        self.bits = bits
        self.cellLibrary = cellLibrary
    }

    private func nand(_ name: String, _ a: String, _ b: String, _ y: String) -> GateLevelNetlist.Instance {
        .init(name: name, cell: cellLibrary.nand(name: "nand2", inputs: ["A", "B"]), netMap: ["A": a, "B": b, "Y": y])
    }

    private func nor(_ name: String, _ a: String, _ b: String, _ y: String) -> GateLevelNetlist.Instance {
        .init(name: name, cell: cellLibrary.nor(name: "nor2", inputs: ["A", "B"]), netMap: ["A": a, "B": b, "Y": y])
    }

    private func inv(_ name: String, _ a: String, _ y: String) -> GateLevelNetlist.Instance {
        .init(name: name, cell: cellLibrary.inverter(name: "inv"), netMap: ["A": a, "Y": y])
    }

    private func xor(_ p: String, _ a: String, _ b: String, _ y: String) -> [GateLevelNetlist.Instance] {
        let n1 = "\(p)_n1", n2 = "\(p)_n2", n3 = "\(p)_n3"
        return [
            nand("\(p)_1", a, b, n1),
            nand("\(p)_2", a, n1, n2),
            nand("\(p)_3", b, n1, n3),
            nand("\(p)_4", n2, n3, y),
        ]
    }

    private func fullAdder(
        _ p: String,
        _ a: String,
        _ b: String,
        _ cin: String,
        _ sum: String,
        _ cout: String
    ) -> [GateLevelNetlist.Instance] {
        let n1 = "\(p)_n1", n2 = "\(p)_n2", n3 = "\(p)_n3", x1 = "\(p)_x1"
        let m1 = "\(p)_m1", m2 = "\(p)_m2", m3 = "\(p)_m3"
        return [
            nand("\(p)_1", a, b, n1),
            nand("\(p)_2", a, n1, n2),
            nand("\(p)_3", b, n1, n3),
            nand("\(p)_4", n2, n3, x1),
            nand("\(p)_5", x1, cin, m1),
            nand("\(p)_6", x1, m1, m2),
            nand("\(p)_7", cin, m1, m3),
            nand("\(p)_8", m2, m3, sum),
            nand("\(p)_9", n1, m1, cout),
        ]
    }

    private func mux2(
        _ p: String,
        a: String,
        b: String,
        sel: String,
        nsel: String,
        y: String
    ) -> [GateLevelNetlist.Instance] {
        let t0 = "\(p)_t0", t1 = "\(p)_t1"
        return [
            nand("\(p)_0", a, nsel, t0),
            nand("\(p)_1", b, sel, t1),
            nand("\(p)_2", t0, t1, y),
        ]
    }

    private func bus(_ name: String) -> [String] {
        (0..<bits).map { "\(name)\($0)" }
    }

    public func gateLevelNetlist(name: String = "alu") -> GateLevelNetlist {
        let a = bus("a"), b = bus("b")
        let op0 = "op0", op1 = "op1"
        var insts: [GateLevelNetlist.Instance] = [
            inv("inv_op0", op0, "op0b"),
            inv("inv_op1", op1, "op1b"),
        ]
        var result: [String] = []
        var carry = op0
        for i in 0..<bits {
            insts += xor("bx\(i)", b[i], op0, "bx\(i)_y")
            let cout = i == bits - 1 ? "alu_cout" : "c\(i + 1)"
            insts += fullAdder("fa\(i)", a[i], "bx\(i)_y", carry, "sum\(i)", cout)
            carry = cout
            insts.append(nand("nand_and\(i)", a[i], b[i], "and\(i)_n"))
            insts.append(inv("and\(i)", "and\(i)_n", "and\(i)_y"))
            insts.append(nor("nor_or\(i)", a[i], b[i], "or\(i)_n"))
            insts.append(inv("or\(i)", "or\(i)_n", "or\(i)_y"))
            insts += mux2("lm\(i)", a: "and\(i)_y", b: "or\(i)_y", sel: op0, nsel: "op0b", y: "lm\(i)_y")
            insts += mux2("rm\(i)", a: "sum\(i)", b: "lm\(i)_y", sel: op1, nsel: "op1b", y: "r\(i)")
            result.append("r\(i)")
        }
        return GateLevelNetlist(name: name, instances: insts, inputs: a + b + [op0, op1], outputs: result)
    }

    public func combinationalModel(name: String = "alu") -> SequentialNetlist {
        let gateLevelNetlist = gateLevelNetlist(name: name)
        return SequentialNetlist(
            name: name,
            combinational: gateLevelNetlist.instances,
            dffs: [],
            inputs: gateLevelNetlist.inputs,
            outputs: gateLevelNetlist.outputs
        )
    }
}
