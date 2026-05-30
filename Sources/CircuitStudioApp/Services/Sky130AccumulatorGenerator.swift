import Foundation

/// Builds an N-bit clocked accumulator: ACC <- ACC + IN on every rising clock edge. The
/// datapath is an N-bit ripple-carry adder (built from NAND2 gates — XOR via NANDs) whose
/// sum feeds an N-bit register of D flip-flops, fed back as one adder operand. This is the
/// first SEQUENTIAL datapath: its function is checked over time by the logic simulator,
/// and (with the DFFs expanded to gates) it is placed & routed for DRC/LVS.
public struct Sky130AccumulatorGenerator: Sendable {

    public let bits: Int
    private let dff = Sky130DFFGenerator()

    public init(bits: Int = 4) { self.bits = bits }

    private func nand(_ name: String, _ a: String, _ b: String, _ y: String) -> GateLevelNetlist.Instance {
        .init(name: name, cell: .nand(name: "nand2", inputs: ["A", "B"]), netMap: ["A": a, "B": b, "Y": y])
    }

    /// A full adder (a + b + cin) -> (sum, cout) from 9 NAND2 gates (two XORs + carry).
    private func fullAdder(_ p: String, a: String, b: String, cin: String, sum: String, cout: String) -> [GateLevelNetlist.Instance] {
        let n1 = "\(p)_n1", n2 = "\(p)_n2", n3 = "\(p)_n3", x1 = "\(p)_x1"
        let m1 = "\(p)_m1", m2 = "\(p)_m2", m3 = "\(p)_m3"
        var g: [GateLevelNetlist.Instance] = []
        g.append(nand("\(p)_g1", a, b, n1))           // n1 = ~(a&b)
        g.append(nand("\(p)_g2", a, n1, n2))
        g.append(nand("\(p)_g3", b, n1, n3))
        g.append(nand("\(p)_g4", n2, n3, x1))         // x1 = a ^ b
        g.append(nand("\(p)_g5", x1, cin, m1))        // m1 = ~(x1&cin)
        g.append(nand("\(p)_g6", x1, m1, m2))
        g.append(nand("\(p)_g7", cin, m1, m3))
        g.append(nand("\(p)_g8", m2, m3, sum))        // sum = x1 ^ cin
        g.append(nand("\(p)_g9", n1, m1, cout))       // cout = ~(~(a&b) & ~(x1&cin)) = a&b | cin&x1
        return g
    }

    /// The ripple-carry adder ACC + IN -> sum[], plus the carry nets (cin0 = VGND = 0).
    private func adder(acc: [String], inp: [String], sum: [String], vgnd: String) -> [GateLevelNetlist.Instance] {
        var g: [GateLevelNetlist.Instance] = []
        var carry = vgnd
        for i in 0..<bits {
            let cout = i == bits - 1 ? "acc_cout" : "acc_c\(i + 1)"
            g += fullAdder("fa\(i)", a: acc[i], b: inp[i], cin: carry, sum: sum[i], cout: cout)
            carry = cout
        }
        return g
    }

    private func bus(_ name: String) -> [String] { (0..<bits).map { "\(name)\($0)" } }

    /// The sequential model (adder cells + DFF primitives) for cycle simulation.
    public func sequentialNetlist(name: String = "acc", clock: String = "CLK") -> SequentialNetlist {
        let acc = bus("acc"), inp = bus("in"), sum = bus("sum")
        let comb = adder(acc: acc, inp: inp, sum: sum, vgnd: "VGND")
        let ffs = (0..<bits).map { SequentialNetlist.DFF(name: "ff\($0)", d: sum[$0], clk: clock, q: acc[$0]) }
        return SequentialNetlist(name: name, combinational: comb, dffs: ffs,
                                 inputs: inp, outputs: acc, clock: clock)
    }

    /// The flat gate-level netlist (adder cells + DFFs expanded to gates) for layout.
    public func gateLevelNetlist(name: String = "acc", clock: String = "CLK") -> GateLevelNetlist {
        let acc = bus("acc"), inp = bus("in"), sum = bus("sum")
        var insts = adder(acc: acc, inp: inp, sum: sum, vgnd: "VGND")
        for i in 0..<bits {
            insts += dff.instances(prefix: "ff\(i)", d: sum[i], clk: clock, q: acc[i])
        }
        return GateLevelNetlist(name: name, instances: insts, inputs: inp + [clock], outputs: acc)
    }
}
