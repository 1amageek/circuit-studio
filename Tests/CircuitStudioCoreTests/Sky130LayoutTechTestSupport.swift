import Foundation
import LayoutCore
import LayoutTech
@testable import CircuitStudioApp

enum Sky130LayoutTech {
    static func resourceName() throws -> String {
        let entry = try defaultEntry()
        guard let resourceName = entry.technologyResourceName else {
            throw LayoutTechnologyCatalogError.missingTechnologyResource(entry.technologyID)
        }
        return resourceName
    }

    static func routingProfileResourceName() throws -> String {
        let entry = try defaultEntry()
        guard let resourceName = entry.routingProfileResourceName else {
            throw LayoutTechnologyCatalogError.missingTechnologyResource(entry.technologyID)
        }
        return resourceName
    }

    static func layer(_ name: String) -> LayoutLayerID {
        LayoutTechnologyCatalog.defaultLayer(name)
    }

    static func loadTech() throws -> LayoutTechDatabase {
        try LayoutTechnologyCatalog.loadDefaultTechnology()
    }

    static func tech() throws -> LayoutTechDatabase {
        try loadTech()
    }

    private static func defaultEntry() throws -> LayoutTechnologyCatalog.Entry {
        try LayoutTechnologyCatalog.defaultEntry()
    }
}
