import Foundation
import LayoutCore
import LayoutTech

/// Places a `GateLevelNetlist`'s standard cells in a row and routes the nets between them
/// into one flat profile-backed layout — automatic gate-level place & route. Each cell is
/// synthesized by `StandardCellSynthesizer`; cells are placed left-to-right in
/// topological (driver-before-sink) order on a shared well and power/ground rails; each
/// internal net is physically wired through profile-selected layer roles rather than a
/// label-only "virtual" merge, so a missing wire fails LVS rather than passing silently.
public struct StandardCircuitSynthesizer: Sendable {

    public enum RouteError: Error, LocalizedError, Equatable {
        case combinationalCycle
        case noDriver(net: String)
        case unsupportedGeometry
        case duplicateDriverNet(String)
        case primaryInputDriven(net: String)
        case undrivenOutput(net: String)
        case duplicateAntennaProtectionCandidateID(String)
        case duplicateAntennaProtectionSiteID(String)
        case unknownAntennaProtectionSiteID(String)
        case inconsistentAntennaProtectionSiteID(String)
        case inconsistentAntennaProtectionPlanDesignName(expected: String, actual: String)
        case missingGateGeometry(instance: String, gate: String)
        case missingMinimumSpacing(layer: String)

        public var errorDescription: String? {
            switch self {
            case .combinationalCycle: return "The gate-level netlist has a combinational cycle (cannot order cells)."
            case .noDriver(let n): return "Internal net \(n) drives a gate but has no driver instance."
            case .unsupportedGeometry: return "A cell produced non-rectangular geometry the placer cannot translate."
            case .duplicateDriverNet(let net): return "Gate-level net \(net) is driven by more than one instance."
            case .primaryInputDriven(let net): return "Primary input net \(net) is also driven by a gate instance."
            case .undrivenOutput(let net): return "Primary output net \(net) has no driver instance."
            case .duplicateAntennaProtectionCandidateID(let id): return "Antenna protection candidates contain duplicate site ID \(id)."
            case .duplicateAntennaProtectionSiteID(let id): return "Antenna protection plan contains duplicate site ID \(id)."
            case .unknownAntennaProtectionSiteID(let id): return "Antenna protection plan references unknown site ID \(id)."
            case .inconsistentAntennaProtectionSiteID(let id): return "Antenna protection plan site \(id) does not match the routed geometry."
            case .inconsistentAntennaProtectionPlanDesignName(let expected, let actual):
                return "Antenna protection plan design \(actual) does not match routed design \(expected)."
            case .missingGateGeometry(let instance, let gate):
                return "Cell instance \(instance) is missing gate geometry for gate net \(gate)."
            case .missingMinimumSpacing(let layer):
                return "Layer \(layer) rule must define minimum spacing."
            }
        }
    }

    private let cellSynth: StandardCellSynthesizer
    private let profile: StandardCellLayoutProfile
    private let layoutTechnology: LayoutTechDatabase
    private let antennaProtectionPlanProvider: any AntennaProtectionPlanProvider
    private let antennaTieGenerator: ProfiledAntennaTieGenerator

