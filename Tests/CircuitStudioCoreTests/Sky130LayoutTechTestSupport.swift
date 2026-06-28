import Foundation
import LayoutCore
import LayoutTech
@testable import CircuitStudioApp

enum Sky130LayoutTech {
    static var resourceName: String {
        defaultEntry.technologyResourceName ?? fail("Default layout technology has no technology resource.")
    }

    static var routingProfileResourceName: String {
        defaultEntry.routingProfileResourceName ?? fail("Default layout technology has no routing profile resource.")
    }

    static func layer(_ name: String) -> LayoutLayerID {
        LayoutTechnologyCatalog.defaultLayer(name)
    }

    static func loadTech() throws -> LayoutTechDatabase {
        try LayoutTechnologyCatalog.loadDefaultTechnology()
    }

    static func tech() -> LayoutTechDatabase {
        do {
            return try loadTech()
        } catch {
            preconditionFailure("Bundled layout technology could not be loaded: \(error)")
        }
    }

    private static var defaultEntry: LayoutTechnologyCatalog.Entry {
        do {
            return try LayoutTechnologyCatalog.defaultEntry()
        } catch {
            preconditionFailure("Bundled layout technology catalog could not be loaded: \(error)")
        }
    }

    private static func fail<T>(_ message: String) -> T {
        preconditionFailure(message)
    }
}
