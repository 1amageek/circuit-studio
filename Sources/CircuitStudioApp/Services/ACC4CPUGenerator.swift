import Foundation

/// Generates the ACC-4 CPU core as a structural gate-level netlist — a single-cycle 4-bit
/// accumulator machine implementing the 8-instruction ISA from NAND2/NOR2/INV gates plus
/// ACC and PC flip-flop registers. Instruction and data memory are EXTERNAL (a standard
/// Harvard CPU-core boundary): the core takes the decoded instruction (opcode + operand)
/// and a data-read bus as inputs, and drives ACC, PC, the zero flag and a write-enable.
/// The same netlist is logic-simulated against the reference model and placed & routed for
/// DRC/LVS — one description, both checks.
///
/// Datapath per cycle: decode opcode -> one-hot; ALU = ACC +/- mem_rdata (shared adder,
/// subtrahend conditionally inverted, carry-in = isSUB); ACC_next = a one-hot mux over
/// {immediate, mem_rdata, ALU} gated by a write-enable (else hold); PC_next = jump-target
/// (JMP, or JZ when ACC == 0) else PC + 1.
public struct ACC4CPUGenerator: Sendable {

    public let bits = 4
    private let cellLibrary: CMOSGateLibrary

    public init(cellLibrary: CMOSGateLibrary = .bundledDefault) {
        self.cellLibrary = cellLibrary
    }

    // Net-name conventions (also the LVS port names).
    public var operandInputs: [String] { (0..<bits).map { "d\($0)" } }     // instruction operand [3:0]
    public var opcodeInputs: [String] { ["op0", "op1", "op2"] }            // instruction opcode [6:4]
    public var memReadInputs: [String] { (0..<bits).map { "rd\($0)" } }    // external data-read bus
    public var accOutputs: [String] { (0..<bits).map { "acc\($0)" } }      // accumulator (also write data)
    public var pcOutputs: [String] { (0..<bits).map { "pc\($0)" } }        // program counter
    public var inputs: [String] { operandInputs + opcodeInputs + memReadInputs }
    public var outputs: [String] { accOutputs + pcOutputs + ["zero", "we"] }

    /// DFF instance names holding each ACC / PC bit — the testbench reads present register
    /// state (the program counter to fetch, the accumulator to store) by these names.
    public var accRegisterNames: [String] { (0..<bits).map { "accff\($0)" } }
    public var pcRegisterNames: [String] { (0..<bits).map { "pcff\($0)" } }

    /// DFF register descriptors (name, d, clk, q) for ACC and PC.
    private func registers(clock: String) -> [SequentialNetlist.DFF] {
        (0..<bits).map { .init(name: accRegisterNames[$0], d: "acc_d\($0)", clk: clock, q: "acc\($0)") }
        + (0..<bits).map { .init(name: pcRegisterNames[$0], d: "pc_d\($0)", clk: clock, q: "pc\($0)") }
    }

