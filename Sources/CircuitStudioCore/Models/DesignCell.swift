import Foundation

/// A named, reusable design unit: one schematic that other cells can
/// instantiate as a component.
///
/// Identity is by name — the same convention SPICE `.subckt` and GDS cells
/// use — so a cell renames consistently across netlists, layouts, and
/// project files.
public struct DesignCell: Sendable, Codable, Identifiable {
    public var name: String
    public var schematic: SchematicDocument

    public var id: String { name }

    public init(name: String, schematic: SchematicDocument = SchematicDocument()) {
        self.name = name
        self.schematic = schematic
    }

    /// Names of cells this cell instantiates, in placement order, deduplicated.
    public var referencedCellNames: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for component in schematic.components {
            guard let cellName = component.cellName else { continue }
            if seen.insert(cellName).inserted {
                result.append(cellName)
            }
        }
        return result
    }
}
