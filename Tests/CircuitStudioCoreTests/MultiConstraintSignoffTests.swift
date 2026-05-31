import Foundation
import Testing
@testable import CircuitStudioApp

/// BC1.4 — the unified verdict. Functional (golden-trace) and timing (STA) signoff fold into
/// ONE result that passes only when every axis passes; a single failing axis fails the whole
/// and a missing required axis throws, so a constraint can never be silently dropped.
@Suite("Multi-constraint signoff")
struct MultiConstraintSignoffTests {

    private func constantLibrary() -> TimingLibrary {
        func arc(_ d: Double) -> TimingArc {
            TimingArc(inputPin: "A", sense: .negativeUnate, delayRise: .constant(d), delayFall: .constant(d),
                      transitionRise: .constant(1e-11), transitionFall: .constant(1e-11))
        }
        let inv = CellTiming(cellName: "inv", inputCapacitance: ["A": 1e-15], arcs: [arc(50e-12)])
        let ff = SequentialTiming(clkToQRise: .constant(100e-12), clkToQFall: .constant(100e-12),
                                  qTransitionRise: .constant(1e-11), qTransitionFall: .constant(1e-11),
                                  setupTime: 20e-12, holdTime: 5e-12, dataCapacitance: 1e-15, clockCapacitance: 1e-15)
        return TimingLibrary(cells: ["inv": inv], flipFlop: ff)
    }

    private func report(clockPeriod: Double) throws -> TimingReport {
        // A self-contained toggle (q -> inv -> d, same flip-flop): no primary-input capture,
        // so the only constraint is the real FF→FF path.
        let seq = SequentialNetlist(
            name: "c",
            combinational: [.init(name: "g0", cell: .inverter(name: "inv"), netMap: ["A": "q", "Y": "d"])],
            dffs: [.init(name: "ff", d: "d", clk: "clk", q: "q")],
            inputs: [], outputs: ["q"], clock: "clk")
        return try StaticTimingAnalyzer(library: constantLibrary()).analyze(seq, clockPeriod: clockPeriod, defaultInputSlew: 1e-11)
    }

    @Test("Functional + timing fold into a single passing verdict")
    func combinesPassingAxes() throws {
        // Functional: the gate CPU matches the reference on a small program.
        let program = try ACC4Assembler().assemble("LDI 5\nADD 0\nSUB 0\nJMP 0")
        let golden = ACC4Reference().run(program, cycles: 16).trace
        let actual = try ACC4Machine().run(program, cycles: 16)
        let fn = MultiConstraintSignoff.functional(passed: actual == golden, cycles: 16, evidence: "ACC4Machine==ACC4Reference")

        let timing = MultiConstraintSignoff.timing(try report(clockPeriod: 5e-9), evidence: "STA@5ns")
        let verdict = try MultiConstraintSignoff().combine([fn, timing])

        #expect(verdict.passed)
        #expect(verdict.failing.isEmpty)
        #expect(verdict.axis(.functional)?.passed == true)
        #expect(verdict.axis(.timing)?.passed == true)
    }

    @Test("A timing violation fails the whole signoff even when function is correct")
    func timingViolationFailsAll() throws {
        let fn = MultiConstraintSignoff.functional(passed: true, cycles: 16, evidence: "ok")
        let timing = MultiConstraintSignoff.timing(try report(clockPeriod: 150e-12), evidence: "STA@150ps")  // < min period
        let verdict = try MultiConstraintSignoff().combine([fn, timing])

        #expect(!verdict.passed)
        #expect(verdict.failing.map(\.axis) == [.timing])
    }

    @Test("A missing required axis throws (a constraint cannot be silently dropped)")
    func missingAxisThrows() {
        let fn = MultiConstraintSignoff.functional(passed: true, cycles: 16, evidence: "ok")
        #expect(throws: MultiConstraintSignoff.SignoffError.missingRequiredAxis(.timing)) {
            _ = try MultiConstraintSignoff().combine([fn])
        }
    }
}
