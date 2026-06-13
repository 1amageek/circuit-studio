import Foundation

/// A single named connection point on a cell's interface.
public struct CellPort: Sendable, Codable, Equatable, Identifiable {
    /// SPICE-safe port name (e.g. "IN", "OUT", "VDD"). Doubles as the net
    /// name inside the cell body and the node name on the `.subckt` line.
    public let name: String
    public let direction: PortDirection

    public var id: String { name }

    public init(name: String, direction: PortDirection) {
        self.name = name
        self.direction = direction
    }
}
