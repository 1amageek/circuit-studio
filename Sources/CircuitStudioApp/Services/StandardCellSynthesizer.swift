import Foundation
import LayoutCore

/// Places and routes a `CMOSGateNetlist` into a profile-backed standard-cell layout
/// automatically — the SYSTEM does the geometry from the topology, not a human laying
/// rectangles. It also emits the matching reference schematic, so one netlist yields a
/// layout + schematic that are LVS-consistent by construction.
///
/// Algorithm (static-CMOS series/parallel class): detect which pull network is the
/// series chain (it fixes the gate column order and the internal, contact-less diffusion
/// nodes) and which is the parallel set (alternating rail/output diffusion regions);
/// place both rows on shared gate columns; route the output across all output diffusion
/// contacts through profile-selected layer roles; connect each rail's contacts to a rail
/// and body tap.
public struct StandardCellSynthesizer: Sendable {

    public enum SynthError: Error, LocalizedError, Equatable {
        case emptyNetwork(CMOSGateNetlist.DeviceKind)
        case notASeriesChain(rail: String)
        case bothNetworksSeries

        public var errorDescription: String? {
            switch self {
            case .emptyNetwork(let k): return "The \(k.rawValue) network is empty."
            case .notASeriesChain(let r): return "Could not trace a series chain from \(r) to the output."
            case .bothNetworksSeries: return "Both networks are series — not a static-CMOS series/parallel gate."
            }
        }
    }

    private let profile: StandardCellLayoutProfile

    public init(profile: StandardCellLayoutProfile) {
        self.profile = profile
    }

    /// A synthesized cell's geometry plus the pin metadata a circuit-level placer needs:
    /// where each gate input is and where the output bus is accessible.
    public struct CellLayout: Sendable {
        public let shapes: [LayoutShape]
        public let labels: [LayoutLabel]
        public let width: Double                 // active diffusion width (cell core)
        public let gateNetX: [String: Double]     // gate net -> gate column center x
        public let outputNet: String
        public let outputLeftX: Double            // output bus left extent
        public let outputRightX: Double
        public let fieldY: Double                 // y of in-field input pins
        public let outputBusY: Double             // y of the upper output bus
    }

    // MARK: - placement

    private struct RowPlan {
        let gateOrder: [String]      // gate nets, left to right
        let regionNets: [String]     // count == gateOrder.count + 1
        let regionContact: [Bool]
        let isSeries: Bool
    }

    private func planRow(
        _ devices: [CMOSGateNetlist.Device], rail: String, output: String, masterOrder: [String]?
    ) throws -> RowPlan {
        let internalNets = Set(devices.flatMap { [$0.source, $0.drain] }).subtracting([rail, output])
        if internalNets.isEmpty {
            // Parallel (or a single device): regions alternate rail / output.
            let order = masterOrder ?? devices.map(\.gate)
            var regions = [rail]
            for _ in order { regions.append(regions.last == rail ? output : rail) }
            return RowPlan(gateOrder: order, regionNets: regions,
                           regionContact: regions.map { _ in true }, isSeries: false)
        }
        // Series chain: walk rail -> ... -> output, recording gate order and nodes.
        var adjacency: [String: [(device: CMOSGateNetlist.Device, other: String)]] = [:]
        for d in devices {
            adjacency[d.source, default: []].append((d, d.drain))
            adjacency[d.drain, default: []].append((d, d.source))
        }
        var regions = [rail]
        var order: [String] = []
        var used = Set<String>()
        var current = rail
        while current != output {
            guard let edge = adjacency[current]?.first(where: { !used.contains($0.device.name) }) else {
                throw SynthError.notASeriesChain(rail: rail)
            }
            order.append(edge.device.gate)
            used.insert(edge.device.name)
            regions.append(edge.other)
            current = edge.other
        }
        return RowPlan(gateOrder: order, regionNets: regions,
                       regionContact: regions.map { $0 == rail || $0 == output }, isSeries: true)
    }

