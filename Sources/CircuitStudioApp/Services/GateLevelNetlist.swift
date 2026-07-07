import Foundation

/// A gate-level netlist: standard-cell instances wired together — the circuit INTENT one
/// level above a single cell. The circuit synthesizer places the cells in a row and
/// routes the nets between them into a flat, DRC/LVS-clean layout.
public struct GateLevelNetlist: Sendable, Hashable, Codable, Identifiable {

    public var id: String { name }

    public enum ValidationError: Error, LocalizedError, Equatable, Sendable {
        case missingOutput(netlistName: String)

        public var errorDescription: String? {
            switch self {
            case .missingOutput(let netlistName):
                return "Gate-level netlist '\(netlistName)' must declare at least one output net."
            }
        }
    }

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

    private enum CodingKeys: String, CodingKey {
        case name
        case instances
        case inputs
        case outputs
        case vpwr
        case vgnd
    }

    public var primaryOutput: String? {
        outputs.first
    }

    public func requirePrimaryOutput() throws -> String {
        guard let output = primaryOutput else {
            throw ValidationError.missingOutput(netlistName: name)
        }
        return output
    }

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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let outputs = try container.decode([String].self, forKey: .outputs)
        guard !outputs.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .outputs,
                in: container,
                debugDescription: "GateLevelNetlist '\(name)' must declare at least one output net."
            )
        }

        self.name = name
        self.instances = try container.decode([Instance].self, forKey: .instances)
        self.inputs = try container.decode([String].self, forKey: .inputs)
        self.outputs = outputs
        self.vpwr = try container.decodeIfPresent(String.self, forKey: .vpwr) ?? "VPWR"
        self.vgnd = try container.decodeIfPresent(String.self, forKey: .vgnd) ?? "VGND"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(instances, forKey: .instances)
        try container.encode(inputs, forKey: .inputs)
        try container.encode(outputs, forKey: .outputs)
        try container.encode(vpwr, forKey: .vpwr)
        try container.encode(vgnd, forKey: .vgnd)
    }

    /// The circuit net driven by each instance's output.
    public func driverNet(of instance: Instance) -> String { instance.net(instance.cell.output) }

    /// All nets that are driven by some instance's output (i.e. internal or top-output
    /// nets, as opposed to primary inputs).
    public var drivenNets: Set<String> { Set(instances.map { driverNet(of: $0) }) }

    // MARK: - common circuits

    /// AND2 = NAND2 -> INV. Y = a AND b.
    public static func and2(name: String = "and2", a: String = "a", b: String = "b",
                            output: String = "y") throws -> GateLevelNetlist {
        try and2(name: name, a: a, b: b, output: output, cellLibrary: CMOSGateLibrary.loadBundledDefault())
    }

    public static func and2(name: String = "and2", a: String = "a", b: String = "b",
                            output: String = "y",
                            cellLibrary: CMOSGateLibrary) -> GateLevelNetlist {
        GateLevelNetlist(name: name, instances: [
            Instance(name: "g0", cell: cellLibrary.nand(name: "nand2", inputs: ["A", "B"]),
                     netMap: ["A": a, "B": b, "Y": "n_and"]),
            Instance(name: "g1", cell: cellLibrary.inverter(name: "inv"), netMap: ["A": "n_and", "Y": output]),
        ], inputs: [a, b], output: output)
    }

    /// OR2 = NOR2 -> INV. Y = a OR b.
    public static func or2(name: String = "or2", a: String = "a", b: String = "b",
                           output: String = "y") throws -> GateLevelNetlist {
        try or2(name: name, a: a, b: b, output: output, cellLibrary: CMOSGateLibrary.loadBundledDefault())
    }

    public static func or2(name: String = "or2", a: String = "a", b: String = "b",
                           output: String = "y",
                           cellLibrary: CMOSGateLibrary) -> GateLevelNetlist {
        GateLevelNetlist(name: name, instances: [
            Instance(name: "g0", cell: cellLibrary.nor(name: "nor2", inputs: ["A", "B"]),
                     netMap: ["A": a, "B": b, "Y": "n_or"]),
            Instance(name: "g1", cell: cellLibrary.inverter(name: "inv"), netMap: ["A": "n_or", "Y": output]),
        ], inputs: [a, b], output: output)
    }

    /// An N-stage inverter chain. Y = in (even N) / NOT(in) (odd N).
    public static func inverterChain(name: String = "invchain", stages: Int,
                                     input: String = "a", output: String = "y") throws -> GateLevelNetlist {
        try inverterChain(
            name: name,
            stages: stages,
            input: input,
            output: output,
            cellLibrary: CMOSGateLibrary.loadBundledDefault()
        )
    }

    public static func inverterChain(name: String = "invchain", stages: Int,
                                     input: String = "a", output: String = "y",
                                     cellLibrary: CMOSGateLibrary) -> GateLevelNetlist {
        var insts: [Instance] = []
        for i in 0..<stages {
            let inNet = i == 0 ? input : "c\(i)"
            let outNet = i == stages - 1 ? output : "c\(i + 1)"
            insts.append(Instance(name: "g\(i)", cell: cellLibrary.inverter(name: "inv"),
                                  netMap: ["A": inNet, "Y": outNet]))
        }
        return GateLevelNetlist(name: name, instances: insts, inputs: [input], output: output)
    }
}
