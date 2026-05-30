import Foundation

/// A plain instruction-set interpreter for the ACC-4 ISA — the INDEPENDENT golden model.
/// It executes a program against an external data memory by the ISA semantics (no gates),
/// producing a per-cycle (PC, ACC) trace and a log of memory stores. The gate-level CPU is
/// verified by matching this trace, so a hardware bug cannot hide behind a shared bug.
public struct ACC4Reference: Sendable {

    public struct CycleState: Sendable, Hashable {
        public let pc: Int      // program counter at the START of the cycle
        public let acc: Int     // accumulator at the START of the cycle
    }

    public struct StoreEvent: Sendable, Hashable {
        public let cycle: Int
        public let address: Int
        public let value: Int
    }

    public struct Result: Sendable {
        public let trace: [CycleState]    // present (pc, acc) per executed cycle
        public let stores: [StoreEvent]   // every STA in order
    }

    public let memoryWords: Int

    public init(memoryWords: Int = 16) { self.memoryWords = memoryWords }

    /// Run `program` for `cycles` clocks. The PC fetches `program[pc]` (out-of-range = NOP).
    public func run(_ program: [ACC4Instruction], cycles: Int) -> Result {
        var pc = 0, acc = 0
        var mem = [Int](repeating: 0, count: memoryWords)
        var trace: [CycleState] = []
        var stores: [StoreEvent] = []

        for cycle in 0..<cycles {
            trace.append(CycleState(pc: pc, acc: acc))
            let instr = pc < program.count ? program[pc] : ACC4Instruction(.nop)
            let addr = instr.operand
            switch instr.opcode {
            case .nop: pc = (pc + 1) & 0xF
            case .ldi: acc = instr.operand & 0xF; pc = (pc + 1) & 0xF
            case .lda: acc = mem[addr]; pc = (pc + 1) & 0xF
            case .sta: mem[addr] = acc; stores.append(StoreEvent(cycle: cycle, address: addr, value: acc)); pc = (pc + 1) & 0xF
            case .add: acc = (acc + mem[addr]) & 0xF; pc = (pc + 1) & 0xF
            case .sub: acc = (acc - mem[addr]) & 0xF; pc = (pc + 1) & 0xF
            case .jmp: pc = addr
            case .jz:  pc = acc == 0 ? addr : (pc + 1) & 0xF
            }
        }
        return Result(trace: trace, stores: stores)
    }
}
