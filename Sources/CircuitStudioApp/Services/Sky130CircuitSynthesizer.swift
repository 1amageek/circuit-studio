import Foundation
import LayoutCore
import LayoutTech

/// Places a `GateLevelNetlist`'s standard cells in a row and routes the nets between them
/// into one flat Sky130 layout — automatic gate-level place & route. Each cell is
/// synthesized by `Sky130StandardCellSynthesizer`; cells are placed left-to-right in
/// topological (driver-before-sink) order on a shared, continuous n-well and VPWR/VGND
/// rails; each internal net is physically wired with li1 (a poly input contact on the
/// sink gate + an li1 run from the driver's output) — not a label-only "virtual" merge,
/// so a missing wire fails LVS rather than passing silently.
public struct Sky130CircuitSynthesizer: Sendable {

    public enum RouteError: Error, LocalizedError, Equatable {
        case combinationalCycle
        case noDriver(net: String)
        case unsupportedGeometry

        public var errorDescription: String? {
            switch self {
            case .combinationalCycle: return "The gate-level netlist has a combinational cycle (cannot order cells)."
            case .noDriver(let n): return "Internal net \(n) drives a gate but has no driver instance."
            case .unsupportedGeometry: return "A cell produced non-rectangular geometry the placer cannot translate."
            }
        }
    }

    private let cellSynth: Sky130StandardCellSynthesizer
    private static let cellGap = 0.90   // inter-cell spacing (keeps implants >= 0.38 apart)

    public init(cellSynthesizer: Sky130StandardCellSynthesizer = Sky130StandardCellSynthesizer()) {
        self.cellSynth = cellSynthesizer
    }

    // MARK: - placement order

    /// Topologically order instances so every net's driver precedes its sinks.
    private func ordered(_ netlist: GateLevelNetlist) throws -> [GateLevelNetlist.Instance] {
        let primaries = Set(netlist.inputs).union([netlist.vpwr, netlist.vgnd])
        let driverOf = Dictionary(uniqueKeysWithValues: netlist.instances.map { (netlist.driverNet(of: $0), $0.name) })
        var result: [GateLevelNetlist.Instance] = []
        var placed = Set<String>()
        var remaining = netlist.instances
        while !remaining.isEmpty {
            let ready = remaining.filter { inst in
                inst.cell.devices.map(\.gate).allSatisfy { g in
                    let net = inst.net(g)
                    return primaries.contains(net) || driverOf[net].map(placed.contains) == true
                }
            }
            if ready.isEmpty {
                // A feedback loop (e.g. a latch): no instance has all inputs driven yet.
                // Place the remaining instances in order — the met2 channel router wires
                // the back-edges regardless of left/right placement.
                result.append(contentsOf: remaining)
                break
            }
            for inst in ready { result.append(inst); placed.insert(inst.name) }
            let readyNames = Set(ready.map(\.name))
            remaining.removeAll { readyNames.contains($0.name) }
        }
        return result
    }

    // MARK: - geometry helpers

