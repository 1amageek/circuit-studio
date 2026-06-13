import Foundation
import CircuitStudioCore

struct LayoutGenerationCellSnapshot: Sendable, Codable, Equatable {
    let name: String
    let isTop: Bool
    let isActive: Bool
    let availability: LayoutGenerationAvailability
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

    @MainActor
    static func capture(
        cell: CellWorkspace,
        topCellName: String,
        activeCellName: String,
        source: LayoutGenerationSourceSnapshot?,
        projectRootURL: URL?,
        projectService: ProjectService,
        catalog: DeviceCatalog
    ) -> LayoutGenerationCellSnapshot {
        let document = cell.schematicViewModel.document
        let availability = LayoutGenerationAvailability.evaluate(
            document: document,
            catalog: catalog,
            activeCellName: cell.name,
            source: cell.name == activeCellName ? source : nil
        )
        let components = document.components
        let duplicateNames = LayoutGenerationAvailability.duplicatedComponentNames(in: components)
        let unknownComponents = components.filter { catalog.device(for: $0.deviceKindID) == nil }
        let hierarchicalComponents = components.filter { $0.cellName != nil }
        let placeableComponents = components.filter { component in
            guard let kind = catalog.device(for: component.deviceKindID) else { return false }
            return LayoutGenerationAvailability.hasLayoutGenerator(kind)
        }
        let unsupportedPhysicalComponents = components.filter { component in
            guard let kind = catalog.device(for: component.deviceKindID) else { return false }
            return LayoutGenerationAvailability.requiresLayoutGenerator(kind)
                && !LayoutGenerationAvailability.hasLayoutGenerator(kind)
        }
        let nonPhysicalComponents = components.filter { component in
            guard let kind = catalog.device(for: component.deviceKindID) else { return false }
            return !LayoutGenerationAvailability.requiresLayoutGenerator(kind)
                && !LayoutGenerationAvailability.hasLayoutGenerator(kind)
        }
        let schematicURL = projectRootURL.flatMap {
            try? projectService.cellSchematicURL(cellName: cell.name, inProjectAt: $0)
        }
        let layoutURL = projectRootURL.flatMap {
            try? projectService.cellLayoutDocumentURL(cellName: cell.name, inProjectAt: $0)
        }

        return LayoutGenerationCellSnapshot(
            name: cell.name,
            isTop: cell.name == topCellName,
            isActive: cell.name == activeCellName,
            availability: availability,
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
                    hasLayoutGenerator: LayoutGenerationAvailability.hasLayoutGenerator(kind),
                    cellName: component.cellName
                )
            },
            schematic: .capture(schematicURL),
            layout: .capture(layoutURL)
        )
    }
}
