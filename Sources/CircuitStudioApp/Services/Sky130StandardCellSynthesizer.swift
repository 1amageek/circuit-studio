import Foundation
import LayoutCore
import LayoutTech

/// Places and routes a `CMOSGateNetlist` into a Sky130 standard-cell LAYOUT
/// automatically — the SYSTEM does the geometry from the topology, not a human laying
/// rectangles. It also emits the matching reference schematic, so one netlist yields a
/// layout + schematic that are LVS-consistent by construction.
///
/// Algorithm (static-CMOS series/parallel class): detect which pull network is the
/// series chain (it fixes the gate column order and the internal, contact-less diffusion
/// nodes) and which is the parallel set (alternating rail/output diffusion regions);
/// place both rows on shared gate columns; route the output across all its diffusion
/// contacts with an li1 trunk; connect each rail's contacts to a rail + body tap.
public struct Sky130StandardCellSynthesizer: Sendable {

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

    public init() {}

    /// A synthesized cell's geometry plus the pin metadata a circuit-level placer needs:
    /// where each gate (input) poly is and where the output li1 trunk is accessible.
    public struct CellLayout: Sendable {
        public let shapes: [LayoutShape]
        public let labels: [LayoutLabel]
        public let width: Double                 // active diffusion width (cell core)
        public let gateNetX: [String: Double]     // gate net -> poly column centre x
        public let outputNet: String
        public let outputLeftX: Double            // output li1 trunk extent (field, y ~0.90)
        public let outputRightX: Double
        public static let fieldY = 0.90           // y of the in-field output trunk / input pins
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

    // MARK: - geometry constants

    // Gate pitch is wide enough (1.05) that a routed input poly contact on a gate clears
    // the cell's own output li1 trunk (which sits between gates for a parallel network),
    // so a cell can be a sink in a circuit without shorting its input to its output.
    private static let gate0X = 0.42, gatePitch = 1.05, gateLen = 0.16
    private static let nmosY = 0.0, pmosBot = 1.40, deviceW = 0.42
    private func gateX(_ i: Int) -> Double { Self.gate0X + Double(i) * Self.gatePitch }
    // Extra drain-side room (1.3 vs the minimal 1.0) so a routed input poly contact on a
    // gate clears the output li1 trunk when the cell is a sink in a circuit.
    private func diffWidth(_ k: Int) -> Double { 1.3 + Double(k - 1) * Self.gatePitch }

    /// Contact x for diffusion region `j` of `k` gates.
    private func contactX(_ j: Int, _ k: Int, _ diffW: Double) -> Double {
        if j == 0 { return 0.10 }
        if j == k { return diffW - 0.27 }
        let gateRight = gateX(j - 1) + Self.gateLen
        let gateLeft = gateX(j)
        return (gateRight + gateLeft) / 2 - 0.085
    }

