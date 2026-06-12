import Foundation
import Testing

@testable import CircuitStudioCore

@Suite("Simulation Service Detect Analyses Tests")
struct SimulationServiceDetectAnalysesTests {

    @Test("Every declared analysis is detected in declaration order")
    func everyDeclaredAnalysisIsDetectedInDeclarationOrder() async throws {
        let source = """
            * multi-analysis testbench
            V1 in 0 DC 1 AC 1
            R1 in out 1k
            C1 out 0 1u
            .op
            .tran 10u 1m
            .ac dec 10 1 1meg
            .dc V1 0 1.8 0.1
            .end
            """

        let analyses = try await SimulationService().detectAnalyses(
            source: source,
            fileName: "multi.cir"
        )

        try #require(analyses.count == 4)

        guard case .op = analyses[0] else {
            Issue.record("Expected .op first, got \(analyses[0])")
            return
        }
        guard case .tran(let tranSpec) = analyses[1] else {
            Issue.record("Expected .tran second, got \(analyses[1])")
            return
        }
        #expect(abs(tranSpec.stopTime - 1e-3) < 1e-12)
        let stepTime = try #require(tranSpec.stepTime)
        #expect(abs(stepTime - 1e-5) < 1e-12)

        guard case .ac(let acSpec) = analyses[2] else {
            Issue.record("Expected .ac third, got \(analyses[2])")
            return
        }
        #expect(acSpec.scaleType == .decade)
        #expect(acSpec.numberOfPoints == 10)
        #expect(abs(acSpec.startFrequency - 1.0) < 1e-12)
        #expect(abs(acSpec.stopFrequency - 1e6) < 1e-6)

        guard case .dcSweep(let dcSpec) = analyses[3] else {
            Issue.record("Expected .dcSweep fourth, got \(analyses[3])")
            return
        }
        // SPICE identifiers are case-insensitive; the parser normalizes case.
        #expect(dcSpec.source.caseInsensitiveCompare("V1") == .orderedSame)
        #expect(abs(dcSpec.startValue - 0.0) < 1e-12)
        #expect(abs(dcSpec.stopValue - 1.8) < 1e-12)
        #expect(abs(dcSpec.stepValue - 0.1) < 1e-12)
    }

    @Test("A netlist without analysis cards yields an empty list")
    func netlistWithoutAnalysisCardsYieldsEmptyList() async throws {
        let source = """
            * passive divider, no analyses
            V1 in 0 DC 1
            R1 in out 1k
            R2 out 0 1k
            .end
            """

        let analyses = try await SimulationService().detectAnalyses(
            source: source,
            fileName: "plain.cir"
        )

        #expect(analyses.isEmpty)
    }
}
