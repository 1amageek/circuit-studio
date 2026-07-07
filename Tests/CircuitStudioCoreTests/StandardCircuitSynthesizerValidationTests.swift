import Foundation
import Testing
@testable import CircuitStudioApp

@Suite("Standard circuit synthesizer validation")
struct StandardCircuitSynthesizerValidationTests {
    @Test("A floating gate net fails before layout artifact generation", .timeLimit(.minutes(1)))
    func floatingGateNetFailsBeforeLayoutArtifactGeneration() throws {
        let netlist = GateLevelNetlist(
            name: "floating_gate",
            instances: [
                GateLevelNetlist.Instance(
                    name: "g0",
                    cell: try .inverter(name: "inv"),
                    netMap: ["A": "floating", "Y": "y"]
                ),
            ],
            inputs: [],
            output: "y"
        )

        #expect(throws: StandardCircuitSynthesizer.RouteError.noDriver(net: "floating")) {
            try makeStandardCircuitSynthesizer().synthesisResult(for: netlist)
        }
    }

    @Test("Reference SPICE fails on the same floating gate net contract", .timeLimit(.minutes(1)))
    func referenceSPICEFailsOnFloatingGateNetContract() throws {
        let netlist = GateLevelNetlist(
            name: "floating_gate_reference",
            instances: [
                GateLevelNetlist.Instance(
                    name: "g0",
                    cell: try .inverter(name: "inv"),
                    netMap: ["A": "floating", "Y": "y"]
                ),
            ],
            inputs: [],
            output: "y"
        )

        #expect(throws: StandardCircuitSynthesizer.RouteError.noDriver(net: "floating")) {
            _ = try makeStandardCircuitSynthesizer().referenceSPICE(for: netlist)
        }
    }

    @Test("An undriven primary output fails before layout artifact generation", .timeLimit(.minutes(1)))
    func undrivenPrimaryOutputFailsBeforeLayoutArtifactGeneration() throws {
        let netlist = GateLevelNetlist(
            name: "undriven_output",
            instances: [
                GateLevelNetlist.Instance(
                    name: "g0",
                    cell: try .inverter(name: "inv"),
                    netMap: ["A": "a", "Y": "internal"]
                ),
            ],
            inputs: ["a"],
            output: "y"
        )

        #expect(throws: StandardCircuitSynthesizer.RouteError.undrivenOutput(net: "y")) {
            try makeStandardCircuitSynthesizer().synthesisResult(for: netlist)
        }
    }

    @Test("A primary input driven by an instance fails before layout artifact generation", .timeLimit(.minutes(1)))
    func primaryInputDrivenByInstanceFailsBeforeLayoutArtifactGeneration() throws {
        let netlist = GateLevelNetlist(
            name: "primary_input_driver_conflict",
            instances: [
                GateLevelNetlist.Instance(
                    name: "g0",
                    cell: try .inverter(name: "inv0"),
                    netMap: ["A": "b", "Y": "a"]
                ),
                GateLevelNetlist.Instance(
                    name: "g1",
                    cell: try .inverter(name: "inv1"),
                    netMap: ["A": "a", "Y": "y"]
                ),
            ],
            inputs: ["a", "b"],
            output: "y"
        )

        #expect(throws: StandardCircuitSynthesizer.RouteError.primaryInputDriven(net: "a")) {
            try makeStandardCircuitSynthesizer().synthesisResult(for: netlist)
        }
    }

    @Test("A feedback loop with explicit drivers can still be synthesized", .timeLimit(.minutes(1)))
    func feedbackLoopWithExplicitDriversCanStillBeSynthesized() throws {
        let netlist = GateLevelNetlist(
            name: "feedback_with_drivers",
            instances: [
                GateLevelNetlist.Instance(
                    name: "g0",
                    cell: try .nor(name: "nor0", inputs: ["A", "B"]),
                    netMap: ["A": "s", "B": "qn", "Y": "q"]
                ),
                GateLevelNetlist.Instance(
                    name: "g1",
                    cell: try .nor(name: "nor1", inputs: ["A", "B"]),
                    netMap: ["A": "r", "B": "q", "Y": "qn"]
                ),
            ],
            inputs: ["s", "r"],
            output: "q"
        )

        let result = try makeStandardCircuitSynthesizer().synthesisResult(for: netlist)
        let topCell = try #require(result.document.cells.first { $0.id == result.document.topCellID })

        #expect(topCell.name == netlist.name)
        #expect(result.antennaProtectionPlan.designName == netlist.name)
    }
}

private func makeStandardCircuitSynthesizer() throws -> StandardCircuitSynthesizer {
    let profile = try StandardCellLayoutProfileCatalog.loadDefaultProfile()
    let technology = try LayoutTechnologyResource.bundled(resourceName: profile.targetTechnologyResourceName)
    return StandardCircuitSynthesizer(profile: profile, layoutTechnology: technology)
}
