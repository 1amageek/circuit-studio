import Foundation

/// Errors raised while deriving a cell interface from its schematic.
public enum CellInterfaceError: Error, Equatable, LocalizedError {
    /// A port component's name is not a valid SPICE identifier.
    case invalidPortName(String)
    /// Two port components share the same name.
    case duplicatePortName(String)
    /// Two distinct ports are wired to the same net.
    case shortedPorts([String])
    /// A port component's pin is not connected to any net.
    case unconnectedPort(String)
    /// A port net is tied to the global ground node "0"; node 0 cannot
    /// appear on a `.subckt` port list.
    case portShortedToGround(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPortName(let name):
            return "Port name '\(name)' is not a valid SPICE identifier (expected [A-Za-z][A-Za-z0-9_]*)."
        case .duplicatePortName(let name):
            return "Duplicate port name '\(name)'. Port names must be unique within a cell."
        case .shortedPorts(let names):
            return "Ports \(names.joined(separator: ", ")) are wired to the same net. Each port needs its own net."
        case .unconnectedPort(let name):
            return "Port '\(name)' is not connected to any wire."
        case .portShortedToGround(let name):
            return "Port '\(name)' is tied to global ground. Node 0 cannot be a subcircuit port."
        }
    }
}

/// The external connection contract of a cell, derived deterministically
/// from the port components placed on its schematic.
///
/// The schematic is the single source of truth: the interface is never
/// persisted, it is re-derived on demand. Port order is canonical —
/// inputs, outputs, bidirectional, power, ground; alphabetical within each
/// group — so `.subckt` lines and `X` instance lines always agree.
public struct CellInterface: Sendable, Equatable {
    public let ports: [CellPort]

    public init(ports: [CellPort]) {
        self.ports = ports
    }

    /// True when `name` is usable as a SPICE node/subcircuit identifier.
    public static func isValidSPICEName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first else { return false }
        guard (first.properties.isAlphabetic && first.isASCII) else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (
                scalar.properties.isAlphabetic
                    || ("0"..."9").contains(Character(scalar))
                    || scalar == "_"
            )
        }
    }

    /// Derives the interface from the port components on a schematic.
    ///
    /// Runs net extraction to verify each port is wired to its own net.
    /// Throws instead of degrading: a cell with an invalid interface cannot
    /// be referenced from other schematics.
    public static func derive(from document: SchematicDocument) throws -> CellInterface {
        var ports: [CellPort] = []
        var portComponentIDs: [UUID: String] = [:]
        var seenNames: Set<String> = []

        for component in document.components {
            guard let direction = PortDirection(deviceKindID: component.deviceKindID) else {
                continue
            }
            let name = component.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidSPICEName(name) else {
                throw CellInterfaceError.invalidPortName(name)
            }
            guard seenNames.insert(name).inserted else {
                throw CellInterfaceError.duplicatePortName(name)
            }
            ports.append(CellPort(name: name, direction: direction))
            portComponentIDs[component.id] = name
        }

        let nets = NetExtractor().extract(from: document)

        var connectedPortNames: Set<String> = []
        for net in nets {
            let portsOnNet = net.connections
                .compactMap { portComponentIDs[$0.componentID] }
                .sorted()
            guard !portsOnNet.isEmpty else { continue }
            if Set(portsOnNet).count > 1 {
                throw CellInterfaceError.shortedPorts(Array(Set(portsOnNet)).sorted())
            }
            if net.name == "0" {
                throw CellInterfaceError.portShortedToGround(portsOnNet[0])
            }
            connectedPortNames.formUnion(portsOnNet)
        }

        for port in ports where !connectedPortNames.contains(port.name) {
            throw CellInterfaceError.unconnectedPort(port.name)
        }

        let ordered = ports.sorted { lhs, rhs in
            if lhs.direction.canonicalGroupIndex != rhs.direction.canonicalGroupIndex {
                return lhs.direction.canonicalGroupIndex < rhs.direction.canonicalGroupIndex
            }
            return lhs.name < rhs.name
        }
        return CellInterface(ports: ordered)
    }
}
