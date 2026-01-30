import Foundation
import CoreGraphics

/// A circuit design containing components and their interconnections.
/// Retained for file serialization and interoperability.
public struct Design: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var components: [Component]
    public var nets: [Net]
    public var parameters: [String: Double]
    public var subcircuits: [Subcircuit]

    public init(
        id: UUID = UUID(),
        name: String,
        components: [Component] = [],
        nets: [Net] = [],
        parameters: [String: Double] = [:],
        subcircuits: [Subcircuit] = []
    ) {
        self.id = id
        self.name = name
        self.components = components
        self.nets = nets
        self.parameters = parameters
        self.subcircuits = subcircuits
    }
}

/// A placed circuit component (resistor, source, etc.).
public struct Component: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var typeName: String
    public var pins: [Pin]
    public var parameters: [String: Double]
    public var position: CGPoint
    public var rotation: Double

    public init(
        id: UUID = UUID(),
        name: String,
        typeName: String,
        pins: [Pin] = [],
        parameters: [String: Double] = [:],
        position: CGPoint = .zero,
        rotation: Double = 0
    ) {
        self.id = id
        self.name = name
        self.typeName = typeName
        self.pins = pins
        self.parameters = parameters
        self.position = position
        self.rotation = rotation
    }
}

/// A pin on a component.
public struct Pin: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var netID: UUID?

    public init(id: UUID = UUID(), name: String, netID: UUID? = nil) {
        self.id = id
        self.name = name
        self.netID = netID
    }
}

/// Reference to a specific pin on a specific component.
public struct PinRef: Sendable, Codable, Hashable {
    public var componentID: UUID
    public var pinID: UUID

    public init(componentID: UUID, pinID: UUID) {
        self.componentID = componentID
        self.pinID = pinID
    }
}

/// A net connecting multiple component pins.
public struct Net: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var connections: [PinRef]

    public init(id: UUID = UUID(), name: String, connections: [PinRef] = []) {
        self.id = id
        self.name = name
        self.connections = connections
    }
}

/// A subcircuit definition within a design.
public struct Subcircuit: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var ports: [String]
    public var components: [Component]
    public var nets: [Net]

    public init(
        id: UUID = UUID(),
        name: String,
        ports: [String] = [],
        components: [Component] = [],
        nets: [Net] = []
    ) {
        self.id = id
        self.name = name
        self.ports = ports
        self.components = components
        self.nets = nets
    }
}
