import Foundation
import CoreGraphics

/// Reference to a specific port on a specific component.
public struct PinReference: Sendable, Hashable, Codable {
    /// The UUID of the PlacedComponent.
    public let componentID: UUID
    /// The port ID from DeviceKind.PortDefinition (e.g. "pos", "neg", "drain").
    public let portID: String

    public init(componentID: UUID, portID: String) {
        self.componentID = componentID
        self.portID = portID
    }
}

/// A wire connecting two points on the schematic.
public struct Wire: Sendable, Identifiable, Codable {
    public let id: UUID
    public var startPoint: CGPoint
    public var endPoint: CGPoint
    /// Pin connected at start point, nil if free end.
    public var startPin: PinReference?
    /// Pin connected at end point, nil if free end.
    public var endPin: PinReference?
    public var netName: String?

    public init(
        id: UUID = UUID(),
        startPoint: CGPoint,
        endPoint: CGPoint,
        startPin: PinReference? = nil,
        endPin: PinReference? = nil,
        netName: String? = nil
    ) {
        self.id = id
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.startPin = startPin
        self.endPin = endPin
        self.netName = netName
    }
}

/// A net label placed on the schematic.
public struct NetLabel: Sendable, Identifiable, Codable {
    public let id: UUID
    public var name: String
    public var position: CGPoint

    public init(id: UUID = UUID(), name: String, position: CGPoint) {
        self.id = id
        self.name = name
        self.position = position
    }
}
