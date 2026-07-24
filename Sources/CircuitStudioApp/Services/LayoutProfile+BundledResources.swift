import CircuitPhysicalDesign
import Foundation

public extension LayoutRoutingProfile {
    static func bundled(resourceName: String) throws -> LayoutRoutingProfile {
        guard let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: "json"
        ) else {
            throw LayoutRoutingProfileError.missingBundledResource(resourceName)
        }
        return try load(from: url)
    }
}

public extension LayoutTechnologyTranslationProfile {
    static func bundled(
        resourceName: String
    ) throws -> LayoutTechnologyTranslationProfile {
        guard let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: "json"
        ) else {
            throw LayoutTechnologyTranslationProfileError.missingBundledResource(
                resourceName
            )
        }
        return try load(from: url)
    }
}
