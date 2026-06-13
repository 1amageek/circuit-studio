import Foundation

/// A single named connection point on a cell's interface.
public struct CellPort: Sendable, Codable, Equatable, Identifiable {
    /// Stable identity of the port, decoupled from its name.
    ///
    /// This is the UUID of the port-marker component on the cell's
    /// schematic, so renaming the port (changing ``name``) leaves the
    /// identity untouched. Symbol pin IDs and the connectivity keys that
    /// parent wires reference are built from this, so a child-port rename
    /// never breaks the parent schematic's wiring.
    public let id: String
    /// SPICE-safe port name (e.g. "IN", "OUT", "VDD"). Doubles as the net
    /// name inside the cell body and the node name on the `.subckt` line.
    /// User-editable, so it must never serve as identity.
    public let name: String
    public let direction: PortDirection

    public init(id: String, name: String, direction: PortDirection) {
        self.id = id
        self.name = name
        self.direction = direction
    }
}
