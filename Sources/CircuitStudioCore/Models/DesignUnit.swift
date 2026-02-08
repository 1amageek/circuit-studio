import Foundation

/// 1:1 binding between a schematic circuit and its physical layout.
///
/// Maps schematic component IDs to layout instance IDs, net names to layout net IDs,
/// and device kind IDs to their generated layout cell IDs.
public struct DesignUnit: Sendable, Codable {
    /// PlacedComponent.id → LayoutInstance.id
    public var componentToInstance: [UUID: UUID]

    /// ExtractedNet.name → LayoutNet.id
    public var netNameToLayoutNet: [String: UUID]

    /// deviceKindID → LayoutCell.id
    public var deviceKindToCell: [String: UUID]

    /// Hash of the schematic state when this unit was generated.
    /// Used to detect when the schematic has changed and the layout is stale.
    public var schematicHash: Int

    public init(
        componentToInstance: [UUID: UUID] = [:],
        netNameToLayoutNet: [String: UUID] = [:],
        deviceKindToCell: [String: UUID] = [:],
        schematicHash: Int = 0
    ) {
        self.componentToInstance = componentToInstance
        self.netNameToLayoutNet = netNameToLayoutNet
        self.deviceKindToCell = deviceKindToCell
        self.schematicHash = schematicHash
    }

    /// Computes a hash of the schematic document state for staleness detection.
    public static func schematicHash(for doc: SchematicDocument) -> Int {
        var hasher = Hasher()
        hasher.combine(doc.components.count)
        for comp in doc.components {
            hasher.combine(comp.id)
            hasher.combine(comp.deviceKindID)
            hasher.combine(comp.name)
            for (key, value) in comp.parameters.sorted(by: { $0.key < $1.key }) {
                hasher.combine(key)
                hasher.combine(value)
            }
        }
        hasher.combine(doc.wires.count)
        for wire in doc.wires {
            hasher.combine(wire.id)
        }
        return hasher.finalize()
    }
}
