import Foundation

/// Persisted schematic placement stored in `.xcircuite/schematic-placement.json`.
public struct SchematicPlacement: Sendable, Codable {
    public var version: Int
    public var sourceNetlist: String
    public var document: SchematicDocument

    public init(
        version: Int = 1,
        sourceNetlist: String = "",
        document: SchematicDocument = SchematicDocument()
    ) {
        self.version = version
        self.sourceNetlist = sourceNetlist
        self.document = document
    }
}