    private func shifted(_ shape: LayoutShape, dx: Double) throws -> LayoutShape {
        guard case let .rect(r) = shape.geometry else { throw RouteError.unsupportedGeometry }
        return LayoutShape(layer: shape.layer, geometry: .rect(LayoutRect(
            origin: LayoutPoint(x: r.origin.x + dx, y: r.origin.y), size: r.size)))
    }
    private func rect(_ layer: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> LayoutShape {
        LayoutShape(layer: Sky130LayoutTech.layer(layer),
                    geometry: .rect(LayoutRect(origin: LayoutPoint(x: x, y: y), size: LayoutSize(width: w, height: h))))
    }
    private func label(_ t: String, _ layer: String, _ x: Double, _ y: Double) -> LayoutLabel {
        LayoutLabel(text: t, position: LayoutPoint(x: x, y: y), layer: Sky130LayoutTech.layer(layer))
    }

    /// Lift a li1 tap at field y up to a met2 track: an mcon (li1->met1), a continuous
    /// 0.29-wide met1 riser, and a via (met1->met2) at the track. The li1 pad merges with
    /// the underlying trunk/contact; mcon and via are at different y (not stacked).
    private func viaUp(_ x: Double, trackY: Double) -> [LayoutShape] {
        let y = Sky130StandardCellSynthesizer.CellLayout.fieldY
        return [
            rect("li1", x - 0.165, y - 0.165, 0.33, 0.33),                       // covers the mcon
            rect("mcon", x - 0.085, y - 0.085, 0.17, 0.17),
            rect("met1", x - 0.165, y - 0.165, 0.33, (trackY + 0.165) - (y - 0.165)),  // riser (encl 0.09)
            rect("via", x - 0.075, trackY - 0.075, 0.15, 0.15),
        ]
    }

    /// Tap a driver cell's MET2 output bus (at the cell's output-bus y) up to a met2
    /// routing track, on met1 so it does not collide with other nets' met2 tracks.
    private func driverTap(_ x: Double, trackY: Double) -> [LayoutShape] {
        let busY = Sky130StandardCellSynthesizer.outputBusY
        return [
            rect("met1", x - 0.165, busY - 0.165, 0.33, 0.33),                       // met1 pad under the bus
            rect("via", x - 0.075, busY - 0.075, 0.15, 0.15),                        // met2 bus <-> met1
            rect("met1", x - 0.165, busY - 0.165, 0.33, (trackY + 0.165) - (busY - 0.165)),  // met1 riser
            rect("via", x - 0.075, trackY - 0.075, 0.15, 0.15),                      // met1 -> met2 track
        ]
    }

    /// A poly input contact (pad + npc + licon + li1) on a gate at column-left `gx`, field y.
    private func polyContact(_ gx: Double) -> [LayoutShape] {
        let cx = gx + 0.08   // gate poly centre
        let y = Sky130StandardCellSynthesizer.CellLayout.fieldY
        return [
            rect("poly", cx - 0.165, y - 0.165, 0.33, 0.33),
            rect("npc", cx - 0.185, y - 0.185, 0.37, 0.37),
            rect("licon1", cx - 0.085, y - 0.085, 0.17, 0.17),
            rect("li1", cx - 0.165, y - 0.165, 0.33, 0.33),
        ]
    }

    // MARK: - synthesis

    public func synthesize(_ netlist: GateLevelNetlist) throws -> LayoutDocument {
        let order = try ordered(netlist)
        let primaries = Set(netlist.inputs)

        // 1) Place each cell, translate its geometry, remap net labels.
        struct Placed { let inst: GateLevelNetlist.Instance; let cell: Sky130StandardCellSynthesizer.CellLayout; let offsetX: Double }
        var placed: [Placed] = []
        var shapes: [LayoutShape] = []
        var labels: [LayoutLabel] = []
        var offsetX = 0.0
        for inst in order {
            let cl = try cellSynth.layout(inst.cell)
            for s in cl.shapes { shapes.append(try shifted(s, dx: offsetX)) }
            // Keep only the per-cell power-rail labels. Every signal net (primary inputs,
            // internal nets, the output) is physically ROUTED and labelled ONCE on its
            // met2 track below — same-name poly labels on separate cells do NOT merge in
            // Magic, so a multi-fanout primary input would otherwise extract as open nets.
            for lbl in cl.labels where lbl.text == inst.cell.vpwr || lbl.text == inst.cell.vgnd {
                labels.append(label(inst.net(lbl.text), layerName(of: lbl.layer),
                                    lbl.position.x + offsetX, lbl.position.y))
            }
            placed.append(Placed(inst: inst, cell: cl, offsetX: offsetX))
            offsetX += cl.width + Self.cellGap
        }
        let rightEdge = (placed.last.map { $0.offsetX + $0.cell.width } ?? 0)

        // 2) Continuous n-well + VPWR/VGND rails spanning the whole row (merge per-cell ones).
        shapes.append(rect("nwell", -0.21, 1.40 - 0.21, rightEdge + 0.42, (2.61 + 0.18) - (1.40 - 0.21)))
        shapes.append(rect("li1", -0.10, 2.10, rightEdge + 0.20, 0.45))   // VPWR rail
        shapes.append(rect("li1", -0.10, -1.08, rightEdge + 0.20, 0.62))  // VGND rail

        // 3) Route every internal (driven, non-primary-output... including output) net to its sinks.
        // 3) Route each internal net on its own met2 track (2-layer channel routing:
        //    met1 vertical risers from li1 taps, met2 horizontal tracks above the row).
        //    Layer separation (met1 up / met2 across) avoids same-layer crossings, so
        //    arbitrary connectivity works: multi-fanout, non-adjacent, and feedback.
        let driver = Dictionary(uniqueKeysWithValues: placed.map { (netlist.driverNet(of: $0.inst), $0) })
        var sinkTapsByNet: [String: [Double]] = [:]
        for p in placed {
            for g in Set(p.inst.cell.devices.map(\.gate)) {
                let net = p.inst.net(g)
                guard net != netlist.vpwr, net != netlist.vgnd else { continue }
                guard let gateLocalX = p.cell.gateNetX[g] else { continue }
                shapes.append(contentsOf: polyContact(p.offsetX + gateLocalX))
                sinkTapsByNet[net, default: []].append(p.offsetX + gateLocalX + 0.08)
            }
        }
        // Route EVERY signal net (including primary inputs, which fan out to several gates)
        // on its own met2 track: the driver (if any) taps its met2 output bus, each sink
        // taps its li1 gate contact, all rising on met1. Primary inputs and the output get
        // one met2 label (the port); internal nets are matched by topology.
        let allNets = Set(sinkTapsByNet.keys).union(driver.keys)
            .subtracting([netlist.vpwr, netlist.vgnd])
        for (index, net) in allNets.sorted().enumerated() {
            let sinks = sinkTapsByNet[net] ?? []
            let trackY = 3.6 + Double(index) * 0.50
            var xs = sinks
            if let drv = driver[net] {
                let driverTapX = drv.offsetX + drv.cell.outputRightX - 0.165
                shapes.append(contentsOf: driverTap(driverTapX, trackY: trackY))
                xs.append(driverTapX)
            } else if sinks.isEmpty {
                continue
            }
            for x in sinks { shapes.append(contentsOf: viaUp(x, trackY: trackY)) }
            let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
            shapes.append(rect("met2", minX - 0.165, trackY - 0.165, max(maxX - minX, 0) + 0.33, 0.33))
            if primaries.contains(net) || net == netlist.output {
                labels.append(label(net, "met2", (xs.first ?? minX), trackY))
            }
        }

        var cell = LayoutCell(name: netlist.name, shapes: shapes)
        cell.labels = labels
        return LayoutDocument(name: netlist.name, cells: [cell], topCellID: cell.id)
    }

    private func layerName(of id: LayoutLayerID) -> String { id.name }

    // MARK: - reference netlist

    /// The flattened reference schematic: every cell's transistors with nets remapped to
    /// circuit nets (internal cell nodes uniquified per instance). Ports match the layout
    /// labels by name.
    public func referenceSPICE(_ netlist: GateLevelNetlist) -> String {
        func resolve(_ inst: GateLevelNetlist.Instance, _ local: String) -> String {
            if local == inst.cell.vpwr { return netlist.vpwr }
            if local == inst.cell.vgnd { return netlist.vgnd }
            if let mapped = inst.netMap[local] { return mapped }
            return "\(inst.name)_\(local)"   // internal node, uniquified
        }
        let ports = (netlist.inputs + [netlist.output, netlist.vpwr, netlist.vgnd]).joined(separator: " ")
        var lines = ["* synthesized circuit \(netlist.name)", ".subckt \(netlist.name) \(ports)"]
        for inst in netlist.instances {
            for (i, d) in inst.cell.devices.enumerated() {
                let model = d.kind == .pmos ? "sky130_fd_pr__pfet_01v8" : "sky130_fd_pr__nfet_01v8"
                let bulk = d.kind == .pmos ? netlist.vpwr : netlist.vgnd
                let w = String(format: "%g", d.width), l = String(format: "%g", d.length)
                lines.append("X\(inst.name)_\(i) \(resolve(inst, d.drain)) \(resolve(inst, d.gate)) \(resolve(inst, d.source)) \(bulk) \(model) w=\(w) l=\(l)")
            }
        }
        lines.append(".ends")
        return lines.joined(separator: "\n")
    }
}
