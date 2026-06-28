import Foundation
import LayoutCore

/// End-to-end automatic hierarchical place & route: it partitions a flat netlist into blocks
/// (`NetlistPartitioner`), synthesizes each as a single-row cell (`StandardCircuitSynthesizer`),
/// tiles them into a 2-D grid (`GridFloorplanner`), maze-routes every cross-block signal net
/// over the cells on profile-selected routing layers (`MazeRouter`), and combs the power rails together
/// (`InterBlockRouter`) — producing one flattened layout that is LVS-equivalent to the flat
/// netlist. This is the scalable alternative to one ever-wider row: block count and grid
/// shape are free parameters, so a design grows in two dimensions, not one.
public struct HierarchicalSynthesizer: Sendable {

    public enum SynthError: Error, LocalizedError, Equatable {
        case noTopCell

        public var errorDescription: String? {
            switch self {
            case .noTopCell: return "The floorplan produced no top cell."
            }
        }
    }

    private let blocks: Int
    private let columns: Int

    public init(blocks: Int, columns: Int) {
        self.blocks = blocks
        self.columns = columns
    }

    public func synthesize(_ netlist: GateLevelNetlist) throws -> LayoutDocument {
        let part = try NetlistPartitioner().partition(netlist, blocks: blocks)
        let profile = try StandardCellLayoutProfileCatalog.loadDefaultProfile()
        let technology = try LayoutTechnologyResource.bundled(resourceName: profile.targetTechnologyResourceName)
        let circuitSynthesizer = StandardCircuitSynthesizer(profile: profile, layoutTechnology: technology)
        let docs = try part.blocks.map { try circuitSynthesizer.synthesize($0) }
        let floor = try GridFloorplanner().tile(docs, columns: columns, name: netlist.name)

        // Power rails first in the margins; boundaryNets empty so this is power only.
        let powered = try InterBlockRouter().route(floor, boundaryNets: [], powerNets: [netlist.vpwr, netlist.vgnd])
        guard var cell = powered.cells.first(where: { $0.id == powered.topCellID }) ?? powered.cells.first else {
            throw SynthError.noTopCell
        }

        // Every signal net that surfaces in >= 2 blocks must be joined (inter-block nets and
        // any primary I/O that fans out to several blocks). Maze-route them over the cells.
        let rails: Set<String> = [netlist.vpwr, netlist.vgnd]
        let pinsByNet = Dictionary(grouping: cell.labels.filter { !rails.contains($0.text) }, by: \.text)
        let primary = Set(netlist.inputs).union(netlist.outputs)
        var mazeNets: [MazeRouter.Net] = []
        for net in pinsByNet.keys.sorted() {
            guard let labels = pinsByNet[net], labels.count >= 2 else { continue }
            mazeNets.append(MazeRouter.Net(name: net, pins: labels.map(\.position)))
        }
        if !mazeNets.isEmpty {
            cell.shapes.append(contentsOf: try MazeRouter().route(mazeNets))
        }

        // Labels: a routed internal net is no longer a port (drop all its labels); a primary
        // I/O net keeps exactly one label (the chip port). Single-pin primary I/O is untouched.
        for (net, labels) in pinsByNet where labels.count >= 2 {
            cell.labels.removeAll { $0.text == net }
            if primary.contains(net), let keep = labels.first {
                cell.labels.append(keep)
            }
        }
        return LayoutDocument(name: netlist.name, cells: [cell], topCellID: cell.id)
    }
}