    public init(
        profile: StandardCellLayoutProfile,
        layoutTechnology: LayoutTechDatabase,
        cellSynthesizer: StandardCellSynthesizer? = nil,
        antennaProtectionPlanProvider: any AntennaProtectionPlanProvider = GateLevelAntennaProtectionPlanner(),
        antennaTieGenerator: ProfiledAntennaTieGenerator? = nil
    ) {
        self.profile = profile
        self.layoutTechnology = layoutTechnology
        self.cellSynth = cellSynthesizer ?? StandardCellSynthesizer(profile: profile)
        self.antennaProtectionPlanProvider = antennaProtectionPlanProvider
        self.antennaTieGenerator = antennaTieGenerator ?? ProfiledAntennaTieGenerator(profile: profile)
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

    private struct SignalSourceSummary {
        let driverOf: [String: String]
    }

    private func validateSignalSources(in netlist: GateLevelNetlist) throws -> SignalSourceSummary {
        let rails = Set([netlist.vpwr, netlist.vgnd])
        let primaries = Set(netlist.inputs)
        var driverOf: [String: String] = [:]
        for instance in netlist.instances {
            let net = netlist.driverNet(of: instance)
            guard driverOf[net] == nil else {
                throw RouteError.duplicateDriverNet(net)
            }
            guard !primaries.contains(net) else {
                throw RouteError.primaryInputDriven(net: net)
            }
            driverOf[net] = instance.name
        }

        var sinkNets: Set<String> = []
        for instance in netlist.instances {
            for gate in Set(instance.cell.devices.map(\.gate)) {
                let net = instance.net(gate)
                guard !rails.contains(net) else { continue }
                sinkNets.insert(net)
            }
        }
        for net in sinkNets.sorted() {
            guard primaries.contains(net) || driverOf[net] != nil else {
                throw RouteError.noDriver(net: net)
            }
        }
        for net in netlist.outputs.sorted() where !rails.contains(net) {
            guard driverOf[net] != nil else {
                throw RouteError.undrivenOutput(net: net)
            }
        }
        return SignalSourceSummary(driverOf: driverOf)
    }

    /// Topologically order instances so every net's driver precedes its sinks.
    private func ordered(_ netlist: GateLevelNetlist) throws -> [GateLevelNetlist.Instance] {
        let sourceSummary = try validateSignalSources(in: netlist)
        let primaries = Set(netlist.inputs).union([netlist.vpwr, netlist.vgnd])
        let driverOf = sourceSummary.driverOf
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
                // Place the remaining instances in order; the channel router wires the
                // back-edges regardless of left/right placement.
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
    private func rect(
        _ role: StandardCellLayoutProfile.LayerRole,
        _ x: Double,
        _ y: Double,
        _ w: Double,
        _ h: Double
    ) -> LayoutShape {
        let layer = profile.layerReference(for: role)
        return LayoutShape(
            layer: LayoutLayerID(name: layer.name, purpose: layer.purpose),
            geometry: .rect(LayoutRect(
                origin: LayoutPoint(x: x, y: y),
                size: LayoutSize(width: w, height: h)
            ))
        )
    }

    private func label(
        _ t: String,
        _ role: StandardCellLayoutProfile.LayerRole,
        _ x: Double,
        _ y: Double
    ) -> LayoutLabel {
        let layer = profile.labelLayerReference(for: role)
        return LayoutLabel(
            text: t,
            position: LayoutPoint(x: x, y: y),
            layer: LayoutLayerID(name: layer.name, purpose: layer.purpose)
        )
    }

    private func minimumSpacing(for role: StandardCellLayoutProfile.LayerRole) throws -> Double {
        let reference = profile.layerReference(for: role)
        let layer = LayoutLayerID(name: reference.name, purpose: reference.purpose)
        guard let spacing = layoutTechnology.ruleSet(for: layer)?.minSpacing else {
            throw RouteError.missingMinimumSpacing(layer: reference.name)
        }
        return spacing
    }

    private var layoutPolicy: StandardCellLayoutProfile.GeneratedCellLayout {
        profile.generatedCellLayout
    }

    private var routingPolicy: StandardCellLayoutProfile.CircuitRouting {
        profile.circuitRouting
    }

    private func signalTrackPitch() throws -> Double {
        try routingPolicy.signalTrackAccessPadWidth
            + minimumSpacing(for: routingPolicy.signalTrackSpacingLayer)
            + routingPolicy.signalTrackRuleMargin
    }

    /// Lift a local gate tap up to a signal track through the profile-declared contact,
    /// riser, and via stack. Contact cuts and vias are kept at distinct y locations.
    private func viaUp(_ x: Double, trackY: Double) -> [LayoutShape] {
        let p = layoutPolicy
        let y = p.fieldY
        let localPadHalf = p.localInterconnectPadSize / 2
        let contactHalf = p.contactSize / 2
        let metalHalf = p.metalRiserWidth / 2
        let viaHalf = p.outputViaSize / 2
        return [
            rect(.localInterconnect, x - localPadHalf, y - localPadHalf, p.localInterconnectPadSize, p.localInterconnectPadSize),
            rect(.localInterconnectToMetalContact, x - contactHalf, y - contactHalf, p.contactSize, p.contactSize),
            rect(.metal1, x - metalHalf, y - metalHalf, p.metalRiserWidth, (trackY + metalHalf) - (y - metalHalf)),
            rect(.metal1ToMetal2Via, x - viaHalf, trackY - viaHalf, p.outputViaSize, p.outputViaSize),
        ]
    }

    /// Tap a driver cell's output bus up to a signal routing track through the
    /// profile-selected intermediate routing layer.
    private func driverTap(_ x: Double, trackY: Double) -> [LayoutShape] {
        let p = layoutPolicy
        let busY = p.outputBusY
        let metalHalf = p.metalRiserWidth / 2
        let viaHalf = p.outputViaSize / 2
        return [
            rect(.metal1, x - metalHalf, busY - metalHalf, p.metalRiserWidth, p.metalRiserWidth),
            rect(.metal1ToMetal2Via, x - viaHalf, busY - viaHalf, p.outputViaSize, p.outputViaSize),
            rect(.metal1, x - metalHalf, busY - metalHalf, p.metalRiserWidth, (trackY + metalHalf) - (busY - metalHalf)),
            rect(.metal1ToMetal2Via, x - viaHalf, trackY - viaHalf, p.outputViaSize, p.outputViaSize),
        ]
    }

    /// Gate input contact stack at column-left `gx`, field y.
    private func gateInputContact(_ gx: Double) -> [LayoutShape] {
        let p = layoutPolicy
        let cx = gx + p.gateLabelOffsetX
        let y = p.fieldY
        let localPadHalf = p.localInterconnectPadSize / 2
        let contactHalf = p.contactSize / 2
        let implantHalf = p.gateContactImplantSize / 2
        return [
            rect(.gateConductor, cx - localPadHalf, y - localPadHalf, p.localInterconnectPadSize, p.localInterconnectPadSize),
            rect(.gateContactImplant, cx - implantHalf, y - implantHalf, p.gateContactImplantSize, p.gateContactImplantSize),
            rect(.contactCut, cx - contactHalf, y - contactHalf, p.contactSize, p.contactSize),
            rect(.localInterconnect, cx - localPadHalf, y - localPadHalf, p.localInterconnectPadSize, p.localInterconnectPadSize),
        ]
    }

    /// Tie a gate's field contact straight to a power rail with one local strap. Used when
    /// a gate input is a constant rail: the gate is a constant, not a routed signal, so it
    /// bonds to the rail in place.
    private func railStrap(_ cx: Double, toVGND: Bool) -> [LayoutShape] {
        let p = layoutPolicy
        let routing = routingPolicy
        let fieldY = p.fieldY
        let localPadHalf = p.localInterconnectPadSize / 2
        if toVGND {
            return [rect(
                .localInterconnect,
                cx - localPadHalf,
                routing.constantGroundStrapTopY,
                p.localInterconnectPadSize,
                fieldY - routing.constantGroundStrapTopY
            )]
        }
        return [rect(
            .localInterconnect,
            cx - localPadHalf,
            fieldY,
            p.localInterconnectPadSize,
            routing.constantPowerStrapTopY - fieldY
        )]
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
        let p = layoutPolicy
        let routing = routingPolicy
        let outputBusHalf = p.outputBusWidth / 2

        // 1) Place each cell, translate its geometry, remap net labels.
        var shapes: [LayoutShape] = []
        var labels: [LayoutLabel] = []
        for placedCell in placed {
            for shape in placedCell.cell.shapes { shapes.append(try shifted(shape, dx: placedCell.offsetX)) }
            // Keep only the per-cell power-rail labels. Every signal net (primary inputs,
            // internal nets, the output) is physically ROUTED and labelled ONCE on its
            // signal track below; same-name gate labels on separate cells do not merge in
            // external extraction, so a multi-fanout primary input would otherwise extract
            // as open nets.
            for label in placedCell.cell.labels where label.text == placedCell.inst.cell.vpwr || label.text == placedCell.inst.cell.vgnd {
                labels.append(LayoutLabel(
                    text: placedCell.inst.net(label.text),
                    position: LayoutPoint(x: label.position.x + placedCell.offsetX, y: label.position.y),
                    layer: label.layer
                ))
            }
        }
        let rightEdge = (placed.last.map { $0.offsetX + $0.cell.width } ?? 0)

        // 2) Continuous well and power/ground rails spanning the whole row.
        let nWellBottomY = p.pmosBottomY - p.nWellBottomOffset
        shapes.append(rect(.nWell, p.nWellOriginX, nWellBottomY, rightEdge + p.nWellHorizontalExtension, p.nWellTopY - nWellBottomY))
        shapes.append(rect(.localInterconnect, -p.firstContactX, p.powerRailY, rightEdge + p.firstContactX * 2, p.powerRailHeight))
        shapes.append(rect(.localInterconnect, -p.firstContactX, p.groundRailY, rightEdge + p.firstContactX * 2, p.groundRailHeight))

        // 3) Route each internal net on its own signal track. Layer separation avoids
        //    same-layer crossings, so
        //    arbitrary connectivity works: multi-fanout, non-adjacent, and feedback.
        for p in placed {
            for g in Set(p.inst.cell.devices.map(\.gate)).sorted() {
                let net = p.inst.net(g)
                guard let gateLocalX = p.cell.gateNetX[g] else {
                    throw RouteError.missingGateGeometry(instance: p.inst.name, gate: g)
                }
                let cx = p.offsetX + gateLocalX + layoutPolicy.gateLabelOffsetX
                shapes.append(contentsOf: gateInputContact(p.offsetX + gateLocalX))
                // A gate tied to a rail is a constant: bond it to the rail in place. A gate
                // on a signal net taps up to that net's routed signal track.
                if net == netlist.vgnd {
                    shapes.append(contentsOf: railStrap(cx, toVGND: true))
                } else if net == netlist.vpwr {
                    shapes.append(contentsOf: railStrap(cx, toVGND: false))
                }
            }
        }
        // Route EVERY signal net (including primary inputs, which fan out to several gates)
        // on its own track: the driver (if any) taps its output bus, each sink taps its
        // gate contact, and primary inputs/outputs get one port label. Internal nets are
        // matched by topology.
        let antennaSiteByID = try validatedAntennaSiteMap(antennaPlan, netlist: netlist, routeAnalysis: routeAnalysis)
        for net in routeAnalysis.allNets {
            let sinks = routeAnalysis.sinkTapsByNet[net] ?? []
            let trackY = routeAnalysis.trackYByNet[net] ?? routing.firstSignalTrackY
            var xs = sinks.map(\.centerXMicrons)
            if let drv = routeAnalysis.driverByNet[net] {
                let driverTapX = drv.offsetX + drv.cell.outputRightX - outputBusHalf
                shapes.append(contentsOf: driverTap(driverTapX, trackY: trackY))
                xs.append(driverTapX)
            } else if sinks.isEmpty {
                continue
            }
            for sink in sinks {
                if let site = antennaSiteByID[sink.id] {
                    shapes.append(contentsOf: antennaTieGenerator.shapes(for: site, baseY: routing.antennaTieBaseY))
                } else {
                    shapes.append(contentsOf: viaUp(sink.centerXMicrons, trackY: trackY))
                }
            }
            let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
            shapes.append(rect(.metal2, minX - outputBusHalf, trackY - outputBusHalf, max(maxX - minX, 0) + p.outputBusWidth, p.outputBusWidth))
            if primaries.contains(net) || netlist.outputs.contains(net) {
                labels.append(label(net, .metal2, (xs.first ?? minX), trackY))
            }
        }

        var cell = LayoutCell(name: netlist.name, shapes: shapes)
        cell.labels = labels
        return SynthesisResult(
            document: LayoutDocument(name: netlist.name, cells: [cell], topCellID: cell.id),
            antennaProtectionPlan: antennaPlan
        )
    }

    // MARK: - antenna-aware placement + net-span analysis

    /// Antenna-aware placement order: start topological (a valid driver-before-sink order), then
    /// run a few barycenter passes that pull each cell toward the average rank of the cells it
    /// shares a net with. Clustering connected cells shortens long signal tracks at scale.
    /// Reordering is LVS- and function-neutral; the channel router wires any order.
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
        for _ in 0..<routingPolicy.barycenterIterations {
            var next = pos
            for i in 0..<n where !neighbors[i].isEmpty {
                next[i] = neighbors[i].reduce(0.0) { $0 + pos[$1] } / Double(neighbors[i].count)
            }
            let ranked = (0..<n).sorted { next[$0] != next[$1] ? next[$0] < next[$1] : $0 < $1 }
            for (rank, i) in ranked.enumerated() { pos[i] = Double(rank) }
        }
        return (0..<n).sorted { pos[$0] != pos[$1] ? pos[$0] < pos[$1] : $0 < $1 }.map { insts[$0] }
    }

    /// One routed net's physical extent in the placed row. `gateLoadCount` is the number
    /// of sink gates it reaches. The span metrics feed profile/rule-driven antenna
    /// protection planning.
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
        let cell: StandardCellSynthesizer.CellLayout
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
            offsetX += cl.width + routingPolicy.cellGap
        }
        return placed
    }

    private func routeAnalysis(
        for netlist: GateLevelNetlist,
        placed: [PlacedCell]
    ) throws -> RouteAnalysis {
        _ = try validateSignalSources(in: netlist)
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
                let centerX = placedCell.offsetX + gateLocalX + layoutPolicy.gateLabelOffsetX
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
        let trackPitch = try signalTrackPitch()
        let trackYByNet = Dictionary(uniqueKeysWithValues: allNets.enumerated().map {
            ($0.element, routingPolicy.firstSignalTrackY + Double($0.offset) * trackPitch)
        })

        var spans: [NetSpan] = []
        var candidates: [AntennaProtectionCandidate] = []
        let drivenNets = netlist.drivenNets
        for net in allNets {
            let sinks = sinkTapsByNet[net] ?? []
            var xs = sinks.map(\.centerXMicrons)
            if let driver = driverByNet[net] {
                xs.append(driver.offsetX + driver.cell.outputRightX - layoutPolicy.outputBusWidth / 2)
            }
            guard let minX = xs.min(), let maxX = xs.max() else { continue }
            let span = NetSpan(
                net: net,
                minimumXMicrons: minX,
                maximumXMicrons: maxX,
                gateLoadCount: sinks.count
            )
            spans.append(span)

            let trackY = trackYByNet[net] ?? routingPolicy.firstSignalTrackY
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
    public func referenceSPICE(for netlist: GateLevelNetlist) throws -> String {
        _ = try validateSignalSources(in: netlist)
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
                let model = d.kind == .pmos ? profile.deviceModels.pmos : profile.deviceModels.nmos
                let bulk = d.kind == .pmos ? netlist.vpwr : netlist.vgnd
                let w = String(format: "%g", d.width), l = String(format: "%g", d.length)
                lines.append("X\(inst.name)_\(i) \(resolve(inst, d.drain)) \(resolve(inst, d.gate)) \(resolve(inst, d.source)) \(bulk) \(model) w=\(w) l=\(l)")
            }
        }
        lines.append(".ends")
        return lines.joined(separator: "\n")
    }
}
