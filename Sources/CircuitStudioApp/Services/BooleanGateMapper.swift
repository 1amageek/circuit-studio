import Foundation

/// Maps a Boolean expression (the logic INTENT) to a `GateLevelNetlist` of standard cells
/// — the front of the flow, one level above gate instances. Technology mapping is the
/// canonical static-CMOS decomposition: NOT→INV, AND→NAND2+INV, OR→NOR2+INV. The circuit
/// synthesizer then places & routes the result into a DRC/LVS-clean layout.
public struct BooleanGateMapper: Sendable {

    /// A Boolean expression over named inputs.
    public indirect enum Expr: Sendable, Hashable {
        case input(String)
        case not(Expr)
        case and(Expr, Expr)
        case or(Expr, Expr)
    }

    private let cellLibrary: CMOSGateLibrary

    public init(cellLibrary: CMOSGateLibrary) {
        self.cellLibrary = cellLibrary
    }

    public init() throws {
        self.init(cellLibrary: try CMOSGateLibrary.loadBundledDefault())
    }

    /// Decompose `expr` into a gate-level netlist whose output net is `output`.
    public func map(_ expr: Expr, name: String, output: String = "y") -> GateLevelNetlist {
        var instances: [GateLevelNetlist.Instance] = []
        var inputs: [String] = []
        var seenInput = Set<String>()
        var counter = 0
        func fresh() -> String { counter += 1; return "w\(counter)" }
        func add(_ cell: CMOSGateNetlist, _ map: [String: String]) {
            instances.append(.init(name: "u\(instances.count)", cell: cell, netMap: map))
        }

        // Returns the net carrying the value of `e`.
        func build(_ e: Expr) -> String {
            switch e {
            case .input(let x):
                if seenInput.insert(x).inserted { inputs.append(x) }
                return x
            case .not(let a):
                let na = build(a), out = fresh()
                add(cellLibrary.inverter(name: "inv"), ["A": na, "Y": out])
                return out
            case .and(let a, let b):
                let na = build(a), nb = build(b), t = fresh(), out = fresh()
                add(cellLibrary.nand(name: "nand2", inputs: ["A", "B"]), ["A": na, "B": nb, "Y": t])
                add(cellLibrary.inverter(name: "inv"), ["A": t, "Y": out])
                return out
            case .or(let a, let b):
                let na = build(a), nb = build(b), t = fresh(), out = fresh()
                add(cellLibrary.nor(name: "nor2", inputs: ["A", "B"]), ["A": na, "B": nb, "Y": t])
                add(cellLibrary.inverter(name: "inv"), ["A": t, "Y": out])
                return out
            }
        }

        let top = build(expr)
        // Rename the top net to the requested circuit output.
        instances = instances.map { inst in
            let remapped = inst.netMap.mapValues { $0 == top ? output : $0 }
            return GateLevelNetlist.Instance(name: inst.name, cell: inst.cell, netMap: remapped)
        }
        return GateLevelNetlist(name: name, instances: instances, inputs: inputs.sorted(), output: output)
    }
}
