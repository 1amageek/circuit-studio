import Foundation

/// Errors raised by the auto-layout pipeline before any geometry is produced.
public enum AutoLayoutError: Error, Equatable, LocalizedError {
    /// The schematic instantiates a project cell. Hierarchical layout
    /// generation (block instantiation + interface pin placement) is not
    /// implemented yet, and silently flattening or skipping the instance
    /// would produce a layout that does not match the schematic.
    case hierarchicalCellsUnsupported(instanceNames: [String])
    /// A placed component references a device kind the catalog cannot
    /// resolve, so no cell generator can be chosen for it.
    case unknownDeviceKind(instanceName: String, deviceKindID: String)

    public var errorDescription: String? {
        switch self {
        case .hierarchicalCellsUnsupported(let instanceNames):
            return "Hierarchical layout generation is not yet supported. "
                + "The schematic instantiates project cells: "
                + instanceNames.joined(separator: ", ")
                + ". Generate layout from a leaf cell, or flatten the design first."
        case .unknownDeviceKind(let instanceName, let deviceKindID):
            return "Component '\(instanceName)' references unknown device kind "
                + "'\(deviceKindID)' — the catalog cannot resolve a layout generator for it."
        }
    }
}
