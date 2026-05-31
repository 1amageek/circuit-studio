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

    /// A li1 strap (rail height 0.45 µm) joining all of a power rail's per-block pins along
    /// their shared row — so VPWR/VGND become one net across the blocks (the rails are
    /// otherwise separate per block). Power nets stay as top-level ports.
    private func powerStrap(pins: [LayoutPoint]) -> [LayoutShape] {
        let minX = pins.map(\.x).min() ?? 0, maxX = pins.map(\.x).max() ?? 0
        let y = pins.map(\.y).reduce(0, +) / Double(max(pins.count, 1))
        return [rect("li1", minX - 0.085, y - 0.225, (maxX - minX) + 0.17, 0.45)]
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
        for net in powerNets {
            let pins = cell.labels.filter { $0.text == net }.map(\.position)
            guard pins.count >= 2 else { continue }   // a single-block power net is already whole
            cell.shapes.append(contentsOf: powerStrap(pins: pins))
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
