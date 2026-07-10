import Foundation
import CircuitStudioCore
import CircuitPhysicalDesign
import LayoutEngine

struct LayoutGenerationCellSnapshot: Sendable, Codable, Equatable {
    let name: String
    let isTop: Bool
    let isActive: Bool
    let availability: CircuitLayoutAvailability
    let layoutHasContent: Bool
    let components: Int
    let wires: Int
    let labels: Int
    let placeable: Int
    let nonPhysical: Int
    let unsupportedPhysical: Int
    let hierarchical: Int
    let unknown: Int
    let duplicateNames: [String]
    let componentNames: [String]
    let devices: [LayoutGenerationDeviceSnapshot]
    let schematic: LayoutGenerationFileSnapshot
    let layout: LayoutGenerationFileSnapshot
    let pathResolutionFailures: [LayoutGenerationPathResolutionFailure]

    @MainActor
    static func capture(
        cell: CellWorkspace,
        topCellName: String,
        activeCellName: String,
        source: LayoutGenerationSourceSnapshot?,
        projectRootURL: URL?,
        projectService: ProjectService,
        catalog: DeviceCatalog,
        layoutEngineCatalog: any LayoutEngineCataloging = CircuitPhysicalDesignDefaults.layoutEngineCatalog()
    ) -> LayoutGenerationCellSnapshot {
        let document = cell.schematicViewModel.document
        let availability = CircuitLayoutAvailability.evaluate(
            document: document,
            catalog: catalog,
            deviceCellEngines: layoutEngineCatalog,
            activeCellName: cell.name
        )
        let resolvedAvailability = appSourceAvailability(
            base: availability,
            source: cell.name == activeCellName ? source : nil,
            cellName: cell.name
        )
        let components = document.components
        let duplicateNames = CircuitLayoutAvailability.duplicatedComponentNames(in: components)
        let unknownComponents = components.filter { catalog.device(for: $0.deviceKindID) == nil }
        let hierarchicalComponents = components.filter { $0.cellName != nil }
        let placeableComponents = components.filter { component in
            guard let kind = catalog.device(for: component.deviceKindID) else { return false }
            return CircuitLayoutAvailability.hasLayoutGenerator(
                kind,
                deviceCellEngines: layoutEngineCatalog
            )
        }
        let unsupportedPhysicalComponents = components.filter { component in
            guard let kind = catalog.device(for: component.deviceKindID) else { return false }
            return CircuitLayoutAvailability.requiresLayoutGenerator(kind)
                && !CircuitLayoutAvailability.hasLayoutGenerator(
                    kind,
                    deviceCellEngines: layoutEngineCatalog
                )
        }
        let nonPhysicalComponents = components.filter { component in
            guard let kind = catalog.device(for: component.deviceKindID) else { return false }
            return !CircuitLayoutAvailability.requiresLayoutGenerator(kind)
                && !CircuitLayoutAvailability.hasLayoutGenerator(
                    kind,
                    deviceCellEngines: layoutEngineCatalog
                )
        }
        var pathResolutionFailures: [LayoutGenerationPathResolutionFailure] = []
        let schematicURL = projectRootURL.flatMap { projectRoot in
            resolvedURL(key: "\(cell.name).schematic", failures: &pathResolutionFailures) {
                try projectService.cellSchematicURL(cellName: cell.name, inProjectAt: projectRoot)
            }
        }
        let layoutURL = projectRootURL.flatMap { projectRoot in
            resolvedURL(key: "\(cell.name).layout", failures: &pathResolutionFailures) {
                try projectService.cellLayoutDocumentURL(cellName: cell.name, inProjectAt: projectRoot)
            }
        }

        return LayoutGenerationCellSnapshot(
            name: cell.name,
            isTop: cell.name == topCellName,
            isActive: cell.name == activeCellName,
            availability: resolvedAvailability,
            layoutHasContent: cell.layoutHasContent,
            components: components.count,
            wires: document.wires.count,
            labels: document.labels.count,
            placeable: placeableComponents.count,
            nonPhysical: nonPhysicalComponents.count,
            unsupportedPhysical: unsupportedPhysicalComponents.count,
            hierarchical: hierarchicalComponents.count,
            unknown: unknownComponents.count,
            duplicateNames: duplicateNames,
            componentNames: components.map(\.name).sorted(),
            devices: components.map { component in
                let kind = catalog.device(for: component.deviceKindID)
                return LayoutGenerationDeviceSnapshot(
                    name: component.name,
                    deviceKindID: component.deviceKindID,
                    category: kind?.category.rawValue ?? "unknown",
                    hasLayoutGenerator: CircuitLayoutAvailability.hasLayoutGenerator(
                        kind,
                        deviceCellEngines: layoutEngineCatalog
                    ),
                    cellName: component.cellName
                )
            },
            schematic: .capture(schematicURL),
            layout: .capture(layoutURL),
            pathResolutionFailures: pathResolutionFailures
        )
    }

    private static func appSourceAvailability(
        base: CircuitLayoutAvailability,
        source: LayoutGenerationSourceSnapshot?,
        cellName: String
    ) -> CircuitLayoutAvailability {
        guard let source else { return base }
        let loadedNetlistName = source.topNetlist.exists
            ? (source.topNetlist.fileName ?? "top.cir")
            : (source.loadedNetlist.fileName ?? "SPICE netlist")
        if source.topNetlist.exists, !source.activeCellSchematic.exists {
            if let materialization = source.netlistMaterialization,
               materialization.status == .failed {
                return unavailable(
                    code: .netlistMaterializationFailed,
                    "Cell '\(cellName)' has no materialized schematic because \(loadedNetlistName) could not be imported: \(materialization.message ?? "unknown failure").",
                    help: "Fix the SPICE import issue or create cells/\(cellName)/schematic.json before generating layout."
                )
            }
            return unavailable(
                code: .missingMaterializedSchematic,
                "\(loadedNetlistName) is loaded, but cells/\(cellName)/schematic.json is missing.",
                help: "Layout generation needs a persisted schematic cell so the editor, CLI, and generated artifacts share the same canonical input."
            )
        }
        if source.projectRoot.path == nil,
           source.loadedNetlist.exists,
           base.code == .emptySchematic {
            return unavailable(
                code: .missingMaterializedSchematic,
                "\(loadedNetlistName) is loaded, but no schematic has been materialized.",
                help: "Layout generation needs a materialized schematic cell before physical design can start."
            )
        }
        return base
    }

    private static func unavailable(
        code: CircuitLayoutAvailabilityFailureCode,
        _ reason: String,
        help: String
    ) -> CircuitLayoutAvailability {
        CircuitLayoutAvailability(isAvailable: false, code: code, reason: reason, help: reason + " " + help)
    }

    private static func resolvedURL(
        key: String,
        failures: inout [LayoutGenerationPathResolutionFailure],
        _ makeURL: () throws -> URL
    ) -> URL? {
        do {
            return try makeURL()
        } catch {
            failures.append(LayoutGenerationPathResolutionFailure(
                key: key,
                message: error.localizedDescription
            ))
            return nil
        }
    }
}
