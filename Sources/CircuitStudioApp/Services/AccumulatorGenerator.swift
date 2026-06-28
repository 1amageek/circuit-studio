import Foundation

/// Builds an N-bit clocked accumulator: ACC <- ACC + IN on every rising clock edge.
/// The topology is process-independent; the injected cell library selects the concrete
/// standard-cell definitions consumed by layout and signoff.
public struct AccumulatorGenerator: Sendable {
    public let bits: Int
    private let cellLibrary: CMOSGateLibrary
    private let dff: DFFGenerator

    public init(bits: Int = 4, cellLibrary: CMOSGateLibrary = .bundledDefault) {
        self.bits = bits
        self.cellLibrary = cellLibrary
        self.dff = DFFGenerator(cellLibrary: cellLibrary)
    }

    private func nand(_ name: String, _ a: String, _ b: String, _ y: String) -> GateLevelNetlist.Instance {
        .init(name: name, cell: cellLibrary.nand(name: "nand2", inputs: ["A", "B"]), netMap: ["A": a, "B": b, "Y": y])
    }

    private func fullAdder(
        _ p: String,
        a: String,
        b: String,
        cin: String,
        sum: String,
        cout: String
    ) -> [GateLevelNetlist.Instance] {
        let n1 = "\(p)_n1", n2 = "\(p)_n2", n3 = "\(p)_n3", x1 = "\(p)_x1"
        let m1 = "\(p)_m1", m2 = "\(p)_m2", m3 = "\(p)_m3"
        var gates: [GateLevelNetlist.Instance] = []
        gates.append(nand("\(p)_g1", a, b, n1))
        gates.append(nand("\(p)_g2", a, n1, n2))
        gates.append(nand("\(p)_g3", b, n1, n3))
        gates.append(nand("\(p)_g4", n2, n3, x1))
        gates.append(nand("\(p)_g5", x1, cin, m1))
        gates.append(nand("\(p)_g6", x1, m1, m2))
        gates.append(nand("\(p)_g7", cin, m1, m3))
        gates.append(nand("\(p)_g8", m2, m3, sum))
        gates.append(nand("\(p)_g9", n1, m1, cout))
        return gates
    }

    private func adder(acc: [String], inp: [String], sum: [String], vgnd: String) -> [GateLevelNetlist.Instance] {
        var gates: [GateLevelNetlist.Instance] = []
        var carry = vgnd
        for i in 0..<bits {
            let cout = i == bits - 1 ? "acc_cout" : "acc_c\(i + 1)"
            gates += fullAdder("fa\(i)", a: acc[i], b: inp[i], cin: carry, sum: sum[i], cout: cout)
            carry = cout
        }
        return gates
    }

    private func bus(_ name: String) -> [String] {
        (0..<bits).map { "\(name)\($0)" }
    }

    public func sequentialNetlist(name: String = "acc", clock: String = "CLK") -> SequentialNetlist {
        let acc = bus("acc"), inp = bus("in"), sum = bus("sum")
        let comb = adder(acc: acc, inp: inp, sum: sum, vgnd: "VGND")
        let ffs = (0..<bits).map { SequentialNetlist.DFF(name: "ff\($0)", d: sum[$0], clk: clock, q: acc[$0]) }
        return SequentialNetlist(
            name: name,
            combinational: comb,
            dffs: ffs,
            inputs: inp,
            outputs: acc,
            clock: clock
        )
    }

    public func gateLevelNetlist(name: String = "acc", clock: String = "CLK") -> GateLevelNetlist {
        let acc = bus("acc"), inp = bus("in"), sum = bus("sum")
        var insts = adder(acc: acc, inp: inp, sum: sum, vgnd: "VGND")
        for i in 0..<bits {
            insts += dff.instances(prefix: "ff\(i)", d: sum[i], clk: clock, q: acc[i])
        }
        return GateLevelNetlist(name: name, instances: insts, inputs: inp + [clock], outputs: acc)
    }
}
