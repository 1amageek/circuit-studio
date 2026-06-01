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
    private static let firstSignalTrackY = 3.60
    private static let met3AccessPadWidth = 0.50
    private static let signalTrackRuleMargin = 0.05
    private static let met3MinimumSpacing = minimumSpacing(layer: "met3")
    private static let signalTrackPitch = met3AccessPadWidth + met3MinimumSpacing + signalTrackRuleMargin

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

    private static func minimumSpacing(layer: String) -> Double {
        guard let spacing = Sky130LayoutTech.tech().ruleSet(for: Sky130LayoutTech.layer(layer))?.minSpacing else {
            preconditionFailure("Sky130 \(layer) rule must define minimum spacing")
        }
        return spacing
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

    /// Tie a gate's field li1 contact (centre `cx`) straight to a power rail with one li1
    /// strap — down into the VGND rail (below the cell) or up into the VPWR rail (above).
    /// Used when a gate INPUT is a constant rail (e.g. a ripple adder's carry-in = VGND, or
    /// a two's-complement subtractor's carry-in = VPWR): the gate is a constant, not a
    /// routed signal, so it never gets a track — it bonds to the rail in place. Running at
    /// the gate column (between source/drain contacts) keeps >= 0.17 li1 spacing.
    private func railStrap(_ cx: Double, toVGND: Bool) -> [LayoutShape] {
        let fieldY = Sky130StandardCellSynthesizer.CellLayout.fieldY
        if toVGND {
            // VGND rail spans y -1.08 ... -0.46; the field pad bottom is fieldY - 0.165.
            return [rect("li1", cx - 0.165, -0.60, 0.33, (fieldY) - (-0.60))]
        }
        // VPWR rail spans y 2.10 ... 2.55; bridge from the field pad up into it.
        return [rect("li1", cx - 0.165, fieldY, 0.33, 2.30 - fieldY)]
    }

    // MARK: - synthesis

    public func synthesize(_ netlist: GateLevelNetlist) throws -> LayoutDocument {
        let order = try placementOrder(netlist)
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
                guard let gateLocalX = p.cell.gateNetX[g] else { continue }
                let cx = p.offsetX + gateLocalX + 0.08
                shapes.append(contentsOf: polyContact(p.offsetX + gateLocalX))
                // A gate tied to a rail is a constant: bond it to the rail in place. A gate
                // on a signal net taps up to that net's met2 track (routed below).
                if net == netlist.vgnd {
                    shapes.append(contentsOf: railStrap(cx, toVGND: true))
                } else if net == netlist.vpwr {
                    shapes.append(contentsOf: railStrap(cx, toVGND: false))
                } else {
                    sinkTapsByNet[net, default: []].append(cx)
                }
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
            let trackY = Self.firstSignalTrackY + Double(index) * Self.signalTrackPitch
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
            if primaries.contains(net) || netlist.outputs.contains(net) {
                labels.append(label(net, "met2", (xs.first ?? minX), trackY))
            }
        }

        var cell = LayoutCell(name: netlist.name, shapes: shapes)
        cell.labels = labels
        return LayoutDocument(name: netlist.name, cells: [cell], topCellID: cell.id)
    }

    private func layerName(of id: LayoutLayerID) -> String { id.name }

    // MARK: - antenna-aware placement + net-span analysis

    /// Antenna-aware placement order: start topological (a valid driver-before-sink order), then
    /// run a few barycenter passes that pull each cell toward the average rank of the cells it
    /// shares a net with. Clustering connected cells SHORTENS every net's met2 track, the dominant
    /// met2 antenna at scale — e.g. it pulls each DFF's clock inverter next to its latches,
    /// collapsing the long `clkb` nets. Reordering is LVS- and function-neutral (same netlist, the
    /// channel router wires any order); it only moves cells in x. This is the placement groundwork
    /// for full antenna closure (which also needs a 2D engine for the remaining global nets).
    private static let barycenterIterations = 5
    func placementOrder(_ netlist: GateLevelNetlist) throws -> [GateLevelNetlist.Instance] {
        let insts = try ordered(netlist)
        let n = insts.count
        guard n > 2 else { return insts }
        let driverInstOfNet = Dictionary(
            insts.enumerated().map { (netlist.driverNet(of: $1), $0) }, uniquingKeysWith: { a, _ in a })
        var neighbors = [Set<Int>](repeating: [], count: n)
        for (i, inst) in insts.enumerated() {
            for g in Set(inst.cell.devices.map(\.gate)) {
                if let j = driverInstOfNet[inst.net(g)], j != i { neighbors[i].insert(j); neighbors[j].insert(i) }
            }
        }
        var pos = (0..<n).map(Double.init)
        for _ in 0..<Self.barycenterIterations {
            var next = pos
            for i in 0..<n where !neighbors[i].isEmpty {
                next[i] = neighbors[i].reduce(0.0) { $0 + pos[$1] } / Double(neighbors[i].count)
            }
            let ranked = (0..<n).sorted { next[$0] != next[$1] ? next[$0] < next[$1] : $0 < $1 }
            for (rank, i) in ranked.enumerated() { pos[i] = Double(rank) }
        }
        return (0..<n).sorted { pos[$0] != pos[$1] ? pos[$0] < pos[$1] : $0 < $1 }.map { insts[$0] }
    }

    /// One routed net's physical extent in the placed row. The met2 track spans `[minX, maxX]`;
    /// `fanout` is the number of sink GATES it reaches. The met2-antenna ratio is ≈ 10.7·span/fanout,
    /// so a net is antenna-safe (with a diode, ratio ≤ 2200) when `span/fanout ≤ ~205 µm` —
    /// `spanPerGate` reports that figure directly. The input to antenna repeater/diode scoping.
    public struct NetSpan: Sendable, Hashable {
        public let net: String
        public let minX: Double
        public let maxX: Double
        public let fanout: Int
        public var span: Double { maxX - minX }
        public var spanPerGate: Double { fanout > 0 ? span / Double(fanout) : span }
    }

    private struct PlacedCell {
        let inst: GateLevelNetlist.Instance
        let cell: Sky130StandardCellSynthesizer.CellLayout
        let offsetX: Double
    }

    private func place(order: [GateLevelNetlist.Instance]) throws -> [PlacedCell] {
        var placed: [PlacedCell] = []
        var offsetX = 0.0
        for inst in order {
            let cl = try cellSynth.layout(inst.cell)
            placed.append(PlacedCell(inst: inst, cell: cl, offsetX: offsetX))
            offsetX += cl.width + Self.cellGap
        }
        return placed
    }

    /// Each signal net's placed span + fanout for a given instance `order` (default: the
    /// synthesizer's actual placement order). Pure geometry (no Magic) — the input to antenna scoping.
    public func analyzeNetSpans(_ netlist: GateLevelNetlist,
                                order: [GateLevelNetlist.Instance]? = nil) throws -> [NetSpan] {
        let placed = try place(order: order ?? placementOrder(netlist))
        let driver = Dictionary(placed.map { (netlist.driverNet(of: $0.inst), $0) }, uniquingKeysWith: { a, _ in a })
        var sinkTapsByNet: [String: [Double]] = [:]
        for p in placed {
            for g in Set(p.inst.cell.devices.map(\.gate)) {
                let net = p.inst.net(g)
                guard let gateLocalX = p.cell.gateNetX[g] else { continue }
                guard net != netlist.vgnd, net != netlist.vpwr else { continue }
                sinkTapsByNet[net, default: []].append(p.offsetX + gateLocalX + 0.08)
            }
        }
        let allNets = Set(sinkTapsByNet.keys).union(driver.keys).subtracting([netlist.vpwr, netlist.vgnd])
        var result: [NetSpan] = []
        for net in allNets.sorted() {
            var xs = sinkTapsByNet[net] ?? []
            if let drv = driver[net] { xs.append(drv.offsetX + drv.cell.outputRightX - 0.165) }
            guard let mn = xs.min(), let mx = xs.max() else { continue }
            result.append(NetSpan(net: net, minX: mn, maxX: mx, fanout: (sinkTapsByNet[net] ?? []).count))
        }
        return result
    }

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
        let ports = (netlist.inputs + netlist.outputs + [netlist.vpwr, netlist.vgnd]).joined(separator: " ")
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
