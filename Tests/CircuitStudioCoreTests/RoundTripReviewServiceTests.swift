import Foundation
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore

@Suite("RoundTripReviewService Tests")
struct RoundTripReviewServiceTests {

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func reviewCommandLoadsManifestBackedArtifacts() async throws {
        let root = try makeTemporaryRoot("review-command")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try writeJSON(makeComparisonReport(), to: comparisonURL)

        let signoffURL = runDirectory.appending(path: "external-signoff-review.json")
        try writeJSON(makeApprovedSignoffReview(), to: signoffURL)

        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeJSON(makeManifest(
            comparisonURL: comparisonURL,
            signoffURL: signoffURL
        ), to: manifestURL)

        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .reviewRoundTrip,
            roundTripManifestPath: manifestURL.path(percentEncoded: false)
        ))

        #expect(result.roundTripReview?.status == .passed)
        #expect(result.roundTripReview?.runID == "review-run")
        #expect(result.roundTripReview?.postLayoutComparison?.gateStatus == "passed")
        #expect(result.roundTripReview?.postLayoutComparison?.oscillationMetrics.first?.variableName == "V(out)")
        #expect(result.roundTripReview?.postLayoutComparison?.oscillationMetrics.first?.preLayoutTransitionCount == 4)
        #expect(result.roundTripReview?.postLayoutComparison?.oscillationMetrics.first?.postLayoutFrequency == 0.9e9)
        #expect(result.roundTripReview?.externalSignoff?.readyForPEX == true)
        #expect(result.roundTripReview?.externalSignoff?.approvedBy == "reviewer")
        #expect(result.roundTripReview?.diagnostics.isEmpty == true)
        #expect(result.roundTripReview?.artifacts.contains { $0.kind == "external-signoff-review" && $0.exists } == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func missingReviewArtifactIsDiagnosticNotLoadFailure() throws {
        let root = try makeTemporaryRoot("review-missing-artifact")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let missingComparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        let signoffURL = runDirectory.appending(path: "external-signoff-review.json")
        try writeJSON(makeApprovedSignoffReview(), to: signoffURL)

        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeJSON(makeManifest(
            comparisonURL: missingComparisonURL,
            signoffURL: signoffURL
        ), to: manifestURL)

        let summary = try RoundTripReviewService().loadReview(manifestURL: manifestURL)

        #expect(summary.status == .incomplete)
        #expect(summary.postLayoutComparison == nil)
        #expect(summary.diagnostics.contains { $0.contains("post-layout-comparison") })
        #expect(summary.artifacts.contains { $0.kind == "post-layout-comparison" && !$0.exists })
        #expect(summary.recommendations.contains { $0.contains("auditable") })
    }

    private func makeManifest(
        comparisonURL: URL,
        signoffURL: URL
    ) -> HeadlessRoundTripService.Manifest {
        HeadlessRoundTripService.Manifest(
            runID: "review-run",
            title: "Review run",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            isRoundTripComplete: true,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "external-signoff", status: .passed),
                HeadlessRoundTripService.Stage(name: "post-layout-comparison", status: .passed, message: "passed"),
            ],
            artifacts: [
                HeadlessRoundTripService.Artifact(
                    kind: "external-signoff-review",
                    path: signoffURL.path(percentEncoded: false),
                    sourcePath: "/source/external-signoff-review.json"
                ),
                HeadlessRoundTripService.Artifact(
                    kind: "post-layout-comparison",
                    path: comparisonURL.path(percentEncoded: false)
                ),
            ],
            bottleneckSummary: HeadlessRoundTripService.BottleneckSummary(
                totalMeasuredDurationSeconds: 1.0,
                longestStageName: "post-layout-comparison",
                longestStageDurationSeconds: 1.0,
                failedStageName: nil,
                recommendations: []
            )
        )
    }

    private func makeComparisonReport() -> PostLayoutComparisonReport {
        PostLayoutComparisonReport(
            status: "compared",
            preLayoutPointCount: 1,
            postLayoutPointCount: 1,
            sweepVariable: nil,
            comparedPointCount: 1,
            maxAbsoluteDelta: 0.001,
            maxRelativeDelta: 0.01,
            comparedVariables: [
                PostLayoutVariableComparison(
                    variableName: "v(out)",
                    maxAbsoluteDelta: 0.001,
                    maxRelativeDelta: 0.01,
                    firstPreLayoutValue: 1.0,
                    firstPostLayoutValue: 0.999,
                    lastPreLayoutValue: 1.0,
                    lastPostLayoutValue: 0.999
                ),
            ],
            oscillationMetrics: [
                PostLayoutOscillationMetricComparison(
                    variableName: "V(out)",
                    threshold: 0.5,
                    preLayout: PostLayoutOscillationMetrics(
                        transitionCount: 4,
                        risingEdgeCount: 2,
                        fallingEdgeCount: 2,
                        minValue: 0,
                        maxValue: 1,
                        amplitude: 1,
                        averagePeriod: 1.0e-9,
                        frequency: 1.0e9,
                        dutyCycle: 0.5,
                        firstRisingEdgeTime: 0,
                        lastRisingEdgeTime: 1.0e-9
                    ),
                    postLayout: PostLayoutOscillationMetrics(
                        transitionCount: 4,
                        risingEdgeCount: 2,
                        fallingEdgeCount: 2,
                        minValue: 0,
                        maxValue: 0.95,
                        amplitude: 0.95,
                        averagePeriod: 1.1111111111111112e-9,
                        frequency: 0.9e9,
                        dutyCycle: 0.48,
                        firstRisingEdgeTime: 0,
                        lastRisingEdgeTime: 1.1111111111111112e-9
                    ),
                    frequencyRelativeDelta: 0.1,
                    periodRelativeDelta: 0.1,
                    dutyCycleDelta: 0.02,
                    diagnostics: []
                ),
            ],
            missingInPostLayout: [],
            addedInPostLayout: [],
            diagnostics: [],
            comparisonLimits: PostLayoutComparisonLimits(maxAbsoluteDelta: 0.01),
            gateStatus: "passed",
            gateViolations: []
        )
    }

    private func makeApprovedSignoffReview() -> ExternalSignoffReview {
        ExternalSignoffReview(
            reports: [
                ExternalSignoffToolReport(
                    kind: .drc,
                    toolName: "replay-drc",
                    success: true,
                    logPath: "/source/drc.log"
                ),
                ExternalSignoffToolReport(
                    kind: .lvs,
                    toolName: "replay-lvs",
                    success: true,
                    logPath: "/source/lvs.log"
                ),
            ],
            approvedBy: "reviewer",
            approvedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "circuit-studio-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}
