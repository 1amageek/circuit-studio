import Foundation
import LayoutCore

struct ConnectivityElement: Sendable, Hashable {
    let layer: LayoutLayerID
    let geometry: LayoutGeometry
    let terminal: TerminalKey?
    let netID: UUID?
    let isVia: Bool
    let viaDefinitionID: String?
    let viaTopLayer: LayoutLayerID?
    let viaBottomLayer: LayoutLayerID?
    let externalPortName: String?
}
