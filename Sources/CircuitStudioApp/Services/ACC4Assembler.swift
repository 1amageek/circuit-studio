import Foundation

/// Parses ACC-4 assembly TEXT into a program (`[ACC4Instruction]`) — so a program is data
/// loaded from a file, not hardcoded Swift. One instruction per line: `MNEMONIC [operand]`,
/// with `;` line comments and optional `label:` definitions usable as a JMP/JZ target.
public struct ACC4Assembler: Sendable {

    public enum AssembleError: Error, LocalizedError, Equatable {
        case unknownMnemonic(line: Int, token: String)
        case badOperand(line: Int, token: String)
        case unknownLabel(line: Int, label: String)
        case operandOutOfRange(line: Int, value: Int)

        public var errorDescription: String? {
            switch self {
            case .unknownMnemonic(let l, let t): return "line \(l): unknown mnemonic '\(t)'"
            case .badOperand(let l, let t): return "line \(l): operand '\(t)' is not a number or known label"
            case .unknownLabel(let l, let s): return "line \(l): undefined label '\(s)'"
            case .operandOutOfRange(let l, let v): return "line \(l): operand \(v) is outside 0...15"
            }
        }
    }

    public init() {}

    /// Strip a trailing `;` comment and surrounding whitespace.
    private func clean(_ line: String) -> String {
        String(line.prefix { $0 != ";" }).trimmingCharacters(in: .whitespaces)
    }

    public func assemble(_ source: String) throws -> [ACC4Instruction] {
        let rawLines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Pass 1: resolve labels to instruction addresses.
        var labels: [String: Int] = [:]
        var address = 0
        for raw in rawLines {
            var body = clean(raw)
            while let colon = body.firstIndex(of: ":") {
                let label = String(body[body.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                labels[label] = address
                body = String(body[body.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
            if !body.isEmpty { address += 1 }
        }

        // Pass 2: encode each instruction line.
        var program: [ACC4Instruction] = []
        for (index, raw) in rawLines.enumerated() {
            let lineNo = index + 1
            var body = clean(raw)
            while let colon = body.firstIndex(of: ":") {
                body = String(body[body.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
            guard !body.isEmpty else { continue }

            let tokens = body.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," }).map(String.init)
            guard let opcode = ACC4Opcode(mnemonic: tokens[0]) else {
                throw AssembleError.unknownMnemonic(line: lineNo, token: tokens[0])
            }
            var operand = 0
            if tokens.count > 1 {
                let tok = tokens[1]
                if let value = Int(tok) {
                    operand = value
                } else if let resolved = labels[tok] {
                    operand = resolved
                } else {
                    throw AssembleError.badOperand(line: lineNo, token: tok)
                }
                guard (0...15).contains(operand) else {
                    throw AssembleError.operandOutOfRange(line: lineNo, value: operand)
                }
            }
            program.append(ACC4Instruction(opcode, operand))
        }
        return program
    }
}
