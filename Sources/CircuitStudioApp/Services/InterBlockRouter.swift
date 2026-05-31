import Foundation
import LayoutCore

/// Joins the placed blocks of a `GridFloorplanner` floorplan into one connected circuit by
/// routing each boundary net on met3 (the over-the-cell global layer added in BC2.1). A
/// boundary net surfaces as a labelled met2 pin inside every block that touches it; the
/// router drops a via2 (met2→met3) on each pin and connects them with an L-shaped met3
/// wire. After flattening, extraction sees the blocks' pins as one net, so the multi-row
/// layout is LVS-equivalent to the flat netlist.
public struct InterBlockRouter: Sendable {

    public enum RouteError: Error, LocalizedError, Equatable {
        case netPinNotFound(String)
        case noTopCell

        public var errorDescription: String? {
            switch self {
            case .netPinNotFound(let n): return "Boundary net '\(n)' has fewer than two block pins to join."
            case .noTopCell: return "The floorplan document has no top cell to route in."
            }
        }
    }

    public init() {}

    private func rect(_ layer: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> LayoutShape {
        LayoutShape(layer: Sky130LayoutTech.layer(layer),
                    geometry: .rect(LayoutRect(origin: LayoutPoint(x: x, y: y), size: LayoutSize(width: w, height: h))))
    }

    /// A via2 stack at a met2 pin: a met2 landing pad (so the via2 is enclosed by >= 0.085),
    /// the via2 cut, and a met3 pad (>= 0.24 µm² min area), centred at `p`.
    private func via2Stack(at p: LayoutPoint) -> [LayoutShape] {
        [
            rect("met2", p.x - 0.185, p.y - 0.185, 0.37, 0.37),
            rect("via2", p.x - 0.10, p.y - 0.10, 0.20, 0.20),
            rect("met3", p.x - 0.25, p.y - 0.25, 0.50, 0.50),
        ]
    }

    /// An L-shaped met3 wire from `a` to `b`: horizontal at a.y, then vertical at b.x. The
    /// wire is drawn 0.50 µm wide — the same as the via2 met3 pads — so the corner and the
    /// pads merge without leaving a sub-spacing notch (and well above the 0.30 µm minimum).
    private func met3LRoute(from a: LayoutPoint, to b: LayoutPoint) -> [LayoutShape] {
        let half = 0.25
        var shapes: [LayoutShape] = []
        let xLo = min(a.x, b.x), xHi = max(a.x, b.x)
        if xHi - xLo > 1e-6 {
            shapes.append(rect("met3", xLo - half, a.y - half, (xHi - xLo) + 2 * half, 2 * half))
        }
        let yLo = min(a.y, b.y), yHi = max(a.y, b.y)
        if yHi - yLo > 1e-6 {
            shapes.append(rect("met3", b.x - half, yLo - half, 2 * half, (yHi - yLo) + 2 * half))
        }
        return shapes
    }

    /// A li1 "comb" joining all of a power rail's per-block pins into one net: a vertical
    /// spine in the empty left margin (at `spineX`) plus a horizontal tooth at each rail row
    /// reaching from the spine to that row's blocks. Side-by-side blocks share one row (one
    /// tooth, no spine); vertically-stacked blocks have a tooth per row linked by the spine —
    /// so VPWR/VGND become one net whatever the floorplan shape. Power nets stay top ports.
    private func powerStrap(pins: [LayoutPoint], spineX: Double, onLeft: Bool) -> [LayoutShape] {
        let railH = 0.45
        let rowYs = pins.map(\.y).reduce(into: [Double]()) { acc, y in
            if !acc.contains(where: { abs($0 - y) < 0.05 }) { acc.append(y) }
        }.sorted()
        var shapes: [LayoutShape] = []
        for y in rowYs {
            let rowX = pins.filter { abs($0.y - y) < 0.05 }.map(\.x)
            // A left spine reaches RIGHT to the row's blocks; a right spine reaches LEFT.
            if onLeft {
                let maxX = rowX.max() ?? spineX
                shapes.append(rect("li1", spineX, y - railH / 2, (maxX - spineX) + 0.085, railH))
            } else {
                let minX = rowX.min() ?? spineX
                shapes.append(rect("li1", minX - 0.085, y - railH / 2, (spineX - minX) + 0.085 + 0.34, railH))
            }
        }
        if let lo = rowYs.min(), let hi = rowYs.max(), hi - lo > 0.05 {
            shapes.append(rect("li1", spineX, lo - railH / 2, 0.34, (hi - lo) + railH))
        }
        return shapes
    }

    /// Route the floorplan's inter-block nets, returning one connected document. Signal
    /// boundary nets go on met3 (via2 at each block pin) and their per-block labels are
    /// dropped (a boundary net is internal, not a port). Power nets are strapped on li1 and
    /// keep their labels (they ARE top-level ports).
    public func route(
        _ floorplan: GridFloorplanner.Floorplan, boundaryNets: [String],
        powerNets: [String] = ["VPWR", "VGND"]
    ) throws -> LayoutDocument {
        let doc = floorplan.document
        guard var cell = doc.cells.first(where: { $0.id == doc.topCellID }) ?? doc.cells.first else {
            throw RouteError.noTopCell
        }
        // Each power net gets its own margin so the combs never cross: the first on the
        // left, the second on the right, etc. (a stacked block's lower rail otherwise sits
        // inside the other rail's spine y-range and shorts it).
        let xs = cell.shapes.compactMap { shape -> (lo: Double, hi: Double)? in
            guard case let .rect(r) = shape.geometry else { return nil }
            return (r.origin.x, r.origin.x + r.size.width)
        }
        let leftEdge = xs.map(\.lo).min() ?? 0, rightEdge = xs.map(\.hi).max() ?? 0
        for (i, net) in powerNets.enumerated() {
            let pins = cell.labels.filter { $0.text == net }.map(\.position)
            guard pins.count >= 2 else { continue }   // a single-block power net is already whole
            let onLeft = i % 2 == 0
            let lane = Double(i / 2) * 0.8
            let spineX = onLeft ? leftEdge - 0.6 - lane : rightEdge + 0.6 + lane
            cell.shapes.append(contentsOf: powerStrap(pins: pins, spineX: spineX, onLeft: onLeft))
        }
        for net in boundaryNets {
            let pins = cell.labels.filter { $0.text == net }.map(\.position)
            guard pins.count >= 2 else { throw RouteError.netPinNotFound(net) }
            for p in pins { cell.shapes.append(contentsOf: via2Stack(at: p)) }
            for i in 1..<pins.count {
                cell.shapes.append(contentsOf: met3LRoute(from: pins[i - 1], to: pins[i]))
            }
            cell.labels.removeAll { $0.text == net }
        }
        return LayoutDocument(name: doc.name, cells: [cell], topCellID: cell.id)
    }
}
