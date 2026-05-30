import Foundation
import LayoutCore

/// A generator for a Sky130 standard cell: it produces the cell LAYOUT in the layout IR
/// and the matching reference SCHEMATIC whose named ports correspond to the layout's
/// labeled-net ports. The signoff service synthesizes and verifies any conforming cell
/// uniformly, so adding a new cell type is just a new conformer — no signoff changes.
public protocol Sky130CellGenerator: Sendable {
    /// The generated cell layout on the Sky130 tech.
    func generate(name: String) -> LayoutDocument
    /// The reference schematic; its `.subckt` ports match the layout's labeled-net ports
    /// by name, so Netgen matches ports by name.
    func schematic(name: String) -> String
}
