import Foundation
import LayoutCore
import LayoutTech

public struct ProfiledInverterGenerator: StandardCellGenerator {
    private let profile: StandardCellLayoutProfile

    public init(profile: StandardCellLayoutProfile) {
        self.profile = profile
    }

    public func generate(name: String) -> LayoutDocument {
        generate(name: name, width: profile.inverter.defaultDeviceWidth)
    }

    public func schematic(name: String) -> String {
        schematic(name: name, width: profile.inverter.defaultDeviceWidth)
    }

    public func generate(name: String, width: Double) -> LayoutDocument {
        let layoutPolicy = profile.inverter
        let layers = profile.layers
        let deviceWidth = max(layoutPolicy.minimumDeviceWidth, width)
        let pmosBot = deviceWidth + layoutPolicy.pmosRowGap
        let pmosTop = pmosBot + deviceWidth
        let tapBot = pmosTop + layoutPolicy.wellTapGap
        let shapes: [LayoutShape] = [
            rect(layers.diffusion, 0.00, 0.00, layoutPolicy.activeLength, deviceWidth),
            rect(
                layers.nImplant,
                layoutPolicy.nImplantOriginX,
                layoutPolicy.nImplantOriginY,
                layoutPolicy.activeLength + layoutPolicy.implantHorizontalMargin,
                deviceWidth + layoutPolicy.implantVerticalMargin
            ),
            rect(
                layers.contactCut,
                layoutPolicy.sourceContactX,
                layoutPolicy.activeContactYInset,
                layoutPolicy.activeContactSize,
                layoutPolicy.activeContactSize
            ),
            rect(
                layers.contactCut,
                layoutPolicy.drainContactX,
                layoutPolicy.activeContactYInset,
                layoutPolicy.activeContactSize,
                layoutPolicy.activeContactSize
            ),
            rect(layers.diffusion, 0.00, pmosBot, layoutPolicy.activeLength, deviceWidth),
            rect(
                layers.pImplant,
                layoutPolicy.pImplantOriginX,
                pmosBot - layoutPolicy.activeContactYInset,
                layoutPolicy.activeLength + layoutPolicy.implantHorizontalMargin,
                deviceWidth + layoutPolicy.implantVerticalMargin
            ),
            rect(
                layers.contactCut,
                layoutPolicy.sourceContactX,
                pmosBot + layoutPolicy.activeContactYInset,
                layoutPolicy.activeContactSize,
                layoutPolicy.activeContactSize
            ),
            rect(
                layers.contactCut,
                layoutPolicy.drainContactX,
                pmosBot + layoutPolicy.activeContactYInset,
                layoutPolicy.activeContactSize,
                layoutPolicy.activeContactSize
            ),
            rect(
                layers.nWell,
                layoutPolicy.nWellOriginX,
                pmosBot - layoutPolicy.nWellBottomMargin,
                layoutPolicy.nWellWidth,
                (tapBot + layoutPolicy.wellTapDiffusionSize + layoutPolicy.nWellTopMargin)
                    - (pmosBot - layoutPolicy.nWellBottomMargin)
            ),
            rect(
                layers.gateConductor,
                layoutPolicy.gateX,
                layoutPolicy.gateBottomY,
                layoutPolicy.gateLength,
                (pmosTop + layoutPolicy.gateTopMargin) - layoutPolicy.gateBottomY
            ),
            rect(
                layers.localInterconnect,
                layoutPolicy.outputLocalInterconnect.x,
                layoutPolicy.outputLocalInterconnect.y,
                layoutPolicy.outputLocalInterconnect.width,
                (pmosBot + layoutPolicy.outputTopYOffset) - layoutPolicy.outputLocalInterconnect.y
            ),
            rect(
                layers.diffusion,
                layoutPolicy.substrateTapDiffusion.x,
                layoutPolicy.substrateTapDiffusion.y,
                layoutPolicy.substrateTapDiffusion.width,
                layoutPolicy.substrateTapDiffusion.height
            ),
            rect(
                layers.pImplant,
                layoutPolicy.substrateTapImplant.x,
                layoutPolicy.substrateTapImplant.y,
                layoutPolicy.substrateTapImplant.width,
                layoutPolicy.substrateTapImplant.height
            ),
            rect(
                layers.contactCut,
                layoutPolicy.substrateTapContact.x,
                layoutPolicy.substrateTapContact.y,
                layoutPolicy.substrateTapContact.width,
                layoutPolicy.substrateTapContact.height
            ),
            rect(
                layers.localInterconnect,
                layoutPolicy.substrateTapRail.x,
                layoutPolicy.substrateTapRail.y,
                layoutPolicy.substrateTapRail.width,
                layoutPolicy.substrateTapRailTopY - layoutPolicy.substrateTapRail.y
            ),
            rect(
                layers.diffusion,
                layoutPolicy.wellTapDiffusionX,
                tapBot,
                layoutPolicy.wellTapDiffusionSize,
                layoutPolicy.wellTapDiffusionSize
            ),
            rect(
                layers.nImplant,
                layoutPolicy.wellTapImplantX,
                tapBot + layoutPolicy.wellTapImplantBottomOffset,
                layoutPolicy.wellTapImplantSize,
                layoutPolicy.wellTapImplantSize
            ),
            rect(
                layers.contactCut,
                layoutPolicy.wellTapContactX,
                tapBot + layoutPolicy.wellTapContactYOffset,
                layoutPolicy.activeContactSize,
                layoutPolicy.activeContactSize
            ),
            rect(
                layers.localInterconnect,
                layoutPolicy.wellTapRailX,
                pmosBot + layoutPolicy.wellTapRailBottomYOffset,
                layoutPolicy.wellTapRailWidth,
                (tapBot + layoutPolicy.wellTapRailTopYOffset) - (pmosBot + layoutPolicy.wellTapRailBottomYOffset)
            ),
        ]
        var cell = LayoutCell(name: name, shapes: shapes)
        cell.labels = [
            label("A", .gateConductor, layoutPolicy.inputLabelX, deviceWidth + layoutPolicy.inputLabelYOffset),
            label("Y", .localInterconnect, layoutPolicy.outputLabelX, layoutPolicy.outputLabelY),
            label("VPWR", .localInterconnect, layoutPolicy.powerLabelX, pmosBot + layoutPolicy.powerLabelYOffset),
            label("VGND", .localInterconnect, layoutPolicy.groundLabelX, layoutPolicy.groundLabelY),
        ]
        return LayoutDocument(name: name, cells: [cell], topCellID: cell.id)
    }

