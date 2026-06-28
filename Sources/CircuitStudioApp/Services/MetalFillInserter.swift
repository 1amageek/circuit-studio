import Foundation
import LayoutCore

/// Raises a layer's area coverage into its density window by tiling fill geometry across the
/// cell. Foundry CMP needs a minimum metal density; sparse routing must be padded with
/// electrically-inert fill squares. This inserts a regular grid of `fillSize` squares on
/// `pitch` over the cell's extent (the grid keeps `pitch - fillSize` spacing so the fill is
/// not shorted into one slab), then the REAL density is re-measured by Magic — the inserter
/// adds geometry, the tool scores it.
public struct MetalFillInserter: Sendable {

    public struct Config: Sendable, Hashable {
        public let layerID: LayoutLayerID
        public let fillSize: Double     // fill square side (µm)
        public let pitch: Double        // grid pitch (µm); must exceed fillSize to keep spacing

        public init(layerID: LayoutLayerID, fillSize: Double, pitch: Double) {
            self.layerID = layerID
            self.fillSize = fillSize
            self.pitch = pitch
        }

        @available(*, deprecated, message: "Use init(layerID:fillSize:pitch:) with a profile-resolved layer.")
        public init(layerName: String, fillSize: Double, pitch: Double) {
            self.layerID = LayoutTechnologyResource.layer(layerName)
            self.fillSize = fillSize
            self.pitch = pitch
        }

        /// The fill density this grid contributes where it tiles (fillSize² / pitch²).
        public var gridDensity: Double { pitch > 0 ? (fillSize * fillSize) / (pitch * pitch) : 0 }
    }

    public init() {}

    /// Insert fill on the top cell of `document` over `region` (defaults to the cell's shape
    /// bounding box). Returns the augmented document. The fill is plain inert geometry on the
    /// configured layer; it carries no net.
    public func fill(_ document: LayoutDocument, region: LayoutRect? = nil, config: Config) -> LayoutDocument {
        var doc = document
        guard let topIndex = topCellIndex(in: doc) else { return doc }
        let cell = doc.cells[topIndex]
        guard let area = region ?? boundingBox(of: cell) else { return doc }

        let layer = config.layerID
        var fills: [LayoutShape] = []
        var y = area.minY
        while y + config.fillSize <= area.maxY {
            var x = area.minX
            while x + config.fillSize <= area.maxX {
                fills.append(LayoutShape(
                    layer: layer,
                    geometry: .rect(LayoutRect(
                        origin: LayoutPoint(x: x, y: y),
                        size: LayoutSize(width: config.fillSize, height: config.fillSize)))))
                x += config.pitch
            }
            y += config.pitch
        }

        doc.cells[topIndex].shapes.append(contentsOf: fills)
        return doc
    }

    private func topCellIndex(in document: LayoutDocument) -> Int? {
        if let topID = document.topCellID, let idx = document.cells.firstIndex(where: { $0.id == topID }) {
            return idx
        }
        return document.cells.isEmpty ? nil : 0
    }

    /// The bounding box of all rectangular shapes in the cell, or nil if it has none.
    private func boundingBox(of cell: LayoutCell) -> LayoutRect? {
        var box: LayoutRect? = nil
        for shape in cell.shapes {
            guard case let .rect(rect) = shape.geometry else { continue }
            box = box.map { $0.union(rect) } ?? rect
        }
        return box
    }
}
