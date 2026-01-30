import Foundation
import CoreGraphics

/// Drawing commands for symbol rendering.
public enum DrawCommand: Sendable {
    case line(from: CGPoint, to: CGPoint)
    case rect(origin: CGPoint, size: CGSize)
    case circle(center: CGPoint, radius: CGFloat)
    case arc(center: CGPoint, radius: CGFloat, startAngle: Double, endAngle: Double)
    case text(String, at: CGPoint, fontSize: CGFloat)
}

/// Device category for grouping in the component palette.
public enum DeviceCategory: String, Sendable, CaseIterable {
    case passive
    case source
    case semiconductor
    case controlled
    case special
}

/// A port (pin) definition on a device, with position in symbol-local coordinates.
public struct PortDefinition: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let position: CGPoint

    public init(id: String, displayName: String, position: CGPoint) {
        self.id = id
        self.displayName = displayName
        self.position = position
    }
}

/// Schema for a single device parameter, driving the property inspector UI.
public struct ParameterSchema: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let unit: String
    public let defaultValue: Double?
    public let range: ClosedRange<Double>?
    public let isRequired: Bool
    /// When true, this parameter belongs in the `.model` card rather than the instance line.
    public let isModelParameter: Bool

    public init(
        id: String,
        displayName: String,
        unit: String,
        defaultValue: Double? = nil,
        range: ClosedRange<Double>? = nil,
        isRequired: Bool = false,
        isModelParameter: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.unit = unit
        self.defaultValue = defaultValue
        self.range = range
        self.isRequired = isRequired
        self.isModelParameter = isModelParameter
    }
}

/// Shape of a circuit symbol.
public enum SymbolShape: Sendable {
    /// Hand-drawn symbol using draw commands (R, C, L, V, I, etc.)
    case custom([DrawCommand])
    /// IC package with auto-laid-out pins.
    case ic(width: CGFloat, height: CGFloat)
}

/// Visual definition of a device symbol.
public struct SymbolDefinition: Sendable {
    public let shape: SymbolShape
    public let size: CGSize
    public let iconName: String

    public init(shape: SymbolShape, size: CGSize, iconName: String) {
        self.shape = shape
        self.size = size
        self.iconName = iconName
    }
}

/// Unified device definition combining electrical metadata (from CoreSpice DeviceDescriptor)
/// with visual symbol information for the schematic editor.
///
/// This is the single source of truth for what a device type looks like and how it behaves.
/// Adding a new device requires only adding a `DeviceKind` entry in `BuiltInDevices.swift`.
public struct DeviceKind: Sendable, Identifiable {
    /// Unique identifier matching CoreSpice `DeviceDescriptor.typeName`.
    public let id: String
    /// Human-readable display name (e.g. "Resistor", "NMOS Level 1").
    public let displayName: String
    /// Category for palette grouping.
    public let category: DeviceCategory
    /// SPICE netlist prefix (e.g. "R", "C", "M").
    public let spicePrefix: String
    /// SPICE `.model` card type keyword (e.g. "NMOS", "NPN", "D"). Nil for non-semiconductor devices.
    public let modelType: String?
    /// Ordered port definitions matching CoreSpice `DeviceDescriptor.portNames`.
    public let portDefinitions: [PortDefinition]
    /// Parameter schema for the property inspector.
    public let parameterSchema: [ParameterSchema]
    /// Visual symbol definition.
    public let symbol: SymbolDefinition

    public init(
        id: String,
        displayName: String,
        category: DeviceCategory,
        spicePrefix: String,
        modelType: String? = nil,
        portDefinitions: [PortDefinition],
        parameterSchema: [ParameterSchema],
        symbol: SymbolDefinition
    ) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.spicePrefix = spicePrefix
        self.modelType = modelType
        self.portDefinitions = portDefinitions
        self.parameterSchema = parameterSchema
        self.symbol = symbol
    }
}
