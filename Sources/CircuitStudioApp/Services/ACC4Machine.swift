import Foundation

/// Executes a program on the GATE-LEVEL ACC-4 core, clocking the synthesized netlist one
/// cycle at a time and modeling the EXTERNAL instruction and data memory between edges:
/// each cycle it reads the present PC from the register state, fetches `program[pc]`, drives
/// the decoded instruction + the data-read bus, steps the gate logic, then applies a store
/// when the core asserts write-enable. The resulting (PC, ACC) trace must match the
/// independent `ACC4Reference` — that is the functional proof the hardware runs the program.
public struct ACC4Machine: Sendable {

    public enum RunError: Error, LocalizedError, Equatable {
        case writeEnableMismatch(cycle: Int, hardware: Bool, expected: Bool)

        public var errorDescription: String? {
            switch self {
            case .writeEnableMismatch(let c, let hw, let exp):
                return "cycle \(c): core write-enable \(hw) != expected STA \(exp)"
            }
        }
    }

    public let generator: ACC4CPUGenerator
    public let memoryWords: Int
    private let sim = GateLevelLogicSimulator()

    public init(generator: ACC4CPUGenerator = ACC4CPUGenerator(), memoryWords: Int = 16) {
        self.generator = generator
        self.memoryWords = memoryWords
    }

    private func value(_ state: [String: Bool], _ names: [String]) -> Int {
        names.enumerated().reduce(0) { $0 | ((state[$1.element] ?? false) ? (1 << $1.offset) : 0) }
    }

    /// Run `program` for `cycles` clocks on the gate-level core; returns the present
    /// (PC, ACC) per cycle. Throws if the core's write-enable disagrees with the ISA.
    public func run(_ program: [ACC4Instruction], cycles: Int) throws -> [ACC4Reference.CycleState] {
        let netlist = generator.sequentialNetlist()
        var state = sim.initialState(netlist)
        var mem = [Int](repeating: 0, count: memoryWords)
        var trace: [ACC4Reference.CycleState] = []

        for cycle in 0..<cycles {
            let pc = value(state, generator.pcRegisterNames)
            let acc = value(state, generator.accRegisterNames)
            trace.append(.init(pc: pc, acc: acc))

            let instr = pc < program.count ? program[pc] : ACC4Instruction(.nop)
            let opcode = instr.opcode.rawValue
            var inputs: [String: Bool] = [:]
            for i in 0..<generator.bits { inputs[generator.operandInputs[i]] = (instr.operand >> i) & 1 == 1 }
            for i in 0..<3 { inputs[generator.opcodeInputs[i]] = (opcode >> i) & 1 == 1 }
            let readValue = mem[instr.operand]
            for i in 0..<generator.bits { inputs[generator.memReadInputs[i]] = (readValue >> i) & 1 == 1 }

            let (nets, next) = try sim.step(netlist, state: state, inputs: inputs)

            // The core's write-enable must agree with the ISA, then drive the external store.
            let we = nets["we"] ?? false
            let expected = instr.opcode == .sta
            guard we == expected else {
                throw RunError.writeEnableMismatch(cycle: cycle, hardware: we, expected: expected)
            }
            if we { mem[instr.operand] = acc }   // store the present ACC

            state = next
        }
        return trace
    }
}
