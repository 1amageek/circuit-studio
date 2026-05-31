import Foundation
import Testing
@testable import CircuitStudioApp

/// BC1.4 — failure-driven timing closure. Starting from a clock the design CANNOT meet, the
/// loop upsizes critical-path cells until setup closes — the fail→pass trajectory the goal
/// requires, computed from the measured critical path against a SPICE-characterized library.
@Suite("Timing-driven closure")
struct TimingDrivenClosureLoopTests {

    /// A library with sized variants (x1/x2/x4) of each cell, characterized in CoreSpice.
    private func sizedLibrary() async throws -> TimingLibrary {
        try await TimingCharacterizationTestCache.shared.sizedClosureLibrary()
    }

    @Test("Upsizing a critical-path cell reduces delay (the sizing knob works)", .timeLimit(.minutes(7)))
    func sizingReducesDelay() async throws {
        let lib = try await sizedLibrary()
        let x1 = try #require(lib.cells["inv"]?.arc(fromInput: "A"))
        let x2 = try #require(lib.cells["inv_x2"]?.arc(fromInput: "A"))
        // At a fixed (heavy) load, the stronger driver is faster.
        let d1 = x1.delayFall.lookup(inputSlew: 40e-12, outputLoad: 12e-15)
        let d2 = x2.delayFall.lookup(inputSlew: 40e-12, outputLoad: 12e-15)
        #expect(d2 < d1, "x2 (\(d2)) should be faster than x1 (\(d1)) at heavy load")
        // And the stronger cell presents more input capacitance (the cost).
        #expect((lib.cells["inv_x2"]?.inputCapacitance["A"] ?? 0) > (lib.cells["inv"]?.inputCapacitance["A"] ?? 0))
    }

    @Test("The loop closes the ACC-4 core at a clock it initially fails", .timeLimit(.minutes(7)))
    func closesACC4AtTighterClock() async throws {
        let lib = try await sizedLibrary()
        let seq = ACC4CPUGenerator().sequentialNetlist()
        let base = try StaticTimingAnalyzer(library: lib).analyze(seq, clockPeriod: 10e-9, defaultInputSlew: 50e-12)

        // Target a clock period below what the base design achieves — it must fail first.
        let target = base.minPeriod * 0.9
        let outcome = try TimingDrivenClosureLoop(library: lib, defaultInputSlew: 50e-12)
            .close(seq, targetPeriod: target, maxIterations: 40)

        #expect(outcome.iterations.first?.met == false, "must start failing at the tight clock")
        #expect(outcome.converged, "loop must close timing; slack \(outcome.report.worstSetupSlack)")
        #expect(outcome.report.worstSetupSlack >= 0)
        #expect(outcome.iterations.contains { $0.upsizedInstance != nil }, "closure must resize cells")
        #expect(outcome.report.minPeriod < base.minPeriod, "fmax must improve: \(outcome.report.minPeriod) vs \(base.minPeriod)")
    }
}
