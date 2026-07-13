import Foundation
import Testing
import PEXEngine
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
                PEXParasiticElement(id: "l.out", kind: .inductor, nodeA: "out_1", nodeB: "out", value: 3e-9),
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
        #expect(netlist.contains("LPEX_l_out out_1 out 3e-09"))
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

    @Test func buildHierarchicalPostLayoutNetlistPreservesSubcircuitBoundary() throws {
        let base = """
        .subckt TOP in out
        R1 in out 1000
        .ends TOP
        V1 in 0 1
        XTOP in out TOP
        .end
        """
        let vdd = NetName("IN")
        let out = NetName("OUT")
        let inPin = NodeName("in")
        let outPin = NodeName("out")
        let ir = ParasiticIR(
            version: ParasiticIR.currentVersion,
            cornerID: "tt",
            units: .canonical,
            nets: [
                ParasiticNet(
                    name: vdd,
                    nodes: [ParasiticNode(name: inPin, kind: .pin, instancePath: nil, coordinate: nil)],
                    totalGroundCapF: 0,
                    totalCouplingCapF: 0,
                    totalResistanceOhm: 0
                ),
                ParasiticNet(
                    name: out,
                    nodes: [ParasiticNode(name: outPin, kind: .pin, instancePath: nil, coordinate: nil)],
                    totalGroundCapF: 0,
                    totalCouplingCapF: 0,
                    totalResistanceOhm: 0
                ),
            ],
            elements: [ParasiticElement(
                id: "Rout",
                kind: .resistor,
                nodeA: NodeRef(netName: vdd, nodeName: inPin),
                nodeB: NodeRef(netName: out, nodeName: outPin),
                value: 2,
                source: .extracted
            )],
            metadata: ["topCell": "TOP"]
        )

        let netlist = try PostLayoutSimulationService().buildHierarchicalPostLayoutNetlist(
            baseNetlist: base,
            canonicalIR: ir,
            topCell: "TOP"
        )

        #expect(netlist.contains("XPEX_tt in out PEX_TOP_tt"))
        #expect(netlist.contains(".subckt PEX_TOP_tt in out"))
        #expect(netlist.range(of: "XPEX_tt in out PEX_TOP_tt")!.lowerBound < netlist.range(of: ".ends TOP")!.lowerBound)
        #expect(netlist.split(separator: "\n").filter { $0.lowercased() == ".end" }.count == 1)
    }
}
