import Foundation
import Testing
@testable import CircuitStudioApp

/// BC3.4 — power integrity (IR drop + EM) on the extracted ACC-4 grid, plus the ngspice
/// trust anchor for the IR solve.
@Suite("Power grid signoff")
struct PowerGridSignoffTests {

    // A representative sky130 met1 peak current-density limit (~1 mA per µm of width).
    private let emLimitAmperesPerMeter = 1000.0

    @Test("The ACC-4 met1 power grid meets IR-drop budget and EM (tool-independent)")
    func acc4PowerIntegrityPasses() async throws {
        let model = PowerGridExtractor().extract(ACC4CPUGenerator().gateLevelNetlist())
        let ir = try await IRDropAnalyzer().analyze(model, budgetFraction: 0.05)
        #expect(ir.passed, "IR drop \(ir.maxIRDropVolts * 1000) mV vs budget \(ir.budgetVolts * 1000) mV")
        let em = ElectromigrationChecker().check(model, limitAmperesPerMeter: emLimitAmperesPerMeter)
        #expect(em.passed, "EM worst \(em.worstDensity) A/m vs limit \(emLimitAmperesPerMeter) A/m at \(em.worstSegment ?? "?")")
    }

    @Test("A too-resistive (li1) grid is caught by IR drop")
    func resistiveGridCaughtByIR() async throws {
        // Same ACC-4 cells but the power rail is left on resistive li1 (12.8 Ω/sq) — IR explodes.
        let model = PowerGridExtractor(railSheetResistance: 12.8, railWidth: 0.2e-6)
            .extract(ACC4CPUGenerator().gateLevelNetlist())
        let ir = try await IRDropAnalyzer().analyze(model, budgetFraction: 0.05)
        #expect(!ir.passed)
        #expect(ir.maxIRDropFraction > 0.05)
    }

    @Test("A thin overloaded rail is caught by electromigration")
    func thinRailCaughtByEM() {
        let model = PowerGridExtractor(railWidth: 0.15e-6).extract(ACC4CPUGenerator().gateLevelNetlist())
        let em = ElectromigrationChecker().check(model, limitAmperesPerMeter: emLimitAmperesPerMeter)
        #expect(!em.passed, "worst \(em.worstDensity) A/m should exceed \(emLimitAmperesPerMeter)")
        // The hot spot is the feed segment carrying the whole design's current.
        #expect(em.worstSegment?.hasPrefix("feed") == true)
    }

    @Test("The IR-drop solve agrees with the ngspice oracle (trust anchor)",
          .enabled(if: IRDropValidator.ngspiceAvailable()), .timeLimit(.minutes(3)))
    func irDropMatchesNgspice() async throws {
        let model = PowerGridExtractor().extract(ACC4CPUGenerator().gateLevelNetlist())
        let agreement = try await IRDropValidator().validate(model, toleranceV: 5e-3)
        #expect(agreement.consistent, "max CoreSpice-vs-ngspice divergence \(agreement.maxDivergenceV * 1000) mV")
    }
}
