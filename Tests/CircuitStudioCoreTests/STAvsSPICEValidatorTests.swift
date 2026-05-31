import Foundation
import Testing
@testable import CircuitStudioApp

/// BC1.3 — the trust anchor. STA's predicted critical-path delay must match a full CoreSpice
/// transient of the same gate chain (CoreSpice itself being the ngspice-validated oracle).
/// This is what licenses the timing axis to be trusted: the abstraction is scored by physics.
@Suite("STA vs SPICE validation")
struct STAvsSPICEValidatorTests {

    private func flipFlop(dataCap: Double) -> SequentialTiming {
        SequentialTiming(clkToQRise: .constant(120e-12), clkToQFall: .constant(120e-12),
                         qTransitionRise: .constant(40e-12), qTransitionFall: .constant(40e-12),
                         setupTime: 30e-12, holdTime: 10e-12, dataCapacitance: dataCap, clockCapacitance: 2e-15)
    }

    @Test("STA's predicted delay matches SPICE on a 4-inverter FF→FF path", .timeLimit(.minutes(6)))
    func inverterChainValidates() async throws {
        var lib = TimingLibrary()
        let inv = try await TimingCharacterizationTestCache.shared.characterizeCell(
            .inverter(name: "inv"),
            inputSlews: [20e-12, 80e-12, 320e-12],
            outputLoads: [0.5e-15, 2e-15, 8e-15]
        )
        lib.add(inv)
        lib.flipFlop = flipFlop(dataCap: inv.inputCapacitance["A"] ?? 1e-15)

        var insts: [GateLevelNetlist.Instance] = []
        for i in 0..<4 {
            let inNet = i == 0 ? "qa" : "c\(i)"
            let outNet = i == 3 ? "db" : "c\(i + 1)"
            insts.append(.init(name: "g\(i)", cell: .inverter(name: "inv"), netMap: ["A": inNet, "Y": outNet]))
        }
        let seq = SequentialNetlist(name: "chain", combinational: insts,
                                    dffs: [.init(name: "ffA", d: "x", clk: "clk", q: "qa"),
                                           .init(name: "ffB", d: "db", clk: "clk", q: "qb")],
                                    inputs: ["x"], outputs: ["qb"], clock: "clk")
        let report = try StaticTimingAnalyzer(library: lib).analyze(seq, clockPeriod: 5e-9, defaultInputSlew: 40e-12)
        #expect(report.criticalPath.stages.count == 4)

        let result = try await TimingCharacterizationTestSupport.withExclusiveSpiceSlot {
            try await STAvsSPICEValidator().validate(path: report.criticalPath, in: seq, toleranceFraction: 0.15)
        }
        #expect(result.staDelay > 0 && result.spiceDelay > 0)
        #expect(result.agrees, "STA \(result.staDelay) vs SPICE \(result.spiceDelay), relErr \(result.relativeError)")
    }

    @Test("STA matches SPICE on the ACC-4 carry-chain critical path", .timeLimit(.minutes(7)))
    func acc4CriticalPathValidates() async throws {
        var lib = TimingLibrary()
        lib.add(try await TimingCharacterizationTestCache.shared.characterizeCell(
            .inverter(name: "inv"),
            inputSlews: [20e-12, 80e-12, 320e-12],
            outputLoads: [0.5e-15, 2e-15, 8e-15]
        ))
        lib.add(try await TimingCharacterizationTestCache.shared.characterizeCell(
            .nand(name: "nand2", inputs: ["A", "B"]),
            inputSlews: [20e-12, 80e-12, 320e-12],
            outputLoads: [0.5e-15, 2e-15, 8e-15]
        ))
        lib.add(try await TimingCharacterizationTestCache.shared.characterizeCell(
            .nor(name: "nor2", inputs: ["A", "B"]),
            inputSlews: [20e-12, 80e-12, 320e-12],
            outputLoads: [0.5e-15, 2e-15, 8e-15]
        ))
        lib.flipFlop = flipFlop(dataCap: lib.cells["nand2"]?.inputCapacitance["A"] ?? 1e-15)

        let seq = ACC4CPUGenerator().sequentialNetlist()
        let report = try StaticTimingAnalyzer(library: lib).analyze(seq, clockPeriod: 10e-9, defaultInputSlew: 50e-12)

        let result = try await TimingCharacterizationTestSupport.withExclusiveSpiceSlot {
            try await STAvsSPICEValidator().validate(path: report.criticalPath, in: seq, toleranceFraction: 0.20)
        }
        #expect(result.staDelay > 0 && result.spiceDelay > 0)
        #expect(result.agrees,
                "ACC-4 path STA \(result.staDelay) vs SPICE \(result.spiceDelay), relErr \(result.relativeError) over \(report.criticalPath.stages.count) stages")
    }
}
