import LayoutAutoGen
import LayoutTech
import LayoutVerify

/// Uses material roles exported by the actual generated device owner.
enum DeviceElectricalVerificationContext {
    static func select(tech: LayoutTechDatabase) -> LayoutElectricalContext {
        let poly = ResistorCellGenerator.polyLayerID, marker = ResistorCellGenerator.bodyMarkerLayerID
        if tech.layerDefinition(for: poly) != nil && tech.layerDefinition(for: marker) != nil {
            return .deviceAwareMOSAndPolyResistors(polyLayer: poly, bodyMarkerLayer: marker)
        }
        return .deviceAwareMOS
    }
}
