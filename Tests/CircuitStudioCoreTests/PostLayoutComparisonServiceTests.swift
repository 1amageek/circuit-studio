import Foundation
import Testing
import CoreSpiceWaveform
@testable import CircuitStudioCore

@Suite("PostLayoutComparisonService Tests")
struct PostLayoutComparisonServiceTests {
    @Test func compareInterpolatesMismatchedSweepValues() throws {
        let preLayout = SimulationResult(
            experimentID: UUID(),
            status: .completed,
            waveform: makeWaveform(sweepValues: [0, 1, 2], values: [1.0, 2.0, 3.0])
        )
        let postLayout = SimulationResult(
            experimentID: UUID(),
            status: .completed,
            waveform: makeWaveform(sweepValues: [0, 1.5, 2], values: [1.0, 2.5, 3.0])
        )

        let report = PostLayoutComparisonService().compare(
            preLayoutResult: preLayout,
            postLayoutResult: postLayout
        )
        let variable = try #require(report.comparedVariables.first)

        #expect(report.status == "compared")
        #expect(report.comparedPointCount == 3)
        #expect(report.maxAbsoluteDelta == 0)
        #expect(report.maxRelativeDelta == 0)
        #expect(variable.variableName == "V(out)")
        #expect(report.diagnostics.contains {
            $0.contains("linearly interpolated")
        })
        let gatedReport = report.applyingLimits(PostLayoutComparisonLimits(maxAbsoluteDelta: 0.0))
        #expect(gatedReport.gateStatus == "passed")
        #expect(gatedReport.gateViolations.isEmpty)
    }

    @Test func compareRejectsNonOverlappingSweepValues() {
        let preLayout = SimulationResult(
            experimentID: UUID(),
            status: .completed,
            waveform: makeWaveform(sweepValues: [0, 1, 2], values: [1.0, 2.0, 3.0])
        )
        let postLayout = SimulationResult(
            experimentID: UUID(),
            status: .completed,
            waveform: makeWaveform(sweepValues: [10, 11, 12], values: [1.0, 2.0, 3.0])
        )

        let report = PostLayoutComparisonService().compare(
            preLayoutResult: preLayout,
            postLayoutResult: postLayout
        )

        #expect(report.status == "not-comparable")
        #expect(report.comparedPointCount == 0)
        #expect(report.maxAbsoluteDelta == 0)
        #expect(report.maxRelativeDelta == 0)
        #expect(report.comparedVariables.isEmpty)
        #expect(report.diagnostics.contains { $0.contains("No overlapping sweep values") })
        let gatedReport = report.applyingLimits(PostLayoutComparisonLimits(maxAbsoluteDelta: 1.0))
        #expect(gatedReport.gateStatus == "failed")
        #expect(gatedReport.gateViolations.contains {
            $0.contains("not comparable")
        })
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
        #expect(report.maxAbsoluteDelta == 0.5)
        #expect(abs(report.maxRelativeDelta - (0.5 / 3.0)) < 1.0e-12)
        #expect(variable.variableName == "V(out)")
        #expect(variable.maxAbsoluteDelta == 0.5)
        #expect(abs(variable.maxRelativeDelta - (0.5 / 3.0)) < 1.0e-12)
        #expect(report.limitViolations(PostLayoutComparisonLimits(maxAbsoluteDelta: 0.6)).isEmpty)
        #expect(report.limitViolations(PostLayoutComparisonLimits(maxAbsoluteDelta: 0.4)).contains {
            $0.contains("absolute delta") && $0.contains("exceeds")
        })
        #expect(report.limitViolations(PostLayoutComparisonLimits(maxRelativeDelta: 0.1)).contains {
            $0.contains("relative delta") && $0.contains("exceeds")
        })
        let limits = PostLayoutComparisonLimits(maxAbsoluteDelta: 0.6, maxRelativeDelta: 0.2)
        let gatedReport = report.applyingLimits(limits)
        #expect(gatedReport.comparisonLimits == limits)
        #expect(gatedReport.gateStatus == "passed")
        #expect(gatedReport.gateViolations.isEmpty)
    }

    @Test func comparisonLimitsRejectInvalidNumericValues() {
        let limits = PostLayoutComparisonLimits(maxAbsoluteDelta: .nan, maxRelativeDelta: -.infinity)

        #expect(!limits.isValid)
        #expect(limits.validationDiagnostics().count == 2)

        let report = PostLayoutComparisonReport(
            status: "compared",
            preLayoutPointCount: 1,
            postLayoutPointCount: 1,
            sweepVariable: "time",
            comparedPointCount: 1,
            maxAbsoluteDelta: 0,
            maxRelativeDelta: 0,
            comparedVariables: [],
            missingInPostLayout: [],
            addedInPostLayout: [],
            diagnostics: []
        )

        #expect(report.limitViolations(limits).count == 2)
        #expect(report.applyingLimits(limits).gateStatus == "failed")
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
