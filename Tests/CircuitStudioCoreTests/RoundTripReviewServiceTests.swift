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
        #expect(result.roundTripReview?.postLayoutComparison?.variableSummaries.first?.signalDomain == .voltage)
        #expect(result.roundTripReview?.postLayoutComparison?.variableSummaries.first?.unit == "V")
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

    @Test(.timeLimit(.minutes(1)))
    func artifactResolverRejectsExternalURLInsteadOfReturningAbsoluteFallback() throws {
        let root = try makeTemporaryRoot("resolver-external-url")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let externalURL = root.appending(path: "external.txt")
        try "external\n".write(to: externalURL, atomically: true, encoding: .utf8)

        var didRejectExternalURL = false
        do {
            _ = try RoundTripArtifactResolver(
                runDirectory: runDirectory,
                allowLegacyAbsolutePaths: false
            ).relativePath(for: externalURL)
            Issue.record("Expected external artifact URL to fail relative path conversion.")
        } catch let error as RoundTripArtifactResolverError {
            if case .pathEscapesRunDirectory = error {
                didRejectExternalURL = true
            } else {
                Issue.record("Expected path escape error, got \(error).")
            }
        }
        #expect(didRejectExternalURL)
    }

    @Test(.timeLimit(.minutes(1)))
    func escapingReviewArtifactIsDiagnosticAndIsNotRead() throws {
        let root = try makeTemporaryRoot("review-escape-artifact")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let outsideComparisonURL = runDirectory
            .deletingLastPathComponent()
            .appending(path: "outside-comparison.json")
        try writeJSON(makeComparisonReport(), to: outsideComparisonURL)

        let signoffURL = runDirectory.appending(path: "external-signoff-review.json")
        try writeJSON(makeApprovedSignoffReview(), to: signoffURL)

        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        var manifest = makeManifest(comparisonURL: runDirectory.appending(path: "unused.json"), signoffURL: signoffURL)
        manifest = HeadlessRoundTripService.Manifest(
            runID: manifest.runID,
            title: manifest.title,
            createdAt: manifest.createdAt,
            isRoundTripComplete: manifest.isRoundTripComplete,
            isReadyForPEX: manifest.isReadyForPEX,
            stages: manifest.stages,
            artifacts: [
                manifest.artifacts[0],
                HeadlessRoundTripService.Artifact(
                    kind: "post-layout-comparison",
                    path: "../outside-comparison.json"
                ),
            ],
            bottleneckSummary: manifest.bottleneckSummary
        )
        try writeJSON(manifest, to: manifestURL)

        let summary = try RoundTripReviewService().loadReview(manifestURL: manifestURL)

        #expect(summary.status == .incomplete)
        #expect(summary.postLayoutComparison == nil)
        #expect(summary.diagnostics.contains { $0.contains("escapes") })
        #expect(summary.warnings.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func symlinkEscapingRunDirectoryIsDiagnosticAndIsNotRead() throws {
        let root = try makeTemporaryRoot("review-symlink-escape")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let externalDirectory = root.appending(path: "external")
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        let externalComparisonURL = externalDirectory.appending(path: "post-layout-comparison.json")
        try writeJSON(makeComparisonReport(), to: externalComparisonURL)

        let linkedComparisonURL = runDirectory.appending(path: "linked-comparison.json")
        try FileManager.default.createSymbolicLink(
            at: linkedComparisonURL,
            withDestinationURL: externalComparisonURL
        )

        let signoffURL = runDirectory.appending(path: "external-signoff-review.json")
        try writeJSON(makeApprovedSignoffReview(), to: signoffURL)

        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeJSON(makeManifest(
            comparisonURL: linkedComparisonURL,
            signoffURL: signoffURL
        ), to: manifestURL)

        let summary = try RoundTripReviewService().loadReview(manifestURL: manifestURL)

        #expect(summary.status == .incomplete)
        #expect(summary.postLayoutComparison == nil)
        #expect(summary.diagnostics.contains { $0.contains("escapes") })
    }

    @Test(.timeLimit(.minutes(1)))
    func legacyAbsoluteArtifactPathIsWarningNotDiagnostic() throws {
        let root = try makeTemporaryRoot("review-legacy-absolute")
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
        var manifest = makeManifest(comparisonURL: comparisonURL, signoffURL: signoffURL)
        manifest = HeadlessRoundTripService.Manifest(
            runID: manifest.runID,
            title: manifest.title,
            createdAt: manifest.createdAt,
            isRoundTripComplete: manifest.isRoundTripComplete,
            isReadyForPEX: manifest.isReadyForPEX,
            stages: manifest.stages,
            artifacts: [
                manifest.artifacts[0],
                HeadlessRoundTripService.Artifact(
                    kind: "post-layout-comparison",
                    path: comparisonURL.path(percentEncoded: false)
                ),
            ],
            bottleneckSummary: manifest.bottleneckSummary
        )
        try writeJSON(manifest, to: manifestURL)

        let summary = try RoundTripReviewService().loadReview(manifestURL: manifestURL)

        #expect(summary.status == .passed)
        #expect(summary.diagnostics.isEmpty)
        #expect(summary.warnings.contains { $0.contains("Legacy absolute artifact path") })
        #expect(summary.postLayoutComparison?.gateStatus == "passed")
    }

    @Test(.timeLimit(.minutes(1)))
    func relativeArtifactManifestRemainsPortableAfterRunDirectoryMove() throws {
        let originalRoot = try makeTemporaryRoot("review-portable-original")
        let movedRoot = try makeTemporaryRoot("review-portable-moved")
        defer { removeTemporaryRoot(originalRoot) }
        defer { removeTemporaryRoot(movedRoot) }

        let originalRunDirectory = originalRoot
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: originalRunDirectory, withIntermediateDirectories: true)

        let comparisonURL = originalRunDirectory.appending(path: "post-layout-comparison.json")
        try writeJSON(makeComparisonReport(), to: comparisonURL)

        let signoffURL = originalRunDirectory.appending(path: "external-signoff-review.json")
        try writeJSON(makeApprovedSignoffReview(), to: signoffURL)

        let manifestURL = originalRunDirectory.appending(path: "round-trip-manifest.json")
        try writeJSON(makeManifest(
            comparisonURL: comparisonURL,
            signoffURL: signoffURL
        ), to: manifestURL)

        let movedRunDirectory = movedRoot
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(
            at: movedRunDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: originalRunDirectory, to: movedRunDirectory)

        let summary = try RoundTripReviewService().loadReview(
            manifestURL: movedRunDirectory.appending(path: "round-trip-manifest.json")
        )

        #expect(summary.status == .passed)
        #expect(summary.diagnostics.isEmpty)
        #expect(summary.warnings.isEmpty)
        #expect(summary.postLayoutComparison?.gateStatus == "passed")
    }

    @Test(.timeLimit(.minutes(1)))
    func manifestBackedApprovalRemainsPortableAfterProjectMove() throws {
        let originalRoot = try makeTemporaryRoot("review-approval-portable-original")
        let movedParent = try makeTemporaryRoot("review-approval-portable-moved")
        defer {
            if FileManager.default.fileExists(atPath: originalRoot.path(percentEncoded: false)) {
                removeTemporaryRoot(originalRoot)
            }
        }
        defer { removeTemporaryRoot(movedParent) }

        let runDirectory = originalRoot
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

        let approval = try FlowRunGovernanceService().approve(GateApprovalRequest(
            gateID: .postLayoutComparison,
            reviewer: "reviewer",
            projectRoot: originalRoot,
            runID: "review-run",
            manifestURL: manifestURL
        ))
        #expect(approval.record.targetArtifactKind == "post-layout-comparison")
        #expect(approval.record.targetArtifactPathBase == .runDirectory)
        #expect(approval.record.targetArtifactPath == "post-layout-comparison.json")

        let movedRoot = movedParent.appending(path: "moved-project")
        try FileManager.default.copyItem(at: originalRoot, to: movedRoot)
        try FileManager.default.removeItem(at: originalRoot)

        let summary = try RoundTripReviewService().loadReview(
            manifestURL: movedRoot
                .appending(path: ".xcircuite")
                .appending(path: "flow-runs")
                .appending(path: "review-run")
                .appending(path: "round-trip-manifest.json")
        )

        #expect(summary.status == .passed)
        #expect(summary.diagnostics.isEmpty)
        #expect(summary.warnings.isEmpty)
        #expect(summary.approvals.count == 1)
        #expect(summary.approvals.first?.targetArtifactPathBase == .runDirectory)
    }

    @Test(.timeLimit(.minutes(1)))
    func legacyAbsoluteApprovalTargetIsAuditedAsNonPortable() throws {
        let root = try makeTemporaryRoot("review-legacy-approval-target")
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

        let approvalsDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "approvals")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: approvalsDirectory, withIntermediateDirectories: true)
        let staleAbsolutePath = FileManager.default.temporaryDirectory
            .appending(path: "missing-approval-target-\(UUID().uuidString).json")
            .path(percentEncoded: false)
        try writeJSON(GateApprovalRecord(
            gateID: .postLayoutComparison,
            decision: .approved,
            reviewer: "reviewer",
            decidedAt: Date(timeIntervalSince1970: 1_700_000_010),
            runID: "review-run",
            manifestPath: manifestURL.path(percentEncoded: false),
            manifestSHA256: nil,
            targetArtifactPath: staleAbsolutePath,
            targetArtifactSHA256: String(repeating: "0", count: 64),
            policy: nil,
            waiverIDs: [],
            note: nil,
            lineage: nil
        ), to: approvalsDirectory.appending(path: "legacy-approval.json"))

        let summary = try RoundTripReviewService().loadReview(manifestURL: manifestURL)

        #expect(summary.status == .incomplete)
        #expect(summary.approvals.count == 1)
        #expect(summary.warnings.contains { $0.contains("legacy absolute target artifact path") })
        #expect(summary.diagnostics.contains { $0.contains("Gate approval target artifact is missing") })
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
                    path: signoffURL.lastPathComponent,
                    sourcePath: "/source/external-signoff-review.json"
                ),
                HeadlessRoundTripService.Artifact(
                    kind: "post-layout-comparison",
                    path: comparisonURL.lastPathComponent
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
                    signalDomain: .voltage,
                    unit: "V",
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
