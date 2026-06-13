import Foundation
import CircuitStudioCore

enum LayoutGenerationFailureCode: String, Sendable, Codable, Equatable {
    case none
    case missingMaterializedSchematic
    case netlistMaterializationFailed
    case emptySchematic
    case duplicateComponentNames
    case hierarchicalCellsUnsupported
    case unknownDeviceKind
    case unsupportedPhysicalDevice
    case noPlaceableComponents
}

struct LayoutGenerationAvailability: Sendable, Codable, Equatable {
    let isAvailable: Bool
    let code: LayoutGenerationFailureCode
    let reason: String?
    let help: String

    static func evaluate(
        document: SchematicDocument,
        catalog: DeviceCatalog,
        activeCellName: String? = nil,
        source: LayoutGenerationSourceSnapshot? = nil
    ) -> LayoutGenerationAvailability {
        let cellName = activeCellName ?? "active cell"
        let cellDescription = "Cell '\(cellName)'"

        guard !document.components.isEmpty else {
            if let source {
                let loadedNetlistName = source.topNetlist.exists
                    ? (source.topNetlist.fileName ?? "top.cir")
                    : (source.selectedFile.fileName ?? "SPICE netlist")
                if let materialization = source.netlistMaterialization,
                   materialization.status == .failed {
                    return unavailable(
                        code: .netlistMaterializationFailed,
                        "\(cellDescription) has no materialized schematic because \(loadedNetlistName) could not be imported: \(materialization.message ?? "unknown failure").",
                        help: "Fix the SPICE import issue or create cells/\(cellName)/schematic.json before generating layout."
                    )
                }
                if source.topNetlist.exists, !source.activeCellSchematic.exists {
                    return unavailable(
                        code: .missingMaterializedSchematic,
                        "\(loadedNetlistName) is loaded, but cells/\(cellName)/schematic.json is missing.",
                        help: "Layout generation needs a materialized schematic cell. The project opened with a SPICE netlist but no visual schematic cell."
                    )
                }
                if source.projectRoot.path == nil, source.selectedFile.exists {
                    return unavailable(
                        code: .missingMaterializedSchematic,
                        "\(loadedNetlistName) is loaded, but no schematic has been materialized.",
                        help: "Layout generation needs a materialized schematic cell before physical design can start."
                    )
                }
            }

            return unavailable(
                code: .emptySchematic,
                "\(cellDescription) has no schematic components.",
                help: "Layout generation needs at least one physical schematic component."
            )
        }

        let duplicateNames = duplicatedComponentNames(in: document.components)
        if !duplicateNames.isEmpty {
            return unavailable(
                code: .duplicateComponentNames,
                "Component names must be unique before layout generation. Rename: \(duplicateNames.joined(separator: ", ")).",
                help: "Layout generation needs unique component names to bind schematic devices to layout instances."
            )
        }

        let hierarchicalComponents = document.components.filter { $0.cellName != nil }
        if !hierarchicalComponents.isEmpty {
            return unavailable(
                code: .hierarchicalCellsUnsupported,
                "Hierarchical layout generation is not supported for \(describe(hierarchicalComponents)). Open a leaf cell or flatten the design first.",
                help: "Generate layout from a leaf cell; hierarchical block layout is not available yet."
            )
        }

        for component in document.components {
            guard catalog.device(for: component.deviceKindID) != nil else {
                return unavailable(
                    code: .unknownDeviceKind,
                    "Component '\(component.name)' uses unknown device kind '\(component.deviceKindID)'.",
                    help: "Replace unknown components or add their device kind to the catalog before generating layout."
                )
            }
        }

        let unsupportedPhysicalComponents = document.components.filter { component in
            guard let kind = catalog.device(for: component.deviceKindID) else { return false }
            return requiresLayoutGenerator(kind) && !hasLayoutGenerator(kind)
        }
        if !unsupportedPhysicalComponents.isEmpty {
            let component = unsupportedPhysicalComponents[0]
            return unavailable(
                code: .unsupportedPhysicalDevice,
                "Layout generation does not have a cell generator for '\(component.name)' (\(component.deviceKindID)).",
                help: "Replace unsupported physical devices or add a layout cell generator before generating layout."
            )
        }

        let placeableComponents = document.components.filter { component in
            guard let kind = catalog.device(for: component.deviceKindID) else { return false }
            return hasLayoutGenerator(kind)
        }
        guard !placeableComponents.isEmpty else {
            return unavailable(
                code: .noPlaceableComponents,
                "\(cellDescription) only contains ports, sources, controlled sources, or reference symbols; add a passive or MOS device to generate physical geometry.",
                help: "Layout generation needs at least one device that produces physical geometry."
            )
        }

        if document.wires.isEmpty {
            return LayoutGenerationAvailability(
                isAvailable: true,
                code: .none,
                reason: nil,
                help: "Generate layout from physical devices. No schematic wires are present, so no signal routes will be created (Shift-Command-G)."
            )
        }

        return LayoutGenerationAvailability(
            isAvailable: true,
            code: .none,
            reason: nil,
            help: "Automatically place and route the schematic components into a physical layout, then run DRC (Shift-Command-G)."
        )
    }

    private static func unavailable(
        code: LayoutGenerationFailureCode,
        _ reason: String,
        help: String
    ) -> LayoutGenerationAvailability {
        LayoutGenerationAvailability(isAvailable: false, code: code, reason: reason, help: reason + " " + help)
    }

    static func duplicatedComponentNames(in components: [PlacedComponent]) -> [String] {
        var counts: [String: Int] = [:]
        for component in components {
            counts[component.name, default: 0] += 1
        }
        return counts
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()
    }

    private static func describe(_ components: [PlacedComponent]) -> String {
        let names = components.prefix(3).map { "'\($0.name)'" }.joined(separator: ", ")
        if components.count > 3 {
            return names + ", and \(components.count - 3) more"
        }
        return names
    }

    static func requiresLayoutGenerator(_ kind: DeviceKind) -> Bool {
        switch kind.category {
        case .passive, .semiconductor:
            return true
        case .source, .controlled, .special, .port, .cell:
            return false
        }
    }

    static func hasLayoutGenerator(_ kind: DeviceKind) -> Bool {
        if let modelType = kind.modelType, modelType == "NMOS" || modelType == "PMOS" {
            return true
        }
        switch kind.spicePrefix {
        case "R", "C", "M":
            return true
        default:
            return false
        }
    }

    static func hasLayoutGenerator(_ kind: DeviceKind?) -> Bool {
        guard let kind else { return false }
        return hasLayoutGenerator(kind)
    }
}
