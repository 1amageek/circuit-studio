import Foundation

/// Parses a structural gate-level netlist (a Verilog subset) into a `GateLevelNetlist`,
/// so a circuit is DATA loaded from a file — not hardcoded in Swift. The supported subset:
///
///   module NAME ( ports );
///     input  a, b ;
///     output y ;
///     CELL inst ( .PORT(net), ... ) ;   // CELL in {inv, nand2, nand3, nor2, nor3}
///   endmodule
///
/// Connections are by name (`.A(net)`); the cell's ports are A/B/C (gates) and Y (output).
public struct VerilogStructuralParser: Sendable {

    public enum ParseError: Error, LocalizedError, Equatable {
        case noModule
        case noOutputPort
        case unknownCell(String)
        case malformedInstance(String)
        case missingPort(instance: String, port: String)

        public var errorDescription: String? {
            switch self {
            case .noModule: return "No `module ... endmodule` found."
            case .noOutputPort: return "The module declares no `output`."
            case .unknownCell(let c): return "Unknown cell type '\(c)' (expected inv/nand2/nand3/nor2/nor3)."
            case .malformedInstance(let s): return "Malformed instance: \(s)"
            case .missingPort(let i, let p): return "Instance \(i) does not connect port \(p)."
            }
        }
    }

    public init() {}

    /// The cell template for a library cell name (its gate + output ports are fixed).
    private func cell(for type: String) throws -> CMOSGateNetlist {
        switch type {
        case "inv", "inverter": return .inverter(name: type)
        case "nand2": return .nand(name: type, inputs: ["A", "B"])
        case "nand3": return .nand(name: type, inputs: ["A", "B", "C"])
        case "nor2": return .nor(name: type, inputs: ["A", "B"])
        case "nor3": return .nor(name: type, inputs: ["A", "B", "C"])
        default: throw ParseError.unknownCell(type)
        }
    }

    public func parse(_ source: String) throws -> GateLevelNetlist {
        let text = stripComments(source)
        let ns0 = text as NSString
        guard let moduleRE = try? NSRegularExpression(pattern: #"module\s+(\w+)\s*\(([^)]*)\)\s*;"#),
              let module = moduleRE.firstMatch(in: text, range: NSRange(location: 0, length: ns0.length)) else {
            throw ParseError.noModule
        }
        let name = ns0.substring(with: module.range(at: 1))
        let body = ns0.substring(from: module.range.location + module.range.length)

        let inputs = declaredNets("input", in: body)
        let outputs = declaredNets("output", in: body)
        guard let output = outputs.first else { throw ParseError.noOutputPort }

        var instances: [GateLevelNetlist.Instance] = []
        // Instance: CELL inst ( .PORT(net), ... ) ;  — exclude input/output/module/endmodule.
        // The connection group allows one level of nested parens (the .PORT(net) pairs).
        let reserved: Set<String> = ["input", "output", "module", "endmodule", "wire"]
        let instRE = try NSRegularExpression(pattern: #"(\w+)\s+(\w+)\s*\(((?:[^()]|\([^()]*\))*)\)\s*;"#)
        let ns = body as NSString
        for m in instRE.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            let type = ns.substring(with: m.range(at: 1))
            guard !reserved.contains(type) else { continue }
            let inst = ns.substring(with: m.range(at: 2))
            let conns = ns.substring(with: m.range(at: 3))
            let template = try cell(for: type)
            var netMap: [String: String] = [:]
            let connRE = try NSRegularExpression(pattern: #"\.(\w+)\s*\(\s*(\w+)\s*\)"#)
            let cns = conns as NSString
            for c in connRE.matches(in: conns, range: NSRange(location: 0, length: cns.length)) {
                netMap[cns.substring(with: c.range(at: 1))] = cns.substring(with: c.range(at: 2))
            }
            guard netMap[template.output] != nil else { throw ParseError.missingPort(instance: inst, port: template.output) }
            instances.append(.init(name: inst, cell: template, netMap: netMap))
        }
        return GateLevelNetlist(name: name, instances: instances, inputs: inputs, output: output)
    }

    // MARK: - text helpers

    private func stripComments(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"//[^\n]*"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"/\*.*?\*/"#, with: "", options: [.regularExpression])
        return t
    }

    private func declaredNets(_ keyword: String, in body: String) -> [String] {
        var nets: [String] = []
        let ns = body as NSString
        guard let re = try? NSRegularExpression(pattern: "\\b\(keyword)\\s+([^;]+);") else { return nets }
        for m in re.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            let list = ns.substring(with: m.range(at: 1))
            for n in list.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" }) {
                let token = n.trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty { nets.append(token) }
            }
        }
        return nets
    }
}
