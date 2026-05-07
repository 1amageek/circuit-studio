import Foundation
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore
@testable import SchematicEditor

@Suite("CMOS Inverter Flow Tests")
struct CMOSInverterFlowTests {

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func cmosInverterRunsThroughExistingDesignFlow() async throws {
        let schematic = SchematicPreview.cmosInverterViewModel().document
        let nets = NetExtractor().extract(from: schematic)
        let netNames = Set(nets.map(\.name))

        #expect(netNames.isSuperset(of: ["vdd", "in", "out", "0"]))

        let testbench = Testbench(
            name: "Transient",
            analysisCommands: [
                .tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9)),
            ]
        )
        let baseNetlist = NetlistGenerator().generate(
            from: schematic,
            title: "CMOS inverter flow",
            testbench: testbench
        )
        #expect(baseNetlist.contains("MP1"))
        #expect(baseNetlist.contains("MN1"))
        #expect(baseNetlist.contains(".tran"))

        let preLayoutResult = try await SimulationService().runSPICE(
            source: baseNetlist,
            fileName: "cmos_inverter_pre.cir"
        )
        #expect(preLayoutResult.status == .completed)
        #expect((preLayoutResult.waveform?.pointCount ?? 0) > 50)

        let layoutOutput = try AutoLayoutService().generate(
            from: schematic,
            catalog: .standard()
        )
        #expect(!layoutOutput.document.cells.isEmpty)
        #expect(!layoutOutput.designUnit.componentToInstance.isEmpty)
        #expect(!layoutOutput.designUnit.netNameToLayoutNet.isEmpty)

        let verification = PhysicalVerificationService().runPrePEXVerification(
            schematic: schematic,
            layout: layoutOutput.document,
            tech: layoutOutput.tech,
            designUnit: layoutOutput.designUnit
        )
        #expect(verification.lvs.passed)
        #expect(verification.lvs.missingLayoutInstances.isEmpty)
        #expect(verification.lvs.missingLayoutNets.isEmpty)

        let pexIR = PEXParasiticIR(
            version: "1.0",
            cornerID: "tt_25c_1v0",
            units: .canonical,
            elements: [
                PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 1.0),
                PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 2e-15),
                PEXParasiticElement(id: "cc_in_out", kind: .coupling, nodeA: "in", nodeB: "out_pex", value: 0.5e-15),
            ]
        )
        let postLayoutService = PostLayoutSimulationService()
        let postLayoutNetlist = postLayoutService.buildPostLayoutNetlist(
            baseNetlist: baseNetlist,
            parasitics: pexIR
        )
        #expect(postLayoutNetlist.contains("RPEX_r_out out out_pex 1"))
        #expect(postLayoutNetlist.contains("CPEX_c_out out_pex 0 2e-15"))

        let postLayoutResult = try await postLayoutService.runPostLayoutAnalysis(
            baseNetlist: baseNetlist,
            parasitics: pexIR,
            command: .tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9))
        )
        #expect(postLayoutResult.status == .completed)
        #expect((postLayoutResult.waveform?.pointCount ?? 0) > 50)
    }
}
