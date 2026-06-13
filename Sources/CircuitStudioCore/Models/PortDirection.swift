import Foundation

/// Electrical direction of a cell port.
///
/// Determines the port's side on the auto-generated cell symbol and its
/// group position in the canonical `.subckt` port order.
public enum PortDirection: String, Sendable, Codable, CaseIterable {
    case input
    case output
    case bidirectional
    case power
    case ground

    /// The device-kind ID of the schematic port component for this direction.
    public var deviceKindID: String {
        switch self {
        case .input: return "port_input"
        case .output: return "port_output"
        case .bidirectional: return "port_inout"
        case .power: return "port_power"
        case .ground: return "port_ground"
        }
    }

    /// Resolves a schematic component's device-kind ID to a port direction.
    /// Returns nil when the ID does not denote a port component.
    public init?(deviceKindID: String) {
        switch deviceKindID {
        case "port_input": self = .input
        case "port_output": self = .output
        case "port_inout": self = .bidirectional
        case "port_power": self = .power
        case "port_ground": self = .ground
        default: return nil
        }
    }

    /// Position of this direction's group in the canonical port order:
    /// inputs, outputs, bidirectional, power, ground.
    public var canonicalGroupIndex: Int {
        switch self {
        case .input: return 0
        case .output: return 1
        case .bidirectional: return 2
        case .power: return 3
        case .ground: return 4
        }
    }
}
