import Foundation
import Testing
@testable import CircuitStudioApp

/// BC2 — automatic partitioning. Tool-independent checks that the partition is
/// information-preserving (the blocks' instances reassemble the original) and that the
/// inter-block nets are exactly the nets a block drives that another block consumes.
@Suite("Netlist partitioner")
struct NetlistPartitionerTests {

    @Test("Partitioning preserves every instance across the blocks")
    func preservesInstances() throws {
        let netlist = ACC4CPUGenerator().gateLevelNetlist()
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
            .init(name: "g0", cell: .inverter(name: "inv"), netMap: ["A": "a", "Y": "n1"]),
            .init(name: "g1", cell: .inverter(name: "inv"), netMap: ["A": "n1", "Y": "n2"]),
            .init(name: "g2", cell: .inverter(name: "inv"), netMap: ["A": "n2", "Y": "n3"]),
            .init(name: "g3", cell: .inverter(name: "inv"), netMap: ["A": "n3", "Y": "y"]),
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
}
