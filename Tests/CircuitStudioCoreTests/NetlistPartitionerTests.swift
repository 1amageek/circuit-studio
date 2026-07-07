import Foundation
import Testing
@testable import CircuitStudioApp

/// BC2 — automatic partitioning. Tool-independent checks that the partition is
/// information-preserving (the blocks' instances reassemble the original) and that the
/// inter-block nets are exactly the nets a block drives that another block consumes.
@Suite("Netlist partitioner")
struct NetlistPartitionerTests {

    private struct FixedPartitioningStrategy: NetlistPartitioningStrategy {
        let assignments: [Int]

        func assignment(for netlist: GateLevelNetlist, blockCount: Int, rails: Set<String>) throws -> [Int] {
            assignments
        }
    }

    @Test("Partitioning preserves every instance across the blocks")
    func preservesInstances() throws {
        let netlist = try ACC4CPUGenerator().gateLevelNetlist()
        let result = try NetlistPartitioner().partition(netlist, blocks: 4)
        let reassembled = Set(result.blocks.flatMap { $0.instances }.map(\.name))
        #expect(reassembled == Set(netlist.instances.map(\.name)))
        #expect(result.blocks.count <= 4)
        #expect(result.blocks.allSatisfy { !$0.instances.isEmpty })
    }

    @Test("Inter-block nets are exactly those driven in one block and consumed in another")
    func interBlockNetsAreCorrect() throws {
        // A 4-inverter chain split into 2 blocks: the middle net is the only crossing.
        let chain = GateLevelNetlist(name: "chain", instances: [
            .init(name: "g0", cell: try .inverter(name: "inv"), netMap: ["A": "a", "Y": "n1"]),
            .init(name: "g1", cell: try .inverter(name: "inv"), netMap: ["A": "n1", "Y": "n2"]),
            .init(name: "g2", cell: try .inverter(name: "inv"), netMap: ["A": "n2", "Y": "n3"]),
            .init(name: "g3", cell: try .inverter(name: "inv"), netMap: ["A": "n3", "Y": "y"]),
        ], inputs: ["a"], output: "y")
        let result = try NetlistPartitioner().partition(chain, blocks: 2)
        #expect(result.blocks.count == 2)
        #expect(result.interBlockNets == ["n2"])              // g1 (block0) -> g2 (block1)
        // Block 0 exposes n2 as an output; block 1 exposes n2 as an input.
        #expect(result.blocks[0].outputs.contains("n2"))
        #expect(result.blocks[1].inputs.contains("n2"))
        // Primary I/O stays at the top.
        #expect(Set(result.primaryPorts) == ["a", "y"])
    }

    @Test("Partitioning clusters connected components even when instances are interleaved")
    func clustersInterleavedChains() throws {
        let netlist = GateLevelNetlist(name: "interleaved", instances: [
            .init(name: "a0", cell: try .inverter(name: "inv"), netMap: ["A": "a", "Y": "a1"]),
            .init(name: "b0", cell: try .inverter(name: "inv"), netMap: ["A": "b", "Y": "b1"]),
            .init(name: "a1", cell: try .inverter(name: "inv"), netMap: ["A": "a1", "Y": "a2"]),
            .init(name: "b1", cell: try .inverter(name: "inv"), netMap: ["A": "b1", "Y": "b2"]),
            .init(name: "a2", cell: try .inverter(name: "inv"), netMap: ["A": "a2", "Y": "ay"]),
            .init(name: "b2", cell: try .inverter(name: "inv"), netMap: ["A": "b2", "Y": "by"]),
        ], inputs: ["a", "b"], outputs: ["ay", "by"])

        let result = try NetlistPartitioner().partition(netlist, blocks: 2)
        let blockNameSets = Set(result.blocks.map { Set($0.instances.map(\.name)) })

        #expect(result.interBlockNets.isEmpty)
        #expect(blockNameSets == [
            Set(["a0", "a1", "a2"]),
            Set(["b0", "b1", "b2"]),
        ])
        #expect(Set(result.primaryPorts) == ["a", "b", "ay", "by"])
    }

    @Test("Partitioning does not emit empty blocks when more blocks than instances are requested")
    func requestedMoreBlocksThanInstances() throws {
        let netlist = try GateLevelNetlist.inverterChain(name: "small", stages: 2)
        let result = try NetlistPartitioner().partition(netlist, blocks: 8)

        #expect(result.blocks.count == 2)
        #expect(result.blocks.allSatisfy { !$0.instances.isEmpty })
        #expect(Set(result.blocks.flatMap { $0.instances }.map(\.name)) == Set(netlist.instances.map(\.name)))
    }

    @Test("Empty netlists preserve primary ports and produce no blocks")
    func emptyNetlist() throws {
        let netlist = GateLevelNetlist(name: "empty", instances: [], inputs: ["a"], outputs: ["y"])
        let result = try NetlistPartitioner().partition(netlist, blocks: 4)

        #expect(result.blocks.isEmpty)
        #expect(result.interBlockNets.isEmpty)
        #expect(result.primaryPorts == ["a", "y"])
    }

    @Test("Partitioner rejects invalid strategy assignment counts")
    func rejectsInvalidAssignmentCount() throws {
        let netlist = try GateLevelNetlist.inverterChain(name: "bad_count", stages: 2)
        let partitioner = NetlistPartitioner(strategy: FixedPartitioningStrategy(assignments: [0]))

        #expect(throws: NetlistPartitioner.PartitionError.self) {
            _ = try partitioner.partition(netlist, blocks: 2)
        }
    }

    @Test("Partitioner rejects strategy block indexes outside the active block range")
    func rejectsOutOfRangeAssignments() throws {
        let netlist = try GateLevelNetlist.inverterChain(name: "bad_range", stages: 2)
        let partitioner = NetlistPartitioner(strategy: FixedPartitioningStrategy(assignments: [0, 3]))

        #expect(throws: NetlistPartitioner.PartitionError.self) {
            _ = try partitioner.partition(netlist, blocks: 2)
        }
    }

    @Test("Partitioner rejects strategy assignments that leave active blocks empty")
    func rejectsEmptyAssignedBlocks() throws {
        let netlist = try GateLevelNetlist.inverterChain(name: "bad_empty", stages: 3)
        let partitioner = NetlistPartitioner(strategy: FixedPartitioningStrategy(assignments: [0, 0, 0]))

        #expect(throws: NetlistPartitioner.PartitionError.self) {
            _ = try partitioner.partition(netlist, blocks: 2)
        }
    }
}
