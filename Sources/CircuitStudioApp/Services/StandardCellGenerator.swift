import Foundation
import LayoutCore

/// A generator for a standard cell: it produces the cell layout in the layout IR
/// and the matching reference schematic whose named ports correspond to the
/// layout's labeled-net ports.
public protocol StandardCellGenerator: Sendable {
    /// The generated cell layout on the selected technology profile.
    func generate(name: String) throws -> LayoutDocument

    /// The reference schematic; its `.subckt` ports match the layout's
    /// labeled-net ports by name, so LVS tools can match ports by name.
    func schematic(name: String) throws -> String
}
