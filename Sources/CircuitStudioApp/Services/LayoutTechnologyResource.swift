import Foundation
import LayoutCore
import LayoutTech

public enum LayoutTechnologyResourceError: Error, Sendable, Hashable {
    case missingBundledResource(String)
}

public enum LayoutTechnologyResource {
    public static func layer(_ name: String, purpose: String? = nil) -> LayoutLayerID {
        LayoutLayerID(name: name, purpose: purpose ?? defaultPurpose(for: name))
    }

    public static func load(from url: URL) throws -> LayoutTechDatabase {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LayoutTechDatabase.self, from: data)
    }

    public static func bundled(resourceName: String) throws -> LayoutTechDatabase {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw LayoutTechnologyResourceError.missingBundledResource(resourceName)
        }
        return try load(from: url)
    }

    private static func defaultPurpose(for name: String) -> String {
        name.contains("con") ? "cut" : "drawing"
    }
}
