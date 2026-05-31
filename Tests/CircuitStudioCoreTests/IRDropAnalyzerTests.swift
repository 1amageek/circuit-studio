import Foundation
import Testing
@testable import CircuitStudioApp

/// BC3.4 — static IR drop. Tool-independent (CoreSpice DC, in-process): a hand-computable
/// single-tap grid matches 2·I·R, far cells along a rail see more drop than near cells, and a
/// too-resistive grid is CAUGHT against the budget.
@Suite("IR drop analysis")
struct IRDropAnalyzerTests {

    private func grid(railLengthMicrons L: Double, current: Double, taps n: Int,
                      width: Double = 0.48e-6) -> PowerGridModel {
        let positions = (1...n).map { Double($0) / Double(n) * (L * 1e-6) }
        return PowerGridModel(supplyVoltage: 1.8, railSheetResistance: 12.8, railWidth: width,
                              feedPosition: 0, taps: positions.enumerated().map {
                                  .init(label: "c\($0.offset)", position: $0.element, current: current) })
    }

    @Test("A single-tap grid matches the hand value 2·I·R")
    func singleTapMatchesHand() async throws {
        // R = 12.8 · (100µm / 0.48µm) = 2667 Ω ; IR drop = 2·I·R = 2·10µA·2667 ≈ 53.3 mV.
        let model = grid(railLengthMicrons: 100, current: 10e-6, taps: 1)
        let result = try await IRDropAnalyzer().analyze(model)
        let expected = 2 * 10e-6 * (12.8 * (100e-6 / 0.48e-6))
        #expect(abs(result.maxIRDropVolts - expected) / expected < 0.02, "got \(result.maxIRDropVolts), want \(expected)")
        #expect(result.passed)   // 53 mV < 90 mV budget
    }

    @Test("A far cell along the rail sees more IR drop than a near cell")
    func farCellWorse() async throws {
        let model = grid(railLengthMicrons: 100, current: 5e-6, taps: 6)
        let result = try await IRDropAnalyzer().analyze(model)
        let near = try #require(result.effectiveSupplyByTap["c0"])
        let far = try #require(result.effectiveSupplyByTap["c5"])
        #expect(far < near, "far cell \(far) should be more starved than near \(near)")
        #expect(result.worstTapLabel == "c5")
    }

    @Test("A too-resistive grid exceeds the IR-drop budget (caught)")
    func resistiveGridCaught() async throws {
        // A long, thin rail with heavy current: IR drop blows the 5% budget.
        let model = grid(railLengthMicrons: 400, current: 40e-6, taps: 10, width: 0.20e-6)
        let result = try await IRDropAnalyzer().analyze(model, budgetFraction: 0.05)
        #expect(!result.passed, "drop \(result.maxIRDropVolts * 1000) mV vs budget \(result.budgetVolts * 1000) mV")
        #expect(result.maxIRDropFraction > 0.05)
    }
}
