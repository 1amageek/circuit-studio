import Foundation
import STAEngine
import Testing
@testable import CircuitStudioApp

@Suite("STA vs SPICE validation")
struct STAvsSPICEValidatorTests {
    @Test("A canonical STA path is validated against SPICE", .timeLimit(.minutes(6)))
    func canonicalPathValidates() async throws {
        let launchSlew = 40e-12
        let load = 1e-15
        let cell = try CMOSGateNetlist.inverter(name: "inv")
        let timing = try await TimingCharacterizationTestCache.shared.characterizeCell(
            cell,
            inputSlews: [20e-12, 80e-12, 320e-12],
            outputLoads: [0.5e-15, 2e-15, 8e-15]
        )
        let arc = try #require(timing.arc(fromInput: "A"))
        let delay = arc.delayFall.lookup(inputSlew: launchSlew, outputLoad: load)
        let outputSlew = arc.transitionFall.lookup(inputSlew: launchSlew, outputLoad: load)
        let netlist = SequentialNetlist(
            name: "chain",
            combinational: [
                .init(name: "g0", cell: cell, netMap: ["A": "qa", "Y": "db"]),
            ],
            dffs: [
                .init(name: "ffA", d: "x", clk: "clk", q: "qa"),
                .init(name: "ffB", d: "db", clk: "clk", q: "qb"),
            ],
            inputs: ["x"],
            outputs: ["qb"],
            clock: "clk"
        )
        let path = STAPath(
            modeID: "functional",
            cornerID: "tt",
            startpoint: "ffA/Q",
            endpoint: "ffB/D",
            arrival: delay,
            required: 5e-9,
            slack: 5e-9 - delay,
            stages: [
                STAPathStage(
                    instance: "g0",
                    cell: "inv",
                    inputPin: "A",
                    inputNet: "qa",
                    outputNet: "db",
                    inputEdge: .rise,
                    outputEdge: .fall,
                    delay: delay,
                    outputSlew: outputSlew,
                    load: load
                ),
            ]
        )

        let result = try await TimingCharacterizationTestSupport.withExclusiveSpiceSlot {
            try await STAvsSPICEValidator().validate(
                path: path,
                in: netlist,
                launchSlew: launchSlew,
                toleranceFraction: 0.20
            )
        }

        #expect(result.staDelay > 0)
        #expect(result.spiceDelay > 0)
        #expect(result.agrees)
    }
}
