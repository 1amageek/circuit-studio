import LayoutCore

struct RawLayoutTerminal: Sendable, Hashable {
    let pinName: String
    let layer: LayoutLayerID
    let geometry: LayoutGeometry
}