    private func rect(_ layer: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> LayoutShape {
        LayoutShape(layer: Sky130LayoutTech.layer(layer),
                    geometry: .rect(LayoutRect(origin: LayoutPoint(x: x, y: y), size: LayoutSize(width: w, height: h))))
    }
    private func label(_ t: String, _ layer: String, _ x: Double, _ y: Double) -> LayoutLabel {
        LayoutLabel(text: t, position: LayoutPoint(x: x, y: y), layer: Sky130LayoutTech.layer(layer))
    }

    // MARK: - synthesis

    /// Place + route the netlist into a Sky130 layout document.
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
        let diffW = diffWidth(k)
        let midX = diffW / 2
        var shapes: [LayoutShape] = []
        var labels: [LayoutLabel] = []

        // Active diffusion + implants for both rows.
        shapes.append(rect("diff", 0, Self.nmosY, diffW, Self.deviceW))
        shapes.append(rect("nsdm", -0.125, -0.125, diffW + 0.25, Self.deviceW + 0.25))
        shapes.append(rect("diff", 0, Self.pmosBot, diffW, Self.deviceW))
        shapes.append(rect("psdm", -0.125, Self.pmosBot - 0.125, diffW + 0.25, Self.deviceW + 0.25))

        // Shared vertical poly gates (labelled with their net).
        var gateNetX: [String: Double] = [:]
        for i in 0..<k {
            shapes.append(rect("poly", gateX(i), -0.13, Self.gateLen, 2.08))
            labels.append(label(master[i], "poly", gateX(i) + 0.08, 1.10))
            gateNetX[master[i]] = gateX(i)
        }

        // Source/drain contacts for both rows.
        let nmosCY = 0.125, pmosCY = Self.pmosBot + 0.125
        func contacts(_ plan: RowPlan, _ cy: Double) {
            for j in 0...k where plan.regionContact[j] {
                shapes.append(rect("licon1", contactX(j, k, diffW), cy, 0.17, 0.17))
            }
        }
        contacts(nmosPlan, nmosCY)
        contacts(pmosPlan, pmosCY)

        // Output routing: an li1 trunk in the field joining every output diffusion
        // contact (both rows), with a vertical stub from each contact to the trunk.
        let nmosOutX = (0...k).filter { nmosPlan.regionNets[$0] == netlist.output }.map { contactX($0, k, diffW) }
        let pmosOutX = (0...k).filter { pmosPlan.regionNets[$0] == netlist.output }.map { contactX($0, k, diffW) }
        let allOutX = nmosOutX + pmosOutX
        let trunkLeft = (allOutX.min() ?? 0) - 0.08
        let trunkRight = (allOutX.max() ?? 0) + 0.25
        shapes.append(rect("li1", trunkLeft, 0.82, trunkRight - trunkLeft, 0.17))   // trunk
        for x in nmosOutX { shapes.append(rect("li1", x - 0.08, 0.045, 0.33, 0.945)) }   // up to trunk
        for x in pmosOutX { shapes.append(rect("li1", x - 0.08, 0.82, 0.33, 0.955)) }     // down to trunk
        labels.append(label(netlist.output, "li1", (allOutX.first ?? midX) + 0.08, 0.90))

        // VGND rail (bottom) + stubs from every VGND contact + p+ substrate tap.
        let vgndX = (0...k).filter { nmosPlan.regionNets[$0] == netlist.vgnd }.map { contactX($0, k, diffW) }
        for x in vgndX { shapes.append(rect("li1", x - 0.08, -1.08, 0.33, 1.455)) }
        let railLeft = ((vgndX.min() ?? 0) - 0.08)
        let railRight = ((vgndX.max() ?? diffW) + 0.25)
        shapes.append(rect("li1", min(railLeft, midX - 0.30), -1.08, max(railRight, midX + 0.30) - min(railLeft, midX - 0.30), 0.62))
        shapes.append(rect("diff", midX - 0.205, -1.20, 0.41, 0.41))
        shapes.append(rect("psdm", midX - 0.33, -1.325, 0.66, 0.66))
        shapes.append(rect("licon1", midX - 0.085, -1.08, 0.17, 0.17))
        labels.append(label(netlist.vgnd, "li1", midX, -0.70))

        // VPWR rail (top) + stubs from every VPWR contact + n+ n-well tap.
        let vpwrX = (0...k).filter { pmosPlan.regionNets[$0] == netlist.vpwr }.map { contactX($0, k, diffW) }
        for x in vpwrX { shapes.append(rect("li1", x - 0.08, 1.445, 0.33, 1.105)) }
        let prLeft = ((vpwrX.min() ?? 0) - 0.08)
        let prRight = ((vpwrX.max() ?? diffW) + 0.25)
        shapes.append(rect("li1", min(prLeft, midX - 0.30), 2.10, max(prRight, midX + 0.30) - min(prLeft, midX - 0.30), 0.45))
        shapes.append(rect("diff", midX - 0.205, 2.20, 0.41, 0.41))
        shapes.append(rect("nsdm", midX - 0.33, 2.075, 0.66, 0.66))
        shapes.append(rect("licon1", midX - 0.085, 2.32, 0.17, 0.17))
        labels.append(label(netlist.vpwr, "li1", midX, 2.30))

        // n-well enclosing the PMOS diffusion and the n-well tap.
        shapes.append(rect("nwell", -0.21, Self.pmosBot - 0.21, diffW + 0.42, (2.61 + 0.18) - (Self.pmosBot - 0.21)))

        return CellLayout(
            shapes: shapes, labels: labels, width: diffW, gateNetX: gateNetX,
            outputNet: netlist.output, outputLeftX: trunkLeft, outputRightX: trunkRight
        )
    }

    /// The reference schematic for `netlist`, ports matching the layout's labelled nets.
    public func schematic(_ netlist: CMOSGateNetlist) -> String {
        let gateNets = orderedGates(netlist)
        let ports = (gateNets + [netlist.output, netlist.vpwr, netlist.vgnd]).joined(separator: " ")
        var lines = ["* synthesized \(netlist.name)", ".subckt \(netlist.name) \(ports)"]
        for (i, d) in netlist.devices.enumerated() {
            let model = d.kind == .pmos ? "sky130_fd_pr__pfet_01v8" : "sky130_fd_pr__nfet_01v8"
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
