import Foundation
import Testing
@testable import CircuitStudioCore

@Suite("PostLayoutSimulationService Tests")
struct PostLayoutSimulationServiceTests {

    @Test func buildPostLayoutNetlistInjectsParasiticsBeforeEnd() {
        let base = """
        * base
        V1 in 0 1
        R1 in out 1000
        .op
        .end
        """
        let ir = PEXParasiticIR(
            version: "1.0",
            cornerID: "tt",
            elements: [
                PEXParasiticElement(id: "r/out/1", kind: .resistor, nodeA: "out_1", nodeB: "out", value: 2.5),
                PEXParasiticElement(id: "c.out", kind: .capacitor, nodeA: "out_1", nodeB: nil, value: 1e-15),
                PEXParasiticElement(id: "cc", kind: .coupling, nodeA: "in", nodeB: "out_1", value: 2e-15),
            ]
        )

        let netlist = PostLayoutSimulationService().buildPostLayoutNetlist(
            baseNetlist: base,
            parasitics: ir
        )

        #expect(netlist.contains("* PEX corner: tt"))
        #expect(netlist.contains("RPEX_r_out_1 out_1 out 2.5"))
        #expect(netlist.contains("CPEX_c_out out_1 0 1e-15"))
        #expect(netlist.contains("CPEX_cc in out_1 2e-15"))
        #expect(netlist.split(separator: "\n").filter { $0.lowercased() == ".end" }.count == 1)
    }

    @Test func runPostLayoutOperatingPointCompletes() async throws {
        let base = """
        V1 in 0 1
        R1 in out 1000
        R2 out 0 1000
        .op
        .end
        """
        let ir = PEXParasiticIR(
            version: "1.0",
            cornerID: "tt",
            elements: [
                PEXParasiticElement(id: "rpex", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 1.0),
                PEXParasiticElement(id: "cpex", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 1e-15),
            ]
        )

        let result = try await PostLayoutSimulationService().runPostLayoutAnalysis(
            baseNetlist: base,
            parasitics: ir,
            command: .op
        )

        #expect(result.status == .completed)
        #expect(result.waveform != nil)
    }
}
