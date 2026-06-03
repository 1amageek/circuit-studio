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
        case duplicateDriverNet(String)
        case duplicateAntennaProtectionCandidateID(String)
        case duplicateAntennaProtectionSiteID(String)
        case unknownAntennaProtectionSiteID(String)
        case inconsistentAntennaProtectionSiteID(String)
        case inconsistentAntennaProtectionPlanDesignName(expected: String, actual: String)
        case missingGateGeometry(instance: String, gate: String)

        public var errorDescription: String? {
            switch self {
            case .combinationalCycle: return "The gate-level netlist has a combinational cycle (cannot order cells)."
            case .noDriver(let n): return "Internal net \(n) drives a gate but has no driver instance."
            case .unsupportedGeometry: return "A cell produced non-rectangular geometry the placer cannot translate."
            case .duplicateDriverNet(let net): return "Gate-level net \(net) is driven by more than one instance."
            case .duplicateAntennaProtectionCandidateID(let id): return "Antenna protection candidates contain duplicate site ID \(id)."
            case .duplicateAntennaProtectionSiteID(let id): return "Antenna protection plan contains duplicate site ID \(id)."
            case .unknownAntennaProtectionSiteID(let id): return "Antenna protection plan references unknown site ID \(id)."
            case .inconsistentAntennaProtectionSiteID(let id): return "Antenna protection plan site \(id) does not match the routed geometry."
            case .inconsistentAntennaProtectionPlanDesignName(let expected, let actual):
                return "Antenna protection plan design \(actual) does not match routed design \(expected)."
            case .missingGateGeometry(let instance, let gate):
                return "Cell instance \(instance) is missing gate geometry for gate net \(gate)."
            }
        }
    }

    private let cellSynth: Sky130StandardCellSynthesizer
    private let antennaProtectionPlanProvider: any AntennaProtectionPlanProvider
    private let antennaTieGenerator: Sky130AntennaTieGenerator
    private static let cellGap = 0.90   // inter-cell spacing (keeps implants >= 0.38 apart)
    private static let firstSignalTrackY = 3.60
    private static let met3AccessPadWidth = 0.50
    private static let signalTrackRuleMargin = 0.05
    private static let antennaTieBaseY = -2.40
    private static let met3MinimumSpacing = minimumSpacing(layer: "met3")
    private static let signalTrackPitch = met3AccessPadWidth + met3MinimumSpacing + signalTrackRuleMargin

    public init(
        cellSynthesizer: Sky130StandardCellSynthesizer = Sky130StandardCellSynthesizer(),
        antennaProtectionPlanProvider: any AntennaProtectionPlanProvider = GateLevelAntennaProtectionPlanner(),
        antennaTieGenerator: Sky130AntennaTieGenerator = Sky130AntennaTieGenerator()
    ) {
        self.cellSynth = cellSynthesizer
        self.antennaProtectionPlanProvider = antennaProtectionPlanProvider
        self.antennaTieGenerator = antennaTieGenerator
    }

    public struct SynthesisResult: Sendable {
        public let document: LayoutDocument
        public let antennaProtectionPlan: AntennaProtectionPlan

        public init(document: LayoutDocument, antennaProtectionPlan: AntennaProtectionPlan) {
            self.document = document
            self.antennaProtectionPlan = antennaProtectionPlan
        }
    }

    // MARK: - placement order

    /// Topologically order instances so every net's driver precedes its sinks.
    private func ordered(_ netlist: GateLevelNetlist) throws -> [GateLevelNetlist.Instance] {
        let primaries = Set(netlist.inputs).union([netlist.vpwr, netlist.vgnd])
        var driverOf: [String: String] = [:]
        for instance in netlist.instances {
            let net = netlist.driverNet(of: instance)
            guard driverOf[net] == nil else {
                throw RouteError.duplicateDriverNet(net)
            }
            driverOf[net] = instance.name
        }
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
        try synthesisResult(for: netlist).document
    }

    public func synthesisResult(for netlist: GateLevelNetlist) throws -> SynthesisResult {
        let order = try placementOrder(netlist)
        let placed = try place(order: order)
        let routeAnalysis = try routeAnalysis(for: netlist, placed: placed)
        let antennaPlan = try antennaProtectionPlanProvider.plan(for: netlist, candidates: routeAnalysis.candidates)
        return try synthesize(netlist, placed: placed, routeAnalysis: routeAnalysis, antennaPlan: antennaPlan)
    }

    private func synthesize(
        _ netlist: GateLevelNetlist,
        placed: [PlacedCell],
        routeAnalysis: RouteAnalysis,
        antennaPlan: AntennaProtectionPlan
    ) throws -> SynthesisResult {
        let primaries = Set(netlist.inputs)

        // 1) Place each cell, translate its geometry, remap net labels.
        var shapes: [LayoutShape] = []
        var labels: [LayoutLabel] = []
        for placedCell in placed {
            for shape in placedCell.cell.shapes { shapes.append(try shifted(shape, dx: placedCell.offsetX)) }
            // Keep only the per-cell power-rail labels. Every signal net (primary inputs,
            // internal nets, the output) is physically ROUTED and labelled ONCE on its
            // met2 track below — same-name poly labels on separate cells do NOT merge in
            // Magic, so a multi-fanout primary input would otherwise extract as open nets.
            for label in placedCell.cell.labels where label.text == placedCell.inst.cell.vpwr || label.text == placedCell.inst.cell.vgnd {
                labels.append(self.label(
                    placedCell.inst.net(label.text),
                    layerName(of: label.layer),
                    label.position.x + placedCell.offsetX,
                    label.position.y
                ))
            }
        }
        let rightEdge = (placed.last.map { $0.offsetX + $0.cell.width } ?? 0)

        // 2) Continuous n-well + VPWR/VGND rails spanning the whole row (merge per-cell ones).
        shapes.append(rect("nwell", -0.21, 1.40 - 0.21, rightEdge + 0.42, (2.61 + 0.18) - (1.40 - 0.21)))
        shapes.append(rect("li1", -0.10, 2.10, rightEdge + 0.20, 0.45))   // VPWR rail
        shapes.append(rect("li1", -0.10, -1.08, rightEdge + 0.20, 0.62))  // VGND rail

        // 3) Route each internal net on its own met2 track (2-layer channel routing:
        //    met1 vertical risers from li1 taps, met2 horizontal tracks above the row).
        //    Layer separation (met1 up / met2 across) avoids same-layer crossings, so
        //    arbitrary connectivity works: multi-fanout, non-adjacent, and feedback.
        for p in placed {
            for g in Set(p.inst.cell.devices.map(\.gate)).sorted() {
                let net = p.inst.net(g)
                guard let gateLocalX = p.cell.gateNetX[g] else {
                    throw RouteError.missingGateGeometry(instance: p.inst.name, gate: g)
                }
                let cx = p.offsetX + gateLocalX + 0.08
                shapes.append(contentsOf: polyContact(p.offsetX + gateLocalX))
                // A gate tied to a rail is a constant: bond it to the rail in place. A gate
                // on a signal net taps up to that net's met2 track (routed below).
                if net == netlist.vgnd {
                    shapes.append(contentsOf: railStrap(cx, toVGND: true))
                } else if net == netlist.vpwr {
                    shapes.append(contentsOf: railStrap(cx, toVGND: false))
                }
            }
        }
        // Route EVERY signal net (including primary inputs, which fan out to several gates)
        // on its own met2 track: the driver (if any) taps its met2 output bus, each sink
        // taps its li1 gate contact, all rising on met1. Primary inputs and the output get
        // one met2 label (the port); internal nets are matched by topology.
        let antennaSiteByID = try validatedAntennaSiteMap(antennaPlan, netlist: netlist, routeAnalysis: routeAnalysis)
        for net in routeAnalysis.allNets {
            let sinks = routeAnalysis.sinkTapsByNet[net] ?? []
            let trackY = routeAnalysis.trackYByNet[net] ?? Self.firstSignalTrackY
            var xs = sinks.map(\.centerXMicrons)
            if let drv = routeAnalysis.driverByNet[net] {
                let driverTapX = drv.offsetX + drv.cell.outputRightX - 0.165
                shapes.append(contentsOf: driverTap(driverTapX, trackY: trackY))
                xs.append(driverTapX)
            } else if sinks.isEmpty {
                continue
            }
            for sink in sinks {
                if let site = antennaSiteByID[sink.id] {
                    shapes.append(contentsOf: antennaTieGenerator.shapes(for: site, baseY: Self.antennaTieBaseY))
                } else {
                    shapes.append(contentsOf: viaUp(sink.centerXMicrons, trackY: trackY))
                }
            }
            let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
            shapes.append(rect("met2", minX - 0.165, trackY - 0.165, max(maxX - minX, 0) + 0.33, 0.33))
            if primaries.contains(net) || netlist.outputs.contains(net) {
                labels.append(label(net, "met2", (xs.first ?? minX), trackY))
            }
        }

        var cell = LayoutCell(name: netlist.name, shapes: shapes)
        cell.labels = labels
        return SynthesisResult(
            document: LayoutDocument(name: netlist.name, cells: [cell], topCellID: cell.id),
            antennaProtectionPlan: antennaPlan
        )
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
        var driverInstOfNet: [String: Int] = [:]
        for (index, instance) in insts.enumerated() {
            let net = netlist.driverNet(of: instance)
            guard driverInstOfNet[net] == nil else {
                throw RouteError.duplicateDriverNet(net)
            }
            driverInstOfNet[net] = index
        }
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
    /// `gateLoadCount` is the number of sink GATES it reaches. The met2-antenna ratio is
    /// ≈ 10.7·span/load, so a net is antenna-safe (with a diode, ratio ≤ 2200) when
    /// `spanPerGateMicrons ≤ ~205`. The input to antenna repeater/diode scoping.
    public struct NetSpan: Sendable, Hashable {
        public let net: String
        public let minimumXMicrons: Double
        public let maximumXMicrons: Double
        public let gateLoadCount: Int
        public var spanMicrons: Double { maximumXMicrons - minimumXMicrons }
        public var spanPerGateMicrons: Double {
            gateLoadCount > 0 ? spanMicrons / Double(gateLoadCount) : spanMicrons
        }
    }

    private struct PlacedCell {
        let inst: GateLevelNetlist.Instance
        let cell: Sky130StandardCellSynthesizer.CellLayout
        let offsetX: Double
    }

    private struct GateSinkTap {
        let id: String
        let net: String
        let instanceName: String
        let gateName: String
        let centerXMicrons: Double
    }

    private struct RouteAnalysis {
        let driverByNet: [String: PlacedCell]
        let sinkTapsByNet: [String: [GateSinkTap]]
        let allNets: [String]
        let trackYByNet: [String: Double]
        let spans: [NetSpan]
        let candidates: [AntennaProtectionCandidate]
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

    private func routeAnalysis(
        for netlist: GateLevelNetlist,
        placed: [PlacedCell]
    ) throws -> RouteAnalysis {
        var driverByNet: [String: PlacedCell] = [:]
        for placedCell in placed {
            let net = netlist.driverNet(of: placedCell.inst)
            guard driverByNet[net] == nil else {
                throw RouteError.duplicateDriverNet(net)
            }
            driverByNet[net] = placedCell
        }
        var sinkTapsByNet: [String: [GateSinkTap]] = [:]
        for placedCell in placed {
            for gate in Set(placedCell.inst.cell.devices.map(\.gate)).sorted() {
                let net = placedCell.inst.net(gate)
                guard net != netlist.vgnd, net != netlist.vpwr else { continue }
                guard let gateLocalX = placedCell.cell.gateNetX[gate] else {
                    throw RouteError.missingGateGeometry(instance: placedCell.inst.name, gate: gate)
                }
                let centerX = placedCell.offsetX + gateLocalX + 0.08
                let tap = GateSinkTap(
                    id: antennaSiteID(instanceName: placedCell.inst.name, gateName: gate, net: net),
                    net: net,
                    instanceName: placedCell.inst.name,
                    gateName: gate,
                    centerXMicrons: centerX
                )
                sinkTapsByNet[net, default: []].append(tap)
            }
        }

        let allNets = Set(sinkTapsByNet.keys).union(driverByNet.keys)
            .subtracting([netlist.vpwr, netlist.vgnd])
            .sorted()
        let trackYByNet = Dictionary(uniqueKeysWithValues: allNets.enumerated().map {
            ($0.element, Self.firstSignalTrackY + Double($0.offset) * Self.signalTrackPitch)
        })

        var spans: [NetSpan] = []
        var candidates: [AntennaProtectionCandidate] = []
        let drivenNets = netlist.drivenNets
        for net in allNets {
            let sinks = sinkTapsByNet[net] ?? []
            var xs = sinks.map(\.centerXMicrons)
            if let driver = driverByNet[net] {
                xs.append(driver.offsetX + driver.cell.outputRightX - 0.165)
            }
            guard let minX = xs.min(), let maxX = xs.max() else { continue }
            let span = NetSpan(
                net: net,
                minimumXMicrons: minX,
                maximumXMicrons: maxX,
                gateLoadCount: sinks.count
            )
            spans.append(span)

            let trackY = trackYByNet[net] ?? Self.firstSignalTrackY
            for sink in sinks {
                candidates.append(AntennaProtectionCandidate(
                    id: sink.id,
                    net: sink.net,
                    instanceName: sink.instanceName,
                    gateName: sink.gateName,
                    centerXMicrons: sink.centerXMicrons,
                    trackYMicrons: trackY,
                    gateLoadCount: sinks.count,
                    hasDiffusionDischargeAnchor: drivenNets.contains(net),
                    spanMicrons: span.spanMicrons,
                    spanPerGateMicrons: span.spanPerGateMicrons
                ))
            }
        }

        return RouteAnalysis(
            driverByNet: driverByNet,
            sinkTapsByNet: sinkTapsByNet,
            allNets: allNets,
            trackYByNet: trackYByNet,
            spans: spans,
            candidates: candidates
        )
    }

    private func validatedAntennaSiteMap(
        _ plan: AntennaProtectionPlan,
        netlist: GateLevelNetlist,
        routeAnalysis: RouteAnalysis
    ) throws -> [String: AntennaProtectionPlan.Site] {
        guard plan.designName == netlist.name else {
            throw RouteError.inconsistentAntennaProtectionPlanDesignName(expected: netlist.name, actual: plan.designName)
        }
        var candidateByID: [String: AntennaProtectionCandidate] = [:]
        for candidate in routeAnalysis.candidates {
            guard candidateByID[candidate.id] == nil else {
                throw RouteError.duplicateAntennaProtectionCandidateID(candidate.id)
            }
            candidateByID[candidate.id] = candidate
        }
        var siteByID: [String: AntennaProtectionPlan.Site] = [:]
        for site in plan.sites {
            guard let candidate = candidateByID[site.id] else {
                throw RouteError.unknownAntennaProtectionSiteID(site.id)
            }
            guard siteByID[site.id] == nil else {
                throw RouteError.duplicateAntennaProtectionSiteID(site.id)
            }
            guard antennaSite(site, matches: candidate) else {
                throw RouteError.inconsistentAntennaProtectionSiteID(site.id)
            }
            siteByID[site.id] = site
        }
        return siteByID
    }

    private func antennaSite(
        _ site: AntennaProtectionPlan.Site,
        matches candidate: AntennaProtectionCandidate
    ) -> Bool {
        site.net == candidate.net
            && site.instanceName == candidate.instanceName
            && site.gateName == candidate.gateName
            && site.gateLoadCount == candidate.gateLoadCount
            && site.hasDiffusionDischargeAnchor == candidate.hasDiffusionDischargeAnchor
            && nearlyEqual(site.centerXMicrons, candidate.centerXMicrons)
            && nearlyEqual(site.trackYMicrons, candidate.trackYMicrons)
            && nearlyEqual(site.spanMicrons, candidate.spanMicrons)
            && nearlyEqual(site.spanPerGateMicrons, candidate.spanPerGateMicrons)
    }

    private func nearlyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        lhs.isFinite && rhs.isFinite && abs(lhs - rhs) <= 1e-9
    }

    private func antennaSiteID(instanceName: String, gateName: String, net: String) -> String {
        [
            "i=\(antennaSiteIDComponent(instanceName))",
            "g=\(antennaSiteIDComponent(gateName))",
            "n=\(antennaSiteIDComponent(net))",
        ].joined(separator: ";")
    }

    private func antennaSiteIDComponent(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Each signal net's placed span + fanout for a given instance `placementOrder` (default: the
    /// synthesizer's actual placement order). Pure geometry (no Magic) — the input to antenna scoping.
    public func netSpans(
        for netlist: GateLevelNetlist,
        placementOrder: [GateLevelNetlist.Instance]? = nil
    ) throws -> [NetSpan] {
        let placed = try place(order: placementOrder ?? self.placementOrder(netlist))
        return try routeAnalysis(for: netlist, placed: placed).spans
    }

    public func antennaProtectionCandidates(
        for netlist: GateLevelNetlist,
        placementOrder: [GateLevelNetlist.Instance]? = nil
    ) throws -> [AntennaProtectionCandidate] {
        let placed = try place(order: placementOrder ?? self.placementOrder(netlist))
        return try routeAnalysis(for: netlist, placed: placed).candidates
    }

    public func antennaProtectionPlan(for netlist: GateLevelNetlist) throws -> AntennaProtectionPlan {
        try antennaProtectionPlan(for: netlist, order: placementOrder(netlist))
    }

    private func antennaProtectionPlan(
        for netlist: GateLevelNetlist,
        order: [GateLevelNetlist.Instance]
    ) throws -> AntennaProtectionPlan {
        let placed = try place(order: order)
        let routeAnalysis = try routeAnalysis(for: netlist, placed: placed)
        let plan = try antennaProtectionPlanProvider.plan(for: netlist, candidates: routeAnalysis.candidates)
        try plan.validate()
        _ = try validatedAntennaSiteMap(plan, netlist: netlist, routeAnalysis: routeAnalysis)
        return plan
    }

    // MARK: - reference netlist

    /// The flattened reference schematic: every cell's transistors with nets remapped to
    /// circuit nets (internal cell nodes uniquified per instance). Ports match the layout
    /// labels by name.
    public func referenceSPICE(for netlist: GateLevelNetlist) -> String {
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
