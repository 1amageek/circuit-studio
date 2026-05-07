import Foundation
import Testing
import CoreSpiceWaveform
@testable import CircuitStudioCore

@Suite("PostLayoutComparisonService Tests")
struct PostLayoutComparisonServiceTests {
    @Test func compareRejectsMismatchedSweepValues() {
        let preLayout = SimulationResult(
            experimentID: UUID(),
            status: .completed,
            waveform: makeWaveform(sweepValues: [0, 1, 2], values: [1.0, 2.0, 3.0])
        )
        let postLayout = SimulationResult(
            experimentID: UUID(),
            status: .completed,
            waveform: makeWaveform(sweepValues: [0, 1.5, 2], values: [1.0, 2.0, 3.0])
        )

        let report = PostLayoutComparisonService().compare(
            preLayoutResult: preLayout,
            postLayoutResult: postLayout
        )

        #expect(report.status == "not-comparable")
        #expect(report.comparedPointCount == 0)
        #expect(report.comparedVariables.isEmpty)
        #expect(report.diagnostics.contains { $0.contains("Sweep values differ beyond tolerance") })
    }

    @Test func compareReportsCommonVariableDeltasWhenSweepsMatch() throws {
        let preLayout = SimulationResult(
            experimentID: UUID(),
            status: .completed,
            waveform: makeWaveform(sweepValues: [0, 1, 2], values: [1.0, 2.0, 3.0])
        )
        let postLayout = SimulationResult(
            experimentID: UUID(),
            status: .completed,
            waveform: makeWaveform(sweepValues: [0, 1, 2], values: [1.0, 2.25, 2.5])
        )

        let report = PostLayoutComparisonService().compare(
            preLayoutResult: preLayout,
            postLayoutResult: postLayout
        )
        let variable = try #require(report.comparedVariables.first)

        #expect(report.status == "compared")
        #expect(report.comparedPointCount == 3)
        #expect(variable.variableName == "V(out)")
        #expect(variable.maxAbsoluteDelta == 0.5)
        #expect(abs(variable.maxRelativeDelta - (0.5 / 3.0)) < 1.0e-12)
    }

    private func makeWaveform(sweepValues: [Double], values: [Double]) -> WaveformData {
        WaveformData(
            metadata: SimulationMetadata(
                analysisType: .transient,
                pointCount: sweepValues.count,
                variableCount: 1
            ),
            sweepVariable: .time(),
            sweepValues: sweepValues,
            variables: [.voltage(node: "out", index: 0)],
            realData: values.map { [$0] }
        )
    }
}
