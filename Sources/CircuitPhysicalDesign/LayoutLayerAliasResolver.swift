import LayoutCore
import LayoutTech

struct LayoutLayerAliasResolver: Sendable, Hashable {
    private let aliasesBySemanticLayer: [LayoutSemanticLayer: Set<LayoutLayerID>]
    private let semanticLayerByAlias: [LayoutLayerID: LayoutSemanticLayer]

    init(tech: LayoutTechDatabase?) {
        var aliases: [LayoutSemanticLayer: Set<LayoutLayerID>] = [:]
        for semanticLayer in LayoutSemanticLayer.allCases {
            aliases[semanticLayer, default: []].insert(semanticLayer.canonicalID)
        }
        for layer in tech?.layers ?? [] {
            guard let semanticLayer = Self.semanticLayer(for: layer.id) else { continue }
            aliases[semanticLayer, default: []].insert(layer.id)
            aliases[semanticLayer, default: []].insert(LayoutLayerID(
                name: "L\(layer.gdsLayer)",
                purpose: "D\(layer.gdsDatatype)"
            ))
        }
        var reverse: [LayoutLayerID: LayoutSemanticLayer] = [:]
        for (semanticLayer, layerAliases) in aliases {
            for alias in layerAliases {
                reverse[alias] = semanticLayer
            }
        }
        self.aliasesBySemanticLayer = aliases
        self.semanticLayerByAlias = reverse
    }

    func matches(_ layer: LayoutLayerID, _ semanticLayer: LayoutSemanticLayer) -> Bool {
        if aliasesBySemanticLayer[semanticLayer, default: []].contains(layer) {
            return true
        }
        return Self.semanticLayer(for: layer) == semanticLayer
    }

    func normalize(_ layer: LayoutLayerID) -> LayoutLayerID {
        if let semanticLayer = semanticLayerByAlias[layer] {
            return semanticLayer.canonicalID
        }
        return Self.semanticLayer(for: layer)?.canonicalID ?? layer
    }

    private static func semanticLayer(for layer: LayoutLayerID) -> LayoutSemanticLayer? {
        let normalizedName = layer.name
            .uppercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return LayoutSemanticLayer.allCases.first { semanticLayer in
            semanticLayer.nameAliases.contains(normalizedName)
        }
    }
}
