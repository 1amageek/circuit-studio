import Foundation
import CoreGraphics

/// A placed component on the schematic canvas.
public struct PlacedComponent: Sendable, Identifiable {
    public let id: UUID
    /// Key into DeviceCatalog (e.g. "resistor", "nmos_l1").
    public var deviceKindID: String
    /// Instance name (e.g. "R1", "M2").
    public var name: String
    public var position: CGPoint
    /// Rotation in degrees.
    public var rotation: Double
    /// Flip across horizontal axis.
    public var mirrorX: Bool
    /// Flip across vertical axis.
    public var mirrorY: Bool
    /// Parameter values keyed by ParameterSchema.id.
    public var parameters: [String: Double]

    public init(
        id: UUID = UUID(),
        deviceKindID: String,
        name: String,
        position: CGPoint,
        rotation: Double = 0,
        mirrorX: Bool = false,
        mirrorY: Bool = false,
        parameters: [String: Double] = [:]
    ) {
        self.id = id
        self.deviceKindID = deviceKindID
        self.name = name
        self.position = position
        self.rotation = rotation
        self.mirrorX = mirrorX
        self.mirrorY = mirrorY
        self.parameters = parameters
    }
}

/// The full state of a schematic canvas.
public struct SchematicDocument: Sendable {
    public var components: [PlacedComponent]
    public var wires: [Wire]
    public var labels: [NetLabel]
    public var selection: Set<UUID>

    public init(
        components: [PlacedComponent] = [],
        wires: [Wire] = [],
        labels: [NetLabel] = [],
        selection: Set<UUID> = []
    ) {
        self.components = components
        self.wires = wires
        self.labels = labels
        self.selection = selection
    }
}
