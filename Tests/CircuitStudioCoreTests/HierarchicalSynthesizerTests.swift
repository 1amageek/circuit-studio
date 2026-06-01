import Foundation
import Testing
@testable import CircuitStudioApp

@Suite("Hierarchical synthesizer")
struct HierarchicalSynthesizerTests {

    @Test("Synthesizes disconnected blocks without requiring signal maze routes")
    func synthesizesDisconnectedBlocks() throws {
        let netlist = GateLevelNetlist(name: "disconnected", instances: [
            .init(name: "a0", cell: .inverter(name: "inv"), netMap: ["A": "a", "Y": "a1"]),
            .init(name: "b0", cell: .inverter(name: "inv"), netMap: ["A": "b", "Y": "b1"]),
            .init(name: "a1", cell: .inverter(name: "inv"), netMap: ["A": "a1", "Y": "ay"]),
            .init(name: "b1", cell: .inverter(name: "inv"), netMap: ["A": "b1", "Y": "by"]),
        ], inputs: ["a", "b"], outputs: ["ay", "by"])

        let document = try HierarchicalSynthesizer(blocks: 2, columns: 2).synthesize(netlist)
        let cell = try #require(document.cells.first { $0.id == document.topCellID } ?? document.cells.first)
        let labels = Set(cell.labels.map(\.text))

        #expect(labels.isSuperset(of: ["a", "b", "ay", "by"]))
    }
}
