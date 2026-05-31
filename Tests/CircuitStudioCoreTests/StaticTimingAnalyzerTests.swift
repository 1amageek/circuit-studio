import Foundation
import Testing
@testable import CircuitStudioApp

/// BC1.1 — tool-independent static timing analysis. A synthetic constant-delay library
/// makes path delays exactly hand-computable, so these check the STA graph/propagation
/// math itself (arrival, setup/hold slack, fmax, critical path) before SPICE
/// characterization makes the numbers physical.
@Suite("Static timing analysis")
struct StaticTimingAnalyzerTests {

    /// A library with constant (load/slew-independent) delays, so a path's delay is just
    /// the sum of its arc delays plus clk→Q — exactly predictable.
    private func constantLibrary(
        inv: Double, nand2: Double, nor2: Double,
        clkToQ: Double, setup: Double, hold: Double,
        cap: Double = 1e-15, slew: Double = 1e-11
    ) -> TimingLibrary {
        func arc(_ pin: String, _ d: Double) -> TimingArc {
            TimingArc(inputPin: pin, sense: .negativeUnate,
                      delayRise: .constant(d), delayFall: .constant(d),
                      transitionRise: .constant(slew), transitionFall: .constant(slew))
        }
        let invCell = CellTiming(cellName: "inv", inputCapacitance: ["A": cap], arcs: [arc("A", inv)])
        let nandCell = CellTiming(cellName: "nand2", inputCapacitance: ["A": cap, "B": cap],
                                  arcs: [arc("A", nand2), arc("B", nand2)])
        let norCell = CellTiming(cellName: "nor2", inputCapacitance: ["A": cap, "B": cap],
                                 arcs: [arc("A", nor2), arc("B", nor2)])
        let ff = SequentialTiming(clkToQRise: .constant(clkToQ), clkToQFall: .constant(clkToQ),
                                  qTransitionRise: .constant(slew), qTransitionFall: .constant(slew),
                                  setupTime: setup, holdTime: hold, dataCapacitance: cap, clockCapacitance: cap)
        return TimingLibrary(cells: ["inv": invCell, "nand2": nandCell, "nor2": norCell], flipFlop: ff)
    }

    @Test("A two-inverter FF→FF path gives exactly clk→Q + 2·t_inv, with the right slack")
    func twoInverterPath() throws {
        // ffA.q -> inv -> inv -> ffB.d
        let seq = SequentialNetlist(
            name: "chain",
            combinational: [
                .init(name: "g0", cell: .inverter(name: "inv"), netMap: ["A": "qa", "Y": "m"]),
                .init(name: "g1", cell: .inverter(name: "inv"), netMap: ["A": "m", "Y": "db"]),
            ],
            dffs: [.init(name: "ffA", d: "x", clk: "clk", q: "qa"),
                   .init(name: "ffB", d: "db", clk: "clk", q: "qb")],
            inputs: ["x"], outputs: ["qb"], clock: "clk")
        let lib = constantLibrary(inv: 50e-12, nand2: 80e-12, nor2: 90e-12, clkToQ: 100e-12, setup: 20e-12, hold: 5e-12)
        let sta = StaticTimingAnalyzer(library: lib)

        let report = try sta.analyze(seq, clockPeriod: 300e-12, defaultInputSlew: 1e-11)
        let dbe = try #require(report.endpoints.first { $0.endpoint == "db" })
        #expect(abs(dbe.dataArrival - 200e-12) < 1e-15)          // 100 (clk2q) + 2*50
        #expect(abs(report.minPeriod - 220e-12) < 1e-15)         // arrival + setup
        #expect(abs(report.worstSetupSlack - 80e-12) < 1e-15)    // (300-20) - 200
        #expect(report.setupMet)
        #expect(report.criticalPath.stages.count == 2)
        #expect(report.criticalPath.startpoint == "qa")

        // Tightening the clock below the min period makes it fail (the loop's starting point).
        let tight = try sta.analyze(seq, clockPeriod: 200e-12, defaultInputSlew: 1e-11)
        #expect(!tight.setupMet)
        #expect(abs(tight.worstSetupSlack - (-20e-12)) < 1e-15)  // (200-20) - 200
    }

    @Test("STA on the ACC-4 core finds the carry-chain critical path and a finite fmax")
    func acc4CriticalPath() throws {
        let seq = ACC4CPUGenerator().sequentialNetlist()
        let lib = constantLibrary(inv: 30e-12, nand2: 60e-12, nor2: 70e-12, clkToQ: 120e-12, setup: 25e-12, hold: 5e-12)
        let report = try StaticTimingAnalyzer(library: lib).analyze(seq, clockPeriod: 5e-9, defaultInputSlew: 1e-11)

        // The accumulator's next-state path (ALU ripple carry -> acc register) is the longest:
        // the critical endpoint must be an accumulator data input.
        #expect(report.criticalPath.endpoint.hasPrefix("acc_d"))
        // It launches from a register Q (a fed-back accumulator/PC bit) or a primary input.
        #expect(!report.criticalPath.stages.isEmpty)
        #expect(report.fmaxHz.isFinite && report.fmaxHz > 0)
        // A generous clock passes; a clock below the min period fails — both via the SAME engine.
        #expect(report.setupMet)
        let tight = try StaticTimingAnalyzer(library: lib).analyze(seq, clockPeriod: report.minPeriod * 0.5, defaultInputSlew: 1e-11)
        #expect(!tight.setupMet)
        #expect(tight.worstSetupSlack < 0)
    }

    @Test("A purely combinational loop with no flip-flop is rejected (never silently)")
    func combinationalLoopRejected() throws {
        let seq = SequentialNetlist(
            name: "loop",
            combinational: [
                .init(name: "g0", cell: .nand(name: "nand2", inputs: ["A", "B"]), netMap: ["A": "a", "B": "y", "Y": "n"]),
                .init(name: "g1", cell: .inverter(name: "inv"), netMap: ["A": "n", "Y": "y"]),
            ],
            dffs: [.init(name: "ff", d: "a", clk: "clk", q: "qa")],
            inputs: [], outputs: ["y"], clock: "clk")
        let lib = constantLibrary(inv: 30e-12, nand2: 60e-12, nor2: 70e-12, clkToQ: 100e-12, setup: 20e-12, hold: 5e-12)
        #expect(throws: StaticTimingAnalyzer.STAError.combinationalCycle) {
            _ = try StaticTimingAnalyzer(library: lib).analyze(seq, clockPeriod: 1e-9, defaultInputSlew: 1e-11)
        }
    }
}