    /// Build the combinational datapath + control into `b`. Reads the input/register nets,
    /// drives acc_d[], pc_d[], zero and we.
    private func buildCombinational(_ b: NANDGateBuilder) {
        let d = operandInputs, rd = memReadInputs

        // Decode opcode (op2 op1 op0) into one-hot controls.
        b.inv("op0", "op0b"); b.inv("op1", "op1b"); b.inv("op2", "op2b")
        b.andN(["op2b", "op1b", "op0"], "isLDI")   // 001
        b.andN(["op2b", "op1", "op0b"], "isLDA")   // 010
        b.andN(["op2b", "op1", "op0"], "we")       // 011 STA -> write-enable
        b.andN(["op2", "op1b", "op0b"], "isADD")   // 100
        b.andN(["op2", "op1b", "op0"], "isSUB")    // 101
        b.andN(["op2", "op1", "op0b"], "isJMP")    // 110
        b.andN(["op2", "op1", "op0"], "isJZ")      // 111
        b.or2("isADD", "isSUB", "isArith")

        // ALU: ACC + (mem_rdata XOR isSUB) + isSUB  (ADD when isSUB=0, two's-complement SUB when 1).
        var carry = "isSUB"
        for i in 0..<bits {
            let bx = b.node("bx")
            b.xor(rd[i], "isSUB", bx)
            let cout = i == bits - 1 ? b.node("aluc") : "alu_c\(i + 1)"
            b.fullAdder("acc\(i)", bx, carry, sum: "alu\(i)", cout: cout)
            carry = cout
        }

        // ACC source: one-hot select {LDI->immediate, LDA->mem_rdata, ADD/SUB->ALU}.
        for i in 0..<bits {
            let tLdi = b.node("sl"), tLda = b.node("sl"), tAlu = b.node("sl"), o1 = b.node("sl")
            b.and2("isLDI", d[i], tLdi)
            b.and2("isLDA", rd[i], tLda)
            b.and2("isArith", "alu\(i)", tAlu)
            b.or2(tLdi, tLda, o1)
            b.or2(o1, tAlu, "accSrc\(i)")
        }

        // ACC next: write (LDI|LDA|ADD|SUB) ? source : hold.
        let wL = b.node("w")
        b.or2("isLDI", "isLDA", wL)
        b.or2(wL, "isArith", "writeACC")
        b.inv("writeACC", "writeACCb")
        for i in 0..<bits {
            b.mux2(a: "acc\(i)", b: "accSrc\(i)", sel: "writeACC", nsel: "writeACCb", "acc_d\(i)")
        }

        // PC + 1 (ripple incrementer: add the constant 1).
        b.inv("pc0", "pcp0")                    // sum0 = ~pc0, carry0 = pc0
        var incCarry = "pc0"
        for i in 1..<bits {
            b.xor("pc\(i)", incCarry, "pcp\(i)")
            if i < bits - 1 {
                let nc = b.node("ic")
                b.and2("pc\(i)", incCarry, nc)
                incCarry = nc
            }
        }

        // Zero flag = NOR4(ACC) = ~(acc0|acc1) & ~(acc2|acc3).
        let zlo = b.node("z"), zhi = b.node("z")
        b.nor("acc0", "acc1", zlo); b.nor("acc2", "acc3", zhi)
        b.and2(zlo, zhi, "zero")

        // Jump = JMP | (JZ & zero).
        let jz = b.node("j")
        b.and2("isJZ", "zero", jz)
        b.or2("isJMP", jz, "doJump")
        b.inv("doJump", "doJumpb")

        // PC next: jump ? operand : PC+1.
        for i in 0..<bits {
            b.mux2(a: "pcp\(i)", b: d[i], sel: "doJump", nsel: "doJumpb", "pc_d\(i)")
        }
    }

    /// The sequential model (combinational logic + ACC/PC flip-flop primitives) for cycle
    /// simulation by `GateLevelLogicSimulator`.
    public func sequentialNetlist(name: String = "acc4", clock: String = "CLK") -> SequentialNetlist {
        let b = NANDGateBuilder(cellLibrary: cellLibrary)
        buildCombinational(b)
        return SequentialNetlist(name: name, combinational: b.instances, dffs: registers(clock: clock),
                                 inputs: inputs, outputs: outputs, clock: clock)
    }

    /// The flat gate-level netlist (combinational + ACC/PC flip-flops expanded to gates) for
    /// place & route + DRC/LVS.
    public func gateLevelNetlist(name: String = "acc4", clock: String = "CLK") -> GateLevelNetlist {
        let b = NANDGateBuilder(cellLibrary: cellLibrary)
        buildCombinational(b)
        var insts = b.instances
        let dff = DFFGenerator(cellLibrary: cellLibrary)
        for r in registers(clock: clock) {
            insts += dff.instances(prefix: r.name, d: r.d, clk: r.clk, q: r.q)
        }
        return GateLevelNetlist(name: name, instances: insts, inputs: inputs + [clock], outputs: outputs)
    }
}
