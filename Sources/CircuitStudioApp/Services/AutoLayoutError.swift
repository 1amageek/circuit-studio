import Foundation

/// Errors raised by the auto-layout pipeline before any geometry is produced.
public enum AutoLayoutError: Error, Equatable, LocalizedError {
    /// The schematic instantiates a project cell. Hierarchical layout
    /// generation (block instantiation + interface pin placement) is not
    /// implemented yet, and silently flattening or skipping the instance
    /// would produce a layout that does not match the schematic.
    case hierarchicalCellsUnsupported(instanceNames: [String])
    /// Duplicate instance names would make schematic-to-layout instance
    /// binding ambiguous after generation.
    case duplicateComponentNames([String])
    /// A placed component references a device kind the catalog cannot
    /// resolve, so no cell generator can be chosen for it.
    case unknownDeviceKind(instanceName: String, deviceKindID: String)
    /// A catalog device is physical, but this auto-layout pipeline has no
    /// primitive cell generator for it yet.
    case unsupportedLayoutDevice(instanceName: String, deviceKindID: String)
    /// The schematic has no primitive devices that produce physical geometry.
    case noPlaceableComponents

    public var errorDescription: String? {
        switch self {
        case .hierarchicalCellsUnsupported(let instanceNames):
            return "Hierarchical layout generation is not yet supported. "
                + "The schematic instantiates project cells: "
                + instanceNames.joined(separator: ", ")
                + ". Generate layout from a leaf cell, or flatten the design first."
        case .duplicateComponentNames(let names):
            return "Component names must be unique before layout generation. Rename: "
                + names.joined(separator: ", ")
                + "."
        case .unknownDeviceKind(let instanceName, let deviceKindID):
            return "Component '\(instanceName)' references unknown device kind "
                + "'\(deviceKindID)' — the catalog cannot resolve a layout generator for it."
        case .unsupportedLayoutDevice(let instanceName, let deviceKindID):
            return "Component '\(instanceName)' uses device kind '\(deviceKindID)', "
                + "but automatic layout has no cell generator for that physical device."
        case .noPlaceableComponents:
            return "The schematic has no components that produce physical layout geometry."
        }
    }
}
