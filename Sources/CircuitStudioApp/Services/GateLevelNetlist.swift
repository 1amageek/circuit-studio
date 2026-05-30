import Foundation

/// A gate-level netlist: standard-cell instances wired together — the circuit INTENT one
/// level above a single cell. The circuit synthesizer places the cells in a row and
/// routes the nets between them into a flat, DRC/LVS-clean layout.
public struct GateLevelNetlist: Sendable, Hashable, Codable, Identifiable {

    public var id: String { name }

    /// One placed cell. `cell` is its transistor-level definition; `netMap` renames the
    /// cell's local nets (gates + output) to circuit nets. VPWR/VGND are global.
    public struct Instance: Sendable, Hashable, Codable {
        public let name: String
        public let cell: CMOSGateNetlist
        public let netMap: [String: String]   // cell-local net -> circuit net

        public init(name: String, cell: CMOSGateNetlist, netMap: [String: String]) {
            self.name = name
            self.cell = cell
            self.netMap = netMap
        }

        /// The circuit net a cell-local net resolves to (identity if unmapped, e.g. rails).
        public func net(_ local: String) -> String { netMap[local] ?? local }
    }

    public let name: String
    public let instances: [Instance]
    public let inputs: [String]
    public let outputs: [String]
    public let vpwr: String
    public let vgnd: String

    /// The first (or only) output net.
    public var output: String { outputs.first ?? "" }

    public init(name: String, instances: [Instance], inputs: [String], output: String,
                vpwr: String = "VPWR", vgnd: String = "VGND") {
        self.init(name: name, instances: instances, inputs: inputs, outputs: [output], vpwr: vpwr, vgnd: vgnd)
    }

    public init(name: String, instances: [Instance], inputs: [String], outputs: [String],
                vpwr: String = "VPWR", vgnd: String = "VGND") {
        self.name = name
        self.instances = instances
        self.inputs = inputs
        self.outputs = outputs
        self.vpwr = vpwr
        self.vgnd = vgnd
    }

    /// The circuit net driven by each instance's output.
    public func driverNet(of instance: Instance) -> String { instance.net(instance.cell.output) }

    /// All nets that are driven by some instance's output (i.e. internal or top-output
    /// nets, as opposed to primary inputs).
    public var drivenNets: Set<String> { Set(instances.map { driverNet(of: $0) }) }

    // MARK: - common circuits

    /// AND2 = NAND2 -> INV. Y = a AND b.
    public static func and2(name: String = "and2", a: String = "a", b: String = "b",
                            output: String = "y") -> GateLevelNetlist {
        GateLevelNetlist(name: name, instances: [
            Instance(name: "g0", cell: .nand(name: "nand2", inputs: ["A", "B"]),
                     netMap: ["A": a, "B": b, "Y": "n_and"]),
            Instance(name: "g1", cell: .inverter(name: "inv"), netMap: ["A": "n_and", "Y": output]),
        ], inputs: [a, b], output: output)
    }

    /// OR2 = NOR2 -> INV. Y = a OR b.
    public static func or2(name: String = "or2", a: String = "a", b: String = "b",
                           output: String = "y") -> GateLevelNetlist {
        GateLevelNetlist(name: name, instances: [
            Instance(name: "g0", cell: .nor(name: "nor2", inputs: ["A", "B"]),
                     netMap: ["A": a, "B": b, "Y": "n_or"]),
            Instance(name: "g1", cell: .inverter(name: "inv"), netMap: ["A": "n_or", "Y": output]),
        ], inputs: [a, b], output: output)
    }

    /// An N-stage inverter chain. Y = in (even N) / NOT(in) (odd N).
    public static func inverterChain(name: String = "invchain", stages: Int,
                                     input: String = "a", output: String = "y") -> GateLevelNetlist {
        var insts: [Instance] = []
        for i in 0..<stages {
            let inNet = i == 0 ? input : "c\(i)"
            let outNet = i == stages - 1 ? output : "c\(i + 1)"
            insts.append(Instance(name: "g\(i)", cell: .inverter(name: "inv"),
                                  netMap: ["A": inNet, "Y": outNet]))
        }
        return GateLevelNetlist(name: name, instances: insts, inputs: [input], output: output)
    }
}
