import Foundation
import LayoutCore

public struct ProfiledAntennaTieGenerator: Sendable {
    public static let protectionProperty = "layout.antenna.protection"
    public static let strategyProperty = "layout.antenna.strategy"
    public static let netNameProperty = "layout.net.name"
    public static let siteIDProperty = "layout.antenna.siteID"
    public static let instanceNameProperty = "layout.antenna.instance"
    public static let gateNameProperty = "layout.antenna.gate"

    private let profile: StandardCellLayoutProfile

    public init(profile: StandardCellLayoutProfile) {
        self.profile = profile
    }

    public func shapes(
        for site: AntennaProtectionPlan.Site,
        baseY: Double = 0.0
    ) -> [LayoutShape] {
        let layoutPolicy = profile.generatedCellLayout
        let fieldY = layoutPolicy.fieldY
        let centerX = site.centerXMicrons
        let trackY = site.trackYMicrons
        let localPadHalf = layoutPolicy.localInterconnectPadSize / 2
        let contactHalf = layoutPolicy.contactSize / 2
        let metalHalf = layoutPolicy.metalRiserWidth / 2
        let viaHalf = layoutPolicy.outputViaSize / 2
        let activeContactY = baseY + layoutPolicy.activeContactYInset
        let localPadY = activeContactY - layoutPolicy.localInterconnectPadInset

        return [
            rect(
                .localInterconnect,
                centerX - localPadHalf,
                fieldY - localPadHalf,
                layoutPolicy.localInterconnectPadSize,
                layoutPolicy.localInterconnectPadSize,
                site: site
            ),
            rect(
                .localInterconnectToMetalContact,
                centerX - contactHalf,
                fieldY - contactHalf,
                layoutPolicy.contactSize,
                layoutPolicy.contactSize,
                site: site
            ),
            rect(
                .diffusion,
                centerX - layoutPolicy.tapDiffusionSize / 2,
                baseY,
                layoutPolicy.tapDiffusionSize,
                layoutPolicy.tapDiffusionSize,
                site: site
            ),
            rect(
                .nImplant,
                centerX - layoutPolicy.tapImplantSize / 2,
                baseY - layoutPolicy.implantMargin,
                layoutPolicy.tapImplantSize,
                layoutPolicy.tapImplantSize,
                site: site
            ),
            rect(
                .contactCut,
                centerX - contactHalf,
                activeContactY,
                layoutPolicy.contactSize,
                layoutPolicy.contactSize,
                site: site
            ),
            rect(
                .localInterconnect,
                centerX - localPadHalf,
                localPadY,
                layoutPolicy.localInterconnectPadSize,
                layoutPolicy.localInterconnectPadSize,
                site: site
            ),
            rect(
                .localInterconnectToMetalContact,
                centerX - contactHalf,
                activeContactY,
                layoutPolicy.contactSize,
                layoutPolicy.contactSize,
                site: site
            ),
            rect(
                .metal1,
                centerX - metalHalf,
                localPadY,
                layoutPolicy.metalRiserWidth,
                (trackY + metalHalf) - localPadY,
                site: site
            ),
            rect(
                .metal1ToMetal2Via,
                centerX - viaHalf,
                trackY - viaHalf,
                layoutPolicy.outputViaSize,
                layoutPolicy.outputViaSize,
                site: site
            ),
        ]
    }

    private func rect(
        _ role: StandardCellLayoutProfile.LayerRole,
        _ x: Double,
        _ y: Double,
        _ w: Double,
        _ h: Double,
        site: AntennaProtectionPlan.Site
    ) -> LayoutShape {
        let reference = profile.layerReference(for: role)
        return LayoutShape(
            layer: LayoutLayerID(name: reference.name, purpose: reference.purpose),
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