    private func hasInternalNode(_ devices: [CMOSGateNetlist.Device], rail: String, output: String) -> Bool {
        !Set(devices.flatMap { [$0.source, $0.drain] }).subtracting([rail, output]).isEmpty
    }

    // MARK: - geometry profile

    private var layoutPolicy: StandardCellLayoutProfile.GeneratedCellLayout {
        profile.generatedCellLayout
    }

    private func gateX(_ i: Int) -> Double {
        layoutPolicy.gateOriginX + Double(i) * layoutPolicy.gatePitch
    }

    private func diffWidth(_ k: Int) -> Double {
        layoutPolicy.diffusionBaseWidth + Double(k - 1) * layoutPolicy.gatePitch
    }

    /// Contact x for diffusion region `j` of `k` gates.
    private func contactX(_ j: Int, _ k: Int, _ diffW: Double) -> Double {
        let p = layoutPolicy
        if j == 0 { return p.firstContactX }
        if j == k { return diffW - p.diffusionRightContactInset }
        let gateRight = gateX(j - 1) + p.gateLength
        let gateLeft = gateX(j)
        return (gateRight + gateLeft) / 2 - p.contactSize / 2
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

    // MARK: - synthesis

    /// Place + route the netlist into a profile-backed layout document.
    public func synthesize(_ netlist: CMOSGateNetlist) throws -> LayoutDocument {
        let cl = try layout(netlist)
        var cell = LayoutCell(name: netlist.name, shapes: cl.shapes)
        cell.labels = cl.labels
        return LayoutDocument(name: netlist.name, cells: [cell], topCellID: cell.id)
    }

    /// Place + route the netlist into cell geometry + pin metadata.
    public func layout(_ netlist: CMOSGateNetlist) throws -> CellLayout {
        let nmos = netlist.nmos, pmos = netlist.pmos
        guard !nmos.isEmpty else { throw SynthError.emptyNetwork(.nmos) }
        guard !pmos.isEmpty else { throw SynthError.emptyNetwork(.pmos) }

        let nmosSeries = hasInternalNode(nmos, rail: netlist.vgnd, output: netlist.output)
        let pmosSeries = hasInternalNode(pmos, rail: netlist.vpwr, output: netlist.output)
        if nmosSeries && pmosSeries { throw SynthError.bothNetworksSeries }

        // The series network fixes the gate column order; the inverter falls back to the
        // single gate order.
        let master: [String]
        if nmosSeries {
            master = try planRow(nmos, rail: netlist.vgnd, output: netlist.output, masterOrder: nil).gateOrder
        } else if pmosSeries {
            master = try planRow(pmos, rail: netlist.vpwr, output: netlist.output, masterOrder: nil).gateOrder
        } else {
            master = nmos.map(\.gate)
        }
        let nmosPlan = try planRow(nmos, rail: netlist.vgnd, output: netlist.output,
                                   masterOrder: nmosSeries ? nil : master)
        let pmosPlan = try planRow(pmos, rail: netlist.vpwr, output: netlist.output,
                                   masterOrder: pmosSeries ? nil : master)

        let k = master.count
        let p = layoutPolicy
        let diffW = diffWidth(k)
        let midX = diffW / 2
        var shapes: [LayoutShape] = []
        var labels: [LayoutLabel] = []

        // Active diffusion + implants for both rows.
        shapes.append(rect(.diffusion, 0, p.nmosY, diffW, p.deviceWidth))
        shapes.append(rect(
            .nImplant,
            -p.implantMargin,
            p.nmosY - p.implantMargin,
            diffW + p.implantMargin * 2,
            p.deviceWidth + p.implantMargin * 2
        ))
        shapes.append(rect(.diffusion, 0, p.pmosBottomY, diffW, p.deviceWidth))
        shapes.append(rect(
            .pImplant,
            -p.implantMargin,
            p.pmosBottomY - p.implantMargin,
            diffW + p.implantMargin * 2,
            p.deviceWidth + p.implantMargin * 2
        ))

        // Shared vertical gate conductors labelled with their net.
        var gateNetX: [String: Double] = [:]
        for i in 0..<k {
            shapes.append(rect(.gateConductor, gateX(i), p.gateBottomY, p.gateLength, p.gateHeight))
            labels.append(label(master[i], .gateConductor, gateX(i) + p.gateLabelOffsetX, p.gateLabelY))
            gateNetX[master[i]] = gateX(i)
        }

        // Source/drain contacts for both rows.
        let nmosCY = p.nmosY + p.activeContactYInset
        let pmosCY = p.pmosBottomY + p.activeContactYInset
        func contacts(_ plan: RowPlan, _ cy: Double) {
            for j in 0...k where plan.regionContact[j] {
                shapes.append(rect(.contactCut, contactX(j, k, diffW), cy, p.contactSize, p.contactSize))
            }
        }
        contacts(nmosPlan, nmosCY)
        contacts(pmosPlan, pmosCY)

        // Output routing: an upper bus joins every output diffusion contact through the
        // profile-selected local pad, contact, riser, and via stack. Keeping the output
        // bus off the input-contact field prevents circuit-level sink contacts from
        // shorting against the cell output at the same x.
        let nmosOutX = (0...k).filter { nmosPlan.regionNets[$0] == netlist.output }.map { contactX($0, k, diffW) }
        let pmosOutX = (0...k).filter { pmosPlan.regionNets[$0] == netlist.output }.map { contactX($0, k, diffW) }
        let allOutX = nmosOutX + pmosOutX
        let busY = p.outputBusY
        let metalRiserHalf = p.metalRiserWidth / 2
        let viaHalf = p.outputViaSize / 2
        let busHalf = p.outputBusWidth / 2
        func outputRiser(_ x: Double, fromY cy: Double) {
            shapes.append(rect(
                .localInterconnect,
                x - p.localInterconnectPadInset,
                cy - p.localInterconnectPadInset,
                p.localInterconnectPadSize,
                p.localInterconnectPadSize
            ))
            shapes.append(rect(.localInterconnectToMetalContact, x - p.contactSize / 2, cy, p.contactSize, p.contactSize))
            shapes.append(rect(
                .metal1,
                x - metalRiserHalf,
                cy - p.localInterconnectPadInset,
                p.metalRiserWidth,
                (busY + metalRiserHalf) - (cy - p.localInterconnectPadInset)
            ))
            shapes.append(rect(.metal1ToMetal2Via, x - viaHalf, busY - viaHalf, p.outputViaSize, p.outputViaSize))
        }
        for x in nmosOutX { outputRiser(x, fromY: nmosCY) }
        for x in pmosOutX { outputRiser(x, fromY: pmosCY) }
        let busL = (allOutX.min() ?? 0) - busHalf
        let busR = (allOutX.max() ?? 0) + busHalf
        shapes.append(rect(.metal2, busL, busY - busHalf, busR - busL, p.outputBusWidth))
        labels.append(label(netlist.output, .metal2, (allOutX.first ?? midX), busY))

        // VGND rail (bottom) + stubs from every VGND contact + p+ substrate tap.
        let vgndX = (0...k).filter { nmosPlan.regionNets[$0] == netlist.vgnd }.map { contactX($0, k, diffW) }
        for x in vgndX {
            shapes.append(rect(.localInterconnect, x - p.localInterconnectPadInset, p.groundRailY, p.localInterconnectPadSize, p.groundStubHeight))
        }
        let railLeft = ((vgndX.min() ?? 0) - p.localInterconnectPadInset)
        let railRight = ((vgndX.max() ?? diffW) + p.localInterconnectPadSize - p.localInterconnectPadInset)
        let groundRailLeft = min(railLeft, midX - p.railMinimumHalfWidth)
        let groundRailRight = max(railRight, midX + p.railMinimumHalfWidth)
        shapes.append(rect(.localInterconnect, groundRailLeft, p.groundRailY, groundRailRight - groundRailLeft, p.groundRailHeight))
        shapes.append(rect(.diffusion, midX - p.tapDiffusionSize / 2, p.groundTapDiffusionY, p.tapDiffusionSize, p.tapDiffusionSize))
        shapes.append(rect(.pImplant, midX - p.tapImplantSize / 2, p.groundTapImplantY, p.tapImplantSize, p.tapImplantSize))
        shapes.append(rect(.contactCut, midX - p.contactSize / 2, p.groundRailY, p.contactSize, p.contactSize))
        labels.append(label(netlist.vgnd, .localInterconnect, midX, p.groundLabelY))

        // Power rail (top), stubs from every power contact, and well tap.
        let vpwrX = (0...k).filter { pmosPlan.regionNets[$0] == netlist.vpwr }.map { contactX($0, k, diffW) }
        for x in vpwrX {
            shapes.append(rect(.localInterconnect, x - p.localInterconnectPadInset, p.powerStubY, p.localInterconnectPadSize, p.powerStubHeight))
        }
        let prLeft = ((vpwrX.min() ?? 0) - p.localInterconnectPadInset)
        let prRight = ((vpwrX.max() ?? diffW) + p.localInterconnectPadSize - p.localInterconnectPadInset)
        let powerRailLeft = min(prLeft, midX - p.railMinimumHalfWidth)
        let powerRailRight = max(prRight, midX + p.railMinimumHalfWidth)
        shapes.append(rect(.localInterconnect, powerRailLeft, p.powerRailY, powerRailRight - powerRailLeft, p.powerRailHeight))
        shapes.append(rect(.diffusion, midX - p.tapDiffusionSize / 2, p.powerTapDiffusionY, p.tapDiffusionSize, p.tapDiffusionSize))
        shapes.append(rect(.nImplant, midX - p.tapImplantSize / 2, p.powerTapImplantY, p.tapImplantSize, p.tapImplantSize))
        shapes.append(rect(.contactCut, midX - p.contactSize / 2, p.powerTapContactY, p.contactSize, p.contactSize))
        labels.append(label(netlist.vpwr, .localInterconnect, midX, p.powerLabelY))

        // Well enclosing the PMOS diffusion and well tap.
        let nWellBottomY = p.pmosBottomY - p.nWellBottomOffset
        shapes.append(rect(.nWell, p.nWellOriginX, nWellBottomY, diffW + p.nWellHorizontalExtension, p.nWellTopY - nWellBottomY))

        return CellLayout(
            shapes: shapes, labels: labels, width: diffW, gateNetX: gateNetX,
            outputNet: netlist.output, outputLeftX: busL, outputRightX: busR,
            fieldY: p.fieldY,
            outputBusY: p.outputBusY
        )
    }

    /// The reference schematic for `netlist`, ports matching the layout's labelled nets.
    public func schematic(_ netlist: CMOSGateNetlist) -> String {
        let gateNets = orderedGates(netlist)
        let ports = (gateNets + [netlist.output, netlist.vpwr, netlist.vgnd]).joined(separator: " ")
        var lines = ["* synthesized \(netlist.name)", ".subckt \(netlist.name) \(ports)"]
        for (i, d) in netlist.devices.enumerated() {
            let model = d.kind == .pmos ? profile.deviceModels.pmos : profile.deviceModels.nmos
            let bulk = d.kind == .pmos ? netlist.vpwr : netlist.vgnd
            let w = String(format: "%g", d.width), l = String(format: "%g", d.length)
            lines.append("X\(i) \(d.drain) \(d.gate) \(d.source) \(bulk) \(model) w=\(w) l=\(l)")
        }
        lines.append(".ends")
        return lines.joined(separator: "\n")
    }

    private func orderedGates(_ netlist: CMOSGateNetlist) -> [String] {
        var seen = Set<String>(), order: [String] = []
        for d in netlist.devices where !seen.contains(d.gate) { seen.insert(d.gate); order.append(d.gate) }
        return order
    }
}
