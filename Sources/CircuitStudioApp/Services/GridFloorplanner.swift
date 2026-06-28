import Foundation
import LayoutCore

/// Tiles synthesized standard-cell blocks into a 2-D grid of rows and columns — the spatial
/// scale primitive that replaces one impossibly-wide row with a roughly-square array. Each
/// block is an independently DRC/LVS-clean layout (from `StandardCircuitSynthesizer`); the
/// floorplanner translates each block's geometry to its grid slot, separated by enough gap
/// that no inter-block rule is violated. Inter-block signal routing joins the grid into one
/// circuit; this step establishes legal placement.
public struct GridFloorplanner: Sendable {

    public enum FloorplanError: Error, LocalizedError, Equatable {
        case emptyGrid
        case nonRectangularGeometry

        public var errorDescription: String? {
            switch self {
            case .emptyGrid: return "The floorplan has no blocks to place."
            case .nonRectangularGeometry: return "A block produced non-rectangular geometry the floorplanner cannot translate."
            }
        }
    }

    /// One placed block plus the slot it occupies, for downstream inter-block routing.
    public struct Placement: Sendable, Hashable {
        public let blockName: String
        public let row: Int
        public let column: Int
        public let originX: Double
        public let originY: Double
        public let width: Double
        public let height: Double
    }

    public struct Floorplan: Sendable {
        public let document: LayoutDocument
        public let placements: [Placement]
    }

    private let columnGap: Double
    private let rowGap: Double

    /// Gaps default to >= the n-well spacing (1.27 µm) so adjacent blocks' wells never clash.
    public init(columnGap: Double = 1.6, rowGap: Double = 1.6) {
        self.columnGap = columnGap
        self.rowGap = rowGap
    }

    /// Tile `blocks` row-major into `columns` columns. Each block is one synthesized layout
    /// document (its top cell's shapes/labels are translated into the shared floorplan cell).
    public func tile(_ blocks: [LayoutDocument], columns: Int, name: String = "floorplan") throws -> Floorplan {
        guard !blocks.isEmpty, columns >= 1 else { throw FloorplanError.emptyGrid }

        // Per-block bounding boxes (to size each grid track to its widest/tallest member).
        let boxes = try blocks.map { try boundingBox(of: $0) }
        let rows = (blocks.count + columns - 1) / columns
        var columnWidth = [Double](repeating: 0, count: columns)
        var rowHeight = [Double](repeating: 0, count: rows)
        for (i, box) in boxes.enumerated() {
            let c = i % columns, r = i / columns
            columnWidth[c] = max(columnWidth[c], box.width)
            rowHeight[r] = max(rowHeight[r], box.height)
        }
        // Column/row origins (cumulative with gaps).
        var columnX = [Double](repeating: 0, count: columns)
        for c in 1..<max(columns, 1) { columnX[c] = columnX[c - 1] + columnWidth[c - 1] + columnGap }
        var rowY = [Double](repeating: 0, count: rows)
        for r in 1..<max(rows, 1) { rowY[r] = rowY[r - 1] + rowHeight[r - 1] + rowGap }

        var shapes: [LayoutShape] = []
        var labels: [LayoutLabel] = []
        var placements: [Placement] = []
        for (i, block) in blocks.enumerated() {
            let c = i % columns, r = i / columns
            let box = boxes[i]
            // Place each block at its slot's lower-left, normalizing the block's own origin.
            let dx = columnX[c] - box.minX
            let dy = rowY[r] - box.minY
            guard let cell = block.cells.first(where: { $0.id == block.topCellID }) ?? block.cells.first else { continue }
            for s in cell.shapes { shapes.append(try translate(s, dx: dx, dy: dy)) }
            for l in cell.labels {
                labels.append(LayoutLabel(text: l.text, position: LayoutPoint(x: l.position.x + dx, y: l.position.y + dy), layer: l.layer))
            }
            placements.append(Placement(blockName: block.name, row: r, column: c,
                                        originX: columnX[c], originY: rowY[r], width: box.width, height: box.height))
        }

        var cell = LayoutCell(name: name, shapes: shapes)
        cell.labels = labels
        return Floorplan(document: LayoutDocument(name: name, cells: [cell], topCellID: cell.id),
                         placements: placements)
    }

    // MARK: - geometry

    private struct Box { let minX, minY, width, height: Double }

    private func boundingBox(of document: LayoutDocument) throws -> Box {
        guard let cell = document.cells.first(where: { $0.id == document.topCellID }) ?? document.cells.first else {
            throw FloorplanError.emptyGrid
        }
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for s in cell.shapes {
            guard case let .rect(r) = s.geometry else { throw FloorplanError.nonRectangularGeometry }
            minX = min(minX, r.origin.x); minY = min(minY, r.origin.y)
            maxX = max(maxX, r.origin.x + r.size.width); maxY = max(maxY, r.origin.y + r.size.height)
        }
        guard minX.isFinite else { throw FloorplanError.emptyGrid }
        return Box(minX: minX, minY: minY, width: maxX - minX, height: maxY - minY)
    }

    private func translate(_ shape: LayoutShape, dx: Double, dy: Double) throws -> LayoutShape {
        guard case let .rect(r) = shape.geometry else { throw FloorplanError.nonRectangularGeometry }
        return LayoutShape(layer: shape.layer, geometry: .rect(LayoutRect(
            origin: LayoutPoint(x: r.origin.x + dx, y: r.origin.y + dy), size: r.size)))
    }
}
