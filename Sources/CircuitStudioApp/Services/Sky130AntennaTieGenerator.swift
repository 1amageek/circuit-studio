import Foundation
import LayoutCore

public struct Sky130AntennaTieGenerator: Sendable {
    public static let protectionProperty = "layout.antenna.protection"
    public static let strategyProperty = "layout.antenna.strategy"
    public static let netNameProperty = "layout.net.name"
    public static let siteIDProperty = "layout.antenna.siteID"
    public static let instanceNameProperty = "layout.antenna.instance"
    public static let gateNameProperty = "layout.antenna.gate"

    public init() {}

    public func shapes(
        for site: AntennaProtectionPlan.Site,
        baseY: Double = 0.0
    ) -> [LayoutShape] {
        let fieldY = Sky130StandardCellSynthesizer.CellLayout.fieldY
        let centerX = site.centerXMicrons
        let trackY = site.trackYMicrons
        return [
            rect("li1", centerX - 0.165, fieldY - 0.165, 0.33, 0.33, site: site),
            rect("mcon", centerX - 0.085, fieldY - 0.085, 0.17, 0.17, site: site),
            rect("diff", centerX - 0.205, baseY, 0.41, 0.41, site: site),
            rect("nsdm", centerX - 0.33, baseY - 0.125, 0.66, 0.66, site: site),
            rect("licon1", centerX - 0.085, baseY + 0.125, 0.17, 0.17, site: site),
            rect("li1", centerX - 0.165, baseY + 0.045, 0.33, 0.33, site: site),
            rect("mcon", centerX - 0.085, baseY + 0.125, 0.17, 0.17, site: site),
            rect("met1", centerX - 0.165, baseY + 0.045, 0.33, (trackY + 0.165) - (baseY + 0.045), site: site),
            rect("via", centerX - 0.075, trackY - 0.075, 0.15, 0.15, site: site),
        ]
    }

    private func rect(
        _ layer: String,
        _ x: Double,
        _ y: Double,
        _ w: Double,
        _ h: Double,
        site: AntennaProtectionPlan.Site
    ) -> LayoutShape {
        LayoutShape(
            layer: Sky130LayoutTech.layer(layer),
            geometry: .rect(LayoutRect(origin: LayoutPoint(x: x, y: y), size: LayoutSize(width: w, height: h))),
            properties: [
                Self.protectionProperty: "true",
                Self.strategyProperty: AntennaProtectionPlan.Strategy.diffusionTie.rawValue,
                Self.netNameProperty: site.net,
                Self.siteIDProperty: site.id,
                Self.instanceNameProperty: site.instanceName,
                Self.gateNameProperty: site.gateName,
            ]
        )
    }
}
