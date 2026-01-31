import Foundation

/// A PORT component resolved to its SPICE variable name.
public struct ResolvedTerminal: Sendable {
    /// The component ID of the PORT component.
    public let componentID: UUID
    /// The PORT component's instance name (e.g. "Vout").
    public let label: String
    /// The SPICE variable name (e.g. "V(net3)").
    public let variableName: String

    public init(componentID: UUID, label: String, variableName: String) {
        self.componentID = componentID
        self.label = label
        self.variableName = variableName
    }
}

/// Resolves Terminal (PORT) components in a schematic to SPICE variable names.
///
/// PORT components are user-placed measurement points. Each PORT's pin connects
/// to a net, and the resolver maps that to V(netName) for the waveform viewer.
public struct TerminalResolver: Sendable {

    public init() {}

    /// Resolve all PORT components to SPICE variable names.
    ///
    /// Skips PORT components whose pin is not connected to any net.
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
            guard component.deviceKindID == "terminal" else { continue }
            guard let kind = catalog.device(for: component.deviceKindID) else { continue }

            // Find the net connected to the PORT's pin
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