    public func schematic(name: String, width: Double) -> String {
        let layoutPolicy = profile.inverter
        let models = profile.deviceModels
        let deviceWidth = Self.format(max(layoutPolicy.minimumDeviceWidth, width))
        let gateLength = Self.format(layoutPolicy.gateLength)
        return """
        * generated inverter reference
        .subckt \(name) A Y VPWR VGND
        X0 Y A VPWR VPWR \(models.pmos) w=\(deviceWidth) l=\(gateLength)
        X1 Y A VGND VGND \(models.nmos) w=\(deviceWidth) l=\(gateLength)
        .ends
        """
    }

    private func rect(
        _ layer: LayoutTechnologyLayerReference,
        _ x: Double,
        _ y: Double,
        _ w: Double,
        _ h: Double
    ) -> LayoutShape {
        LayoutShape(
            layer: LayoutLayerID(name: layer.name, purpose: layer.purpose),
            geometry: .rect(LayoutRect(origin: LayoutPoint(x: x, y: y), size: LayoutSize(width: w, height: h)))
        )
    }

    private func label(
        _ text: String,
        _ role: StandardCellLayoutProfile.LayerRole,
        _ x: Double,
        _ y: Double
    ) -> LayoutLabel {
        let layer = profile.labelLayerReference(for: role)
        return LayoutLabel(
            text: text,
            position: LayoutPoint(x: x, y: y),
            layer: LayoutLayerID(name: layer.name, purpose: layer.purpose)
        )
    }

    private static func format(_ value: Double) -> String {
        String(format: "%g", value)
    }
}
