import Foundation
import Testing
@testable import CircuitStudioApp

/// Tool-independent tests for the cycle-based gate-level logic simulator — it evaluates
/// static-CMOS cells from their transistor topology and clocks D flip-flops, the
/// functional-verification engine for sequential designs.
@Suite("Gate-level logic simulator")
struct GateLevelLogicSimulatorTests {

    private let sim = GateLevelLogicSimulator()

    @Test("Static-CMOS cells evaluate to their boolean function")
    func cellsEvaluateCorrectly() throws {
        let nand2 = try CMOSGateNetlist.nand(name: "nand2", inputs: ["A", "B"])
        let nor2 = try CMOSGateNetlist.nor(name: "nor2", inputs: ["A", "B"])
        let inv = try CMOSGateNetlist.inverter(name: "inv")
        for a in [false, true] {
            for b in [false, true] {
                let g: (String) -> Bool = { $0 == "A" ? a : b }
                #expect(sim.cellOutput(nand2, gateValue: g) == !(a && b))
                #expect(sim.cellOutput(nor2, gateValue: g) == !(a || b))
            }
            #expect(sim.cellOutput(inv, gateValue: { _ in a }) == !a)
        }
    }

    @Test("A mapped Boolean circuit simulates to its truth table")
    func combinationalTruthTable() throws {
        // Y = (a AND b) OR c, synthesized to NAND/NOR/INV by the mapper.
        let gl = try BooleanGateMapper().map(.or(.and(.input("a"), .input("b")), .input("c")), name: "aoi", output: "y")
        let seq = SequentialNetlist(name: "aoi", combinational: gl.instances, dffs: [],
                                    inputs: gl.inputs, outputs: ["y"])
        for combo in 0..<8 {
            let a = combo & 1 == 1, b = (combo >> 1) & 1 == 1, c = (combo >> 2) & 1 == 1
            let trace = try sim.simulate(seq, cycles: [["a": a, "b": b, "c": c]])
            #expect(trace[0]["y"] == ((a && b) || c), "a=\(a) b=\(b) c=\(c)")
        }
    }

    @Test("A D flip-flop delays its input by one cycle")
    func dffDelaysByOneCycle() throws {
        let seq = SequentialNetlist(name: "ff", combinational: [],
                                    dffs: [.init(name: "ff0", d: "d", clk: "clk", q: "q")],
                                    inputs: ["d"], outputs: ["q"])
        let d = [true, false, true, true, false]
        let trace = try sim.simulate(seq, cycles: d.map { ["d": $0] })
        // q[0] = 0 (initial), q[i] = d[i-1].
        let q = trace.map { $0["q"] ?? false }
        #expect(q == [false, true, false, true, true])
    }

    @Test("M2 functional: a 4-bit clocked accumulator adds its input every cycle")
    func accumulatorAccumulates() throws {
        let seq = try AccumulatorGenerator(bits: 4).sequentialNetlist(name: "acc")
        func run(addend: Int, cycles n: Int) throws -> [Int] {
            let vec = (0..<4).reduce(into: [String: Bool]()) { $0["in\($1)"] = (addend >> $1) & 1 == 1 }
            let trace = try sim.simulate(seq, cycles: Array(repeating: vec, count: n))
            return trace.map { t in (0..<4).reduce(0) { $0 | ((t["acc\($1)"] ?? false) ? (1 << $1) : 0) } }
        }
        let plusOne = try run(addend: 1, cycles: 6)
        let plusThree = try run(addend: 3, cycles: 7)
        #expect(plusOne == [0, 1, 2, 3, 4, 5])
        #expect(plusThree == [0, 3, 6, 9, 12, 15, 2])   // mod 16
    }

    @Test("Gate-level netlist decoding rejects missing outputs")
    func gateLevelNetlistDecodingRejectsMissingOutputs() {
        let json = Data("""
        {
          "name": "invalid",
          "instances": [],
          "inputs": ["a"],
          "outputs": [],
          "vpwr": "VPWR",
          "vgnd": "VGND"
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(GateLevelNetlist.self, from: json)
        }
    }

    @Test("M3 functional: the 4-bit ALU matches its truth table for ADD/SUB/AND/OR")
    func aluTruthTable() throws {
        let seq = try ALUGenerator(bits: 4).combinationalModel()
        for av in 0..<16 {
            for bv in 0..<16 {
                for op in 0..<4 {
                    var vec: [String: Bool] = ["op0": op & 1 == 1, "op1": (op >> 1) & 1 == 1]
                    for i in 0..<4 { vec["a\(i)"] = (av >> i) & 1 == 1; vec["b\(i)"] = (bv >> i) & 1 == 1 }
                    let t = try sim.simulate(seq, cycles: [vec])[0]
                    let r = (0..<4).reduce(0) { $0 | ((t["r\($1)"] ?? false) ? (1 << $1) : 0) }
                    let want: Int
                    switch op {
                    case 0: want = (av + bv) & 15        // ADD
                    case 1: want = (av - bv) & 15        // SUB (two's complement)
                    case 2: want = av & bv               // AND
                    default: want = av | bv              // OR
                    }
                    #expect(r == want, "op=\(op) a=\(av) b=\(bv): got \(r), want \(want)")
                }
            }
        }
    }

    @Test("A toggle flip-flop (q fed back through an inverter) alternates each cycle")
    func toggleFlipFlop() throws {
        let seq = SequentialNetlist(
            name: "toggle",
            combinational: [.init(name: "g0", cell: try .inverter(name: "inv"), netMap: ["A": "q", "Y": "dn"])],
            dffs: [.init(name: "ff0", d: "dn", clk: "clk", q: "q")],
            inputs: [], outputs: ["q"])
        let trace = try sim.simulate(seq, cycles: Array(repeating: [:], count: 6))
        #expect(trace.map { $0["q"] ?? false } == [false, true, false, true, false, true])
    }
}
