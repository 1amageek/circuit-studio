import Foundation

/// Parses a Boolean expression string into a `BooleanGateMapper.Expr`, so logic INTENT is
/// data loaded from a file/string — not hardcoded in Swift. Grammar (recursive descent):
///
///   assignment := [ identifier '=' ] expr
///   expr       := term ( '|' term )*
///   term       := factor ( '&' factor )*
///   factor     := '~' factor | '(' expr ')' | identifier
///
/// `|`/`+` are OR, `&`/`*` are AND, `~`/`!` are NOT.
public struct BooleanExpressionParser: Sendable {

    public enum ParseError: Error, LocalizedError, Equatable {
        case unexpectedEnd
        case unexpected(String)
        case expected(String)

        public var errorDescription: String? {
            switch self {
            case .unexpectedEnd: return "Unexpected end of expression."
            case .unexpected(let t): return "Unexpected token '\(t)'."
            case .expected(let t): return "Expected '\(t)'."
            }
        }
    }

    public init() {}

    /// Parse an expression; if it is `lhs = rhs`, the lhs is ignored (the output name is
    /// supplied to `netlist(...)`).
    public func parse(_ source: String) throws -> BooleanGateMapper.Expr {
        var tokens = tokenize(source)
        // Drop an optional `identifier =` assignment prefix.
        if tokens.count >= 2, case .identifier = tokens[0], tokens[1] == .equals {
            tokens.removeFirst(2)
        }
        var parser = Cursor(tokens: tokens)
        let expr = try parser.parseExpr()
        guard parser.isAtEnd else { throw ParseError.unexpected(parser.peekDescription) }
        return expr
    }

    /// Parse and technology-map to a placed-and-routable gate-level netlist.
    public func netlist(_ source: String, name: String, output: String = "y") throws -> GateLevelNetlist {
        BooleanGateMapper().map(try parse(source), name: name, output: output)
    }

    // MARK: - tokens

    private enum Token: Equatable {
        case identifier(String), and, or, not, lparen, rparen, equals
    }

    private func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        var ident = ""
        func flush() { if !ident.isEmpty { tokens.append(.identifier(ident)); ident = "" } }
        for ch in s {
            switch ch {
            case "&", "*": flush(); tokens.append(.and)
            case "|", "+": flush(); tokens.append(.or)
            case "~", "!": flush(); tokens.append(.not)
            case "(": flush(); tokens.append(.lparen)
            case ")": flush(); tokens.append(.rparen)
            case "=": flush(); tokens.append(.equals)
            case " ", "\t", "\n", "\r": flush()
            default: ident.append(ch)
            }
        }
        flush()
        return tokens
    }

    // MARK: - recursive descent

    private struct Cursor {
        let tokens: [Token]
        var i = 0
        var isAtEnd: Bool { i >= tokens.count }
        var peekDescription: String { isAtEnd ? "end" : "\(tokens[i])" }

        mutating func parseExpr() throws -> BooleanGateMapper.Expr {
            var node = try parseTerm()
            while !isAtEnd, tokens[i] == .or { i += 1; node = .or(node, try parseTerm()) }
            return node
        }
        mutating func parseTerm() throws -> BooleanGateMapper.Expr {
            var node = try parseFactor()
            while !isAtEnd, tokens[i] == .and { i += 1; node = .and(node, try parseFactor()) }
            return node
        }
        mutating func parseFactor() throws -> BooleanGateMapper.Expr {
            guard !isAtEnd else { throw ParseError.unexpectedEnd }
            switch tokens[i] {
            case .not:
                i += 1
                return .not(try parseFactor())
            case .lparen:
                i += 1
                let inner = try parseExpr()
                guard !isAtEnd, tokens[i] == .rparen else { throw ParseError.expected(")") }
                i += 1
                return inner
            case .identifier(let name):
                i += 1
                return .input(name)
            default:
                throw ParseError.unexpected("\(tokens[i])")
            }
        }
    }
}
