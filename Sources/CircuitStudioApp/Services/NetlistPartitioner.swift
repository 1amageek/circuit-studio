import Foundation

/// Splits a flat `GateLevelNetlist` into block sub-netlists for hierarchical place & route.
/// Each block keeps a contiguous slice of the instances; a net that a block drives or
/// consumes but that also touches another block (or a chip primary I/O) becomes a PORT of
/// that block, so the synthesizer exposes it on a met2 pin the inter-block router can reach.
/// Nets entirely inside one block stay internal. The partition is information-preserving:
/// the union of the blocks' instances is the original netlist, so a flattened layout of the
/// routed blocks is LVS-equivalent to the flat netlist.
public struct NetlistPartitioner: Sendable {

    public enum PartitionError: Error, LocalizedError, Equatable {
        case nonPositiveBlocks

        public var errorDescription: String? {
            switch self {
            case .nonPositiveBlocks: return "The partitioner needs blocks >= 1."
            }
        }
    }

    public struct Result: Sendable {
        public let blocks: [GateLevelNetlist]
        /// Nets that cross block boundaries (a port of >= 2 blocks) — routed on met3.
        public let interBlockNets: [String]
        /// Chip primary I/O nets (kept as top-level ports).
        public let primaryPorts: [String]
    }

    public init() {}

    public func partition(_ netlist: GateLevelNetlist, blocks blockCount: Int) throws -> Result {
        guard blockCount >= 1 else { throw PartitionError.nonPositiveBlocks }
        let rails: Set<String> = [netlist.vpwr, netlist.vgnd]
        let primaryInputs = Set(netlist.inputs)
        let primaryOutputs = Set(netlist.outputs)

        // Which block drives / consumes each net.
        let instances = netlist.instances
        let n = instances.count
        let perBlock = max(1, (n + blockCount - 1) / blockCount)
        var blockOf: [String: Int] = [:]   // instance name -> block index (by driver)
        var groups: [[GateLevelNetlist.Instance]] = Array(repeating: [], count: blockCount)
        for (i, inst) in instances.enumerated() {
            let b = min(i / perBlock, blockCount - 1)
            groups[b].append(inst)
            blockOf[inst.name] = b
        }

        // Driver block of each net (by the instance that drives it).
        var driverBlock: [String: Int] = [:]
        for inst in instances { driverBlock[netlist.driverNet(of: inst)] = blockOf[inst.name] }

        // Per block: which nets it drives / consumes.
        func driven(_ g: [GateLevelNetlist.Instance]) -> Set<String> { Set(g.map { netlist.driverNet(of: $0) }) }
        func consumed(_ g: [GateLevelNetlist.Instance]) -> Set<String> {
            var s = Set<String>()
            for inst in g { for gate in Set(inst.cell.devices.map(\.gate)) { s.insert(inst.net(gate)) } }
            return s.subtracting(rails)
        }
        let drivenSets = groups.map(driven)
        let consumedSets = groups.map(consumed)
        let allDriven = drivenSets.reduce(into: Set<String>()) { $0.formUnion($1) }
        let allConsumed = consumedSets.reduce(into: Set<String>()) { $0.formUnion($1) }

        var result: [GateLevelNetlist] = []
        var interBlock = Set<String>()
        for b in 0..<blockCount where !groups[b].isEmpty {
            let dB = drivenSets[b], cB = consumedSets[b]
            // Outputs: nets this block drives that are a primary output OR consumed elsewhere.
            var outs: [String] = []
            for net in dB.sorted() where !rails.contains(net) {
                let consumedElsewhere = consumedSets.enumerated().contains { $0.offset != b && $0.element.contains(net) }
                if primaryOutputs.contains(net) || consumedElsewhere {
                    outs.append(net)
                    if consumedElsewhere { interBlock.insert(net) }
                }
            }
            // Inputs: nets this block consumes that are a primary input OR driven elsewhere.
            var ins: [String] = []
            for net in cB.sorted() where !rails.contains(net) {
                let drivenElsewhere = driverBlock[net].map { $0 != b } ?? false
                if primaryInputs.contains(net) || drivenElsewhere {
                    ins.append(net)
                    if drivenElsewhere { interBlock.insert(net) }
                }
            }
            result.append(GateLevelNetlist(name: "\(netlist.name)_b\(b)", instances: groups[b],
                                           inputs: ins, outputs: outs, vpwr: netlist.vpwr, vgnd: netlist.vgnd))
        }
        _ = (allDriven, allConsumed)
        let primaryPorts = (netlist.inputs + netlist.outputs).filter { !rails.contains($0) }
        return Result(blocks: result, interBlockNets: interBlock.sorted(), primaryPorts: primaryPorts)
    }
}
