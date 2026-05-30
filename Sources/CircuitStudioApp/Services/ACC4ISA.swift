import Foundation

/// The ACC-4 instruction-set architecture: a minimal 4-bit accumulator machine. One
/// instruction is a 7-bit word — a 3-bit opcode in bits [6:4] and a 4-bit operand
/// (immediate or address) in bits [3:0], packed into a byte. Programs are DATA: an
/// `[Instruction]` parsed from assembly text, never hardcoded control flow.
public enum ACC4Opcode: Int, Sendable, Hashable, CaseIterable {
    case nop = 0   // do nothing
    case ldi = 1   // ACC <- operand (immediate)
    case lda = 2   // ACC <- mem[operand]
    case sta = 3   // mem[operand] <- ACC
    case add = 4   // ACC <- ACC + mem[operand]
    case sub = 5   // ACC <- ACC - mem[operand]
    case jmp = 6   // PC  <- operand
    case jz  = 7   // PC  <- operand if ACC == 0, else PC + 1

    public var mnemonic: String {
        switch self {
        case .nop: return "NOP"; case .ldi: return "LDI"; case .lda: return "LDA"
        case .sta: return "STA"; case .add: return "ADD"; case .sub: return "SUB"
        case .jmp: return "JMP"; case .jz: return "JZ"
        }
    }

    public init?(mnemonic: String) {
        guard let op = Self.allCases.first(where: { $0.mnemonic == mnemonic.uppercased() }) else { return nil }
        self = op
    }
}

/// One decoded instruction. `operand` is a 4-bit value (0...15).
public struct ACC4Instruction: Sendable, Hashable {
    public let opcode: ACC4Opcode
    public let operand: Int

    public init(_ opcode: ACC4Opcode, _ operand: Int = 0) {
        self.opcode = opcode
        self.operand = operand & 0xF
    }

    /// The packed 7-bit word: opcode in [6:4], operand in [3:0].
    public var word: Int { (opcode.rawValue << 4) | operand }

    /// The instruction as 8 input bits (bit i = (word >> i) & 1); bit 7 is unused (0).
    public var bits: [Bool] { (0..<8).map { (word >> $0) & 1 == 1 } }
}
