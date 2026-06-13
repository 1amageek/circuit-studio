import Foundation

/// A port component resolved to its SPICE variable name.
public struct ResolvedTerminal: Sendable {
    /// The component ID of the port component.
    public let componentID: UUID
    /// The port component's instance name (e.g. "Vout").
    public let label: String
    /// The SPICE variable name (e.g. "V(net3)").
    public let variableName: String

    public init(componentID: UUID, label: String, variableName: String) {
        self.componentID = componentID
        self.label = label
        self.variableName = variableName
    }
}

/// Resolves port components in a schematic to SPICE variable names.
///
/// Ports mark the cell boundary and double as measurement points. Each
/// port's pin connects to a net, and the resolver maps that to V(netName)
/// for the waveform viewer. Since net extraction names a port's net after
/// the port itself, the variable is typically V(portName).
public struct TerminalResolver: Sendable {

    public init() {}

    /// Resolve all port components to SPICE variable names.
    ///
    /// Skips port components whose pin is not connected to any net.
    public func resolve(
        document: SchematicDocument,
        nets: [ExtractedNet],
        catalog: DeviceCatalog
    ) -> [ResolvedTerminal] {
        // Build pin-to-net map
        var pinNetMap: [String: String] = [:]
        for net in nets {
            for conn in net.connections {
                pinNetMap["\(conn.componentID):\(conn.portID)"] = net.name
            }
        }

        var results: [ResolvedTerminal] = []

        for component in document.components {
            guard PortDirection(deviceKindID: component.deviceKindID) != nil else { continue }
            guard let kind = catalog.device(for: component.deviceKindID) else { continue }

            // Find the net connected to the port's pin
            guard let port = kind.portDefinitions.first else { continue }
            let key = "\(component.id):\(port.id)"
            guard let netName = pinNetMap[key] else { continue }

            results.append(ResolvedTerminal(
                componentID: component.id,
                label: component.name,
                variableName: "V(\(netName))"
            ))
        }

        return results
    }
}
