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
        let limits = PostLayoutComparisonLimits(
            maxAbsoluteDelta: .nan,
            maxRelativeDelta: -.infinity,
            variableLimits: [
                PostLayoutVariableComparisonLimit(variableName: "", maxAbsoluteDelta: 1),
                PostLayoutVariableComparisonLimit(variableName: "V(out)"),
                PostLayoutVariableComparisonLimit(variableName: "V(out)", maxRelativeDelta: .infinity),
            ]
        )

        #expect(!limits.isValid)
        #expect(limits.validationDiagnostics().count == 6)

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

        #expect(report.limitViolations(limits).count == 6)
        #expect(report.applyingLimits(limits).gateStatus == "failed")
    }

    @Test func variableSpecificLimitsGateTargetedVariables() throws {
        let preLayout = SimulationResult(
            experimentID: UUID(),
            status: .completed,
            waveform: makeWaveform(
                sweepValues: [0, 1, 2],
                variables: ["out", "in"],
                values: [
                    [1.0, 5.0],
                    [2.0, 5.0],
                    [3.0, 5.0],
                ]
            )
        )
        let postLayout = SimulationResult(
            experimentID: UUID(),
            status: .completed,
            waveform: makeWaveform(
                sweepValues: [0, 1, 2],
                variables: ["out", "in"],
                values: [
                    [1.0, 5.0],
                    [2.25, 5.0],
                    [3.5, 5.0],
                ]
            )
        )

        let report = PostLayoutComparisonService().compare(
            preLayoutResult: preLayout,
            postLayoutResult: postLayout
        )
        let limits = PostLayoutComparisonLimits(
            variableLimits: [
                PostLayoutVariableComparisonLimit(variableName: "V(out)", maxAbsoluteDelta: 0.4),
                PostLayoutVariableComparisonLimit(variableName: "V(in)", maxAbsoluteDelta: 0),
            ]
        )
        let gatedReport = report.applyingLimits(limits)

        #expect(report.comparedVariables.map(\.variableName) == ["V(out)", "V(in)"])
        #expect(gatedReport.gateStatus == "failed")
        #expect(gatedReport.comparisonLimits == limits)
        #expect(gatedReport.gateViolations.count == 1)
        #expect(gatedReport.gateViolations[0].contains("V(out)"))
        #expect(gatedReport.gateViolations[0].contains("absolute delta"))
    }

    @Test func variableSpecificLimitFailsWhenVariableIsMissing() {
        let report = PostLayoutComparisonReport(
            status: "compared",
            preLayoutPointCount: 1,
            postLayoutPointCount: 1,
            sweepVariable: "time",
            comparedPointCount: 1,
            maxAbsoluteDelta: 0,
            maxRelativeDelta: 0,
            comparedVariables: [
                PostLayoutVariableComparison(
                    variableName: "V(out)",
                    maxAbsoluteDelta: 0,
                    maxRelativeDelta: 0,
                    firstPreLayoutValue: 0,
                    firstPostLayoutValue: 0,
                    lastPreLayoutValue: 0,
                    lastPostLayoutValue: 0
                ),
            ],
            missingInPostLayout: [],
            addedInPostLayout: [],
            diagnostics: []
        )
        let limits = PostLayoutComparisonLimits(
            variableLimits: [
                PostLayoutVariableComparisonLimit(variableName: "V(in)", maxAbsoluteDelta: 0),
            ]
        )

        #expect(report.limitViolations(limits).contains {
            $0.contains("V(in)") && $0.contains("not compared")
        })
    }

    @Test func aggregateMultiCornerReportPreservesWorstCornerAndGateStatus() {
        let passing = PostLayoutComparisonReport(
            status: "compared",
            preLayoutPointCount: 1,
            postLayoutPointCount: 1,
            sweepVariable: "time",
            comparedPointCount: 1,
            maxAbsoluteDelta: 0.1,
            maxRelativeDelta: 0.01,
            comparedVariables: [],
            missingInPostLayout: [],
            addedInPostLayout: [],
            diagnostics: [],
            comparisonLimits: PostLayoutComparisonLimits(maxAbsoluteDelta: 1),
            gateStatus: "passed"
        )
        let failing = PostLayoutComparisonReport(
            status: "compared",
            preLayoutPointCount: 1,
            postLayoutPointCount: 1,
            sweepVariable: "time",
            comparedPointCount: 1,
            maxAbsoluteDelta: 2.0,
            maxRelativeDelta: 0.5,
            comparedVariables: [],
            missingInPostLayout: [],
            addedInPostLayout: [],
            diagnostics: [],
            comparisonLimits: PostLayoutComparisonLimits(maxAbsoluteDelta: 1),
            gateStatus: "failed",
            gateViolations: ["Post-layout maximum absolute delta 2.0 exceeds limit 1.0."]
        )

        let report = PostLayoutComparisonService().aggregate(cornerReports: [
            PostLayoutCornerComparisonReport(cornerID: "tt", report: passing),
            PostLayoutCornerComparisonReport(cornerID: "ss", report: failing),
        ])

        #expect(report.status == "compared")
        #expect(report.gateStatus == "failed")
        #expect(report.maxAbsoluteDelta == 2.0)
        #expect(report.maxRelativeDelta == 0.5)
        #expect(report.worstAbsoluteCornerID == "ss")
        #expect(report.worstRelativeCornerID == "ss")
        #expect(report.gateViolations == ["[ss] Post-layout maximum absolute delta 2.0 exceeds limit 1.0."])
    }

    private func makeWaveform(sweepValues: [Double], values: [Double]) -> WaveformData {
        makeWaveform(
            sweepValues: sweepValues,
            variables: ["out"],
            values: values.map { [$0] }
        )
    }

    private func makeWaveform(
        sweepValues: [Double],
        variables: [String],
        values: [[Double]]
    ) -> WaveformData {
        WaveformData(
            metadata: SimulationMetadata(
                analysisType: .transient,
                pointCount: sweepValues.count,
                variableCount: variables.count
            ),
            sweepVariable: .time(),
            sweepValues: sweepValues,
            variables: variables.enumerated().map { index, variable in
                .voltage(node: variable, index: index)
            },
            realData: values
        )
    }
}
