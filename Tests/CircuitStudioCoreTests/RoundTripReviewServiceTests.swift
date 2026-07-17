import CircuitSignoff
import CircuiteFoundation
import Foundation
import DesignFlowKernel
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
            .appending(path: "runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try writeJSON(makeComparisonReport(), to: comparisonURL)

        let signoffURL = runDirectory.appending(path: "external-signoff-review.json")
        try writeJSON(makeApprovedSignoffReview(), to: signoffURL)

        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeJSON(try makeManifest(
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
        #expect(result.roundTripReview?.artifacts.allSatisfy { $0.integrityStatus == .verified } == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func loadReviewByRunIDRejectsNoncanonicalRunDirectory() async throws {
        let root = try makeTemporaryRoot("review-noncanonical-runs")
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
        try writeJSON(try makeManifest(
            comparisonURL: comparisonURL,
            signoffURL: signoffURL
        ), to: manifestURL)

        let canonicalManifestURL = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "review-run")
            .appending(path: "round-trip-manifest.json")
        await #expect(throws: RoundTripReviewServiceError.missingManifest(canonicalManifestURL)) {
            try await RoundTripReviewService().loadReview(
                forProjectAt: root,
                runID: "review-run"
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func missingReviewArtifactIsDiagnosticNotLoadFailure() async throws {
        let root = try makeTemporaryRoot("review-missing-artifact")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let missingComparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try writeJSON(makeComparisonReport(), to: missingComparisonURL)
        let signoffURL = runDirectory.appending(path: "external-signoff-review.json")
        try writeJSON(makeApprovedSignoffReview(), to: signoffURL)

        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeJSON(try makeManifest(
            comparisonURL: missingComparisonURL,
            signoffURL: signoffURL
        ), to: manifestURL)
        try FileManager.default.removeItem(at: missingComparisonURL)

        let summary = try await RoundTripReviewService().loadReview(manifestURL: manifestURL)

        #expect(summary.status == .incomplete)
        #expect(summary.postLayoutComparison == nil)
        #expect(summary.diagnostics.contains { $0.contains("post-layout-comparison") })
        #expect(summary.artifacts.contains { $0.kind == "post-layout-comparison" && !$0.exists })
        #expect(summary.recommendations.contains { $0.contains("auditable") })
    }

    @Test(.timeLimit(.minutes(1)))
    func verifiedFailedSignoffArtifactFailsReviewStatus() async throws {
        let root = try makeTemporaryRoot("review-failed-signoff-artifact")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try writeJSON(makeComparisonReport(), to: comparisonURL)

        let signoffURL = runDirectory.appending(path: "external-signoff-review.json")
        try writeJSON(makeRejectedSignoffReview(), to: signoffURL)

        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeJSON(try makeManifest(
            comparisonURL: comparisonURL,
            signoffURL: signoffURL
        ), to: manifestURL)

        let summary = try await RoundTripReviewService().loadReview(manifestURL: manifestURL)

        #expect(summary.externalSignoff?.passed == false)
        #expect(summary.externalSignoff?.readyForPEX == false)
        #expect(summary.status == .failed)
        #expect(summary.isReadyForPEX == false)
        #expect(summary.diagnostics.isEmpty)
        #expect(summary.recommendations.contains { $0.contains("external signoff") })
    }

    @Test(.timeLimit(.minutes(1)))
    func failureSuggestedActionSelectionIsProjectedIntoReview() async throws {
        let root = try makeTemporaryRoot("review-selected-action")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        try await DesignFlowServiceTestSupport.createCanonicalRunLedger(
            projectRoot: root,
            runID: "review-run"
        )

        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try writeJSON(makeComparisonReport(), to: comparisonURL)
        let signoffURL = runDirectory.appending(path: "external-signoff-review.json")
        try writeJSON(makeApprovedSignoffReview(), to: signoffURL)

        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeJSON(try makeManifest(comparisonURL: comparisonURL, signoffURL: signoffURL), to: manifestURL)

        let failure = FlowRunnerFailureEnvelope(
            errorKind: "runtime",
            errorType: "RuntimeTestError",
            message: "Post-layout comparison exceeded configured limits.",
            runID: "review-run",
            projectRoot: root.path(percentEncoded: false),
            manifest: manifestURL.path(percentEncoded: false),
            stage: "post-layout-comparison",
            recommendation: "Inspect post-layout-comparison.json.",
            nextActions: [
                FlowRunNextAction(
                    actionID: "review-flow-runner-failure",
                    kind: "reviewFlowRunnerFailure",
                    stageID: "post-layout-comparison",
                    severity: .error,
                    reason: "Inspect failed artifacts.",
                    diagnosticCodes: ["runtime"],
                    suggestedActions: [
                        FlowRunSuggestedAction(
                            id: "review-flow-runner-failure",
                            readiness: .ready,
                            operation: .reviewRun,
                            runID: "review-run",
                            reason: "Load the failed run review from its persisted manifest."
                        ),
                    ]
                ),
            ]
        )

        let record = try await RoundTripActionLogService().recordSuggestedActionSelection(
            from: failure,
            actionID: "review-flow-runner-failure",
            reviewer: "agent-1"
        )
        let summary = try await RoundTripReviewService().loadReview(manifestURL: manifestURL)
        let selection = try #require(summary.suggestedActionSelections.first)

        #expect(record.actionKind == "review.selectSuggestedAction")
        #expect(record.stageID == "post-layout-comparison")
        #expect(selection.actionRecordID == record.actionID)
        #expect(selection.runID == "review-run")
        #expect(selection.actor.identifier == "agent-1")
        #expect(selection.nextActionID == "review-flow-runner-failure")
        #expect(selection.nextActionKind == "reviewFlowRunnerFailure")
        #expect(selection.action.id == "review-flow-runner-failure")
        #expect(selection.action.readiness == .ready)
        #expect(selection.action.operation == .reviewRun)
        #expect(summary.diagnostics.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func failureSuggestedActionSelectionRejectsManifestOutsideDeclaredProjectRoot() async throws {
        let root = try makeTemporaryRoot("review-selected-action-mismatch")
        let otherRoot = try makeTemporaryRoot("review-selected-action-other-root")
        defer {
            removeTemporaryRoot(root)
            removeTemporaryRoot(otherRoot)
        }

        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        try await DesignFlowServiceTestSupport.createCanonicalRunLedger(
            projectRoot: root,
            runID: "review-run"
        )
        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try writeJSON(makeComparisonReport(), to: comparisonURL)
        let signoffURL = runDirectory.appending(path: "external-signoff-review.json")
        try writeJSON(makeApprovedSignoffReview(), to: signoffURL)
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeJSON(try makeManifest(comparisonURL: comparisonURL, signoffURL: signoffURL), to: manifestURL)

        let failure = FlowRunnerFailureEnvelope(
            errorKind: "runtime",
            errorType: "RuntimeTestError",
            message: "Post-layout comparison exceeded configured limits.",
            runID: "review-run",
            projectRoot: otherRoot.path(percentEncoded: false),
            manifest: manifestURL.path(percentEncoded: false),
            stage: "post-layout-comparison",
            recommendation: "Inspect post-layout-comparison.json.",
            nextActions: [
                FlowRunNextAction(
                    actionID: "review-flow-runner-failure",
                    kind: "reviewFlowRunnerFailure",
                    stageID: "post-layout-comparison",
                    severity: .error,
                    reason: "Inspect failed artifacts.",
                    suggestedActions: [
                        FlowRunSuggestedAction(
                            id: "review-flow-runner-failure",
                            readiness: .ready,
                            operation: .reviewRun,
                            runID: "review-run",
                            reason: "Load the failed run review."
                        ),
                    ]
                ),
            ]
        )

        await #expect(throws: RoundTripActionLogServiceError.self) {
            try await RoundTripActionLogService().recordSuggestedActionSelection(
                from: failure,
                actionID: "review-flow-runner-failure",
                reviewer: "agent-1"
            )
        }
        #expect(!FileManager.default.fileExists(
            atPath: runDirectory.appending(path: "actions.jsonl").path(percentEncoded: false)
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func artifactResolverRejectsExternalURLInsteadOfReturningAbsoluteFallback() throws {
        let root = try makeTemporaryRoot("resolver-external-url")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let externalURL = root.appending(path: "external.txt")
        try "external\n".write(to: externalURL, atomically: true, encoding: .utf8)

        var didRejectExternalURL = false
        do {
            _ = try RoundTripArtifactResolver(runDirectory: runDirectory).relativePath(for: externalURL)
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
    func escapingReviewArtifactCannotBeRepresented() {
        #expect(throws: ArtifactLocationError.self) {
            _ = try ArtifactLocation(workspaceRelativePath: "../outside-comparison.json")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func symlinkEscapingRunDirectoryIsDiagnosticAndIsNotRead() async throws {
        let root = try makeTemporaryRoot("review-symlink-escape")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
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
        let baseManifest = try makeManifest(
            comparisonURL: externalComparisonURL,
            signoffURL: signoffURL
        )
        let comparisonData = try Data(contentsOf: externalComparisonURL)
        let maliciousLocator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: linkedComparisonURL.lastPathComponent),
            role: .output,
            kind: try ArtifactKind(rawValue: "post-layout-comparison"),
            format: .json
        )
        let maliciousReference = ArtifactReference(
            id: try ArtifactID(rawValue: "post-layout-comparison-linked"),
            locator: maliciousLocator,
            digest: try SHA256ContentDigester().digest(data: comparisonData, using: .sha256),
            byteCount: UInt64(comparisonData.count)
        )
        let manifest = HeadlessRoundTripService.Manifest(
            runID: baseManifest.runID,
            title: baseManifest.title,
            createdAt: baseManifest.createdAt,
            isRoundTripComplete: baseManifest.isRoundTripComplete,
            isReadyForPEX: baseManifest.isReadyForPEX,
            stages: baseManifest.stages,
            artifacts: [
                baseManifest.artifacts[0],
                HeadlessRoundTripService.Artifact(reference: maliciousReference),
            ],
            bottleneckSummary: baseManifest.bottleneckSummary
        )
        try writeJSON(manifest, to: manifestURL)

        let summary = try await RoundTripReviewService().loadReview(manifestURL: manifestURL)

        #expect(summary.status == .incomplete)
        #expect(summary.postLayoutComparison == nil)
        #expect(summary.diagnostics.contains { $0.contains("escapes") })
    }

    @Test(.timeLimit(.minutes(1)))
    func absoluteArtifactPathIsDiagnosticAndIsNotRead() async throws {
        let root = try makeTemporaryRoot("review-absolute-artifact")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try writeJSON(makeComparisonReport(), to: comparisonURL)

        let signoffURL = runDirectory.appending(path: "external-signoff-review.json")
        try writeJSON(makeApprovedSignoffReview(), to: signoffURL)

        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        var manifest = try makeManifest(comparisonURL: comparisonURL, signoffURL: signoffURL)
        let absoluteLocator = ArtifactLocator(
            location: try ArtifactLocation(fileURL: comparisonURL),
            role: .output,
            kind: try ArtifactKind(rawValue: "post-layout-comparison"),
            format: .json
        )
        let absoluteReference = try LocalArtifactReferencer().reference(absoluteLocator)
        manifest = HeadlessRoundTripService.Manifest(
            runID: manifest.runID,
            title: manifest.title,
            createdAt: manifest.createdAt,
            isRoundTripComplete: manifest.isRoundTripComplete,
            isReadyForPEX: manifest.isReadyForPEX,
            stages: manifest.stages,
            artifacts: [
                manifest.artifacts[0],
                HeadlessRoundTripService.Artifact(reference: absoluteReference),
            ],
            bottleneckSummary: manifest.bottleneckSummary
        )
        try writeJSON(manifest, to: manifestURL)

        let summary = try await RoundTripReviewService().loadReview(manifestURL: manifestURL)

        #expect(summary.status == .incomplete)
        #expect(summary.postLayoutComparison == nil)
        #expect(summary.diagnostics.contains { $0.contains("absolute") })
        #expect(summary.warnings.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func manifestMissingDigestIsRejectedAtLoad() async throws {
        let root = try makeTemporaryRoot("review-missing-digest")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try writeJSON(makeComparisonReport(), to: comparisonURL)

        let signoffURL = runDirectory.appending(path: "external-signoff-review.json")
        try writeJSON(makeApprovedSignoffReview(), to: signoffURL)

        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        let manifestJSON = """
        {
          "runID": "review-run",
          "title": "Review run",
          "createdAt": "2023-11-14T22:13:20Z",
          "isRoundTripComplete": true,
          "isReadyForPEX": true,
          "stages": [
            {"name": "external-signoff", "status": "passed"},
            {"name": "post-layout-comparison", "status": "passed", "message": "passed"}
          ],
          "artifacts": [
            {"kind": "external-signoff-review", "path": "external-signoff-review.json"},
            {"kind": "post-layout-comparison", "path": "post-layout-comparison.json"}
          ],
          "bottleneckSummary": null
        }
        """
        try manifestJSON.write(to: manifestURL, atomically: true, encoding: .utf8)

        do {
            _ = try await RoundTripReviewService().loadReview(manifestURL: manifestURL)
            Issue.record("Expected manifest without artifact digests to fail decoding.")
        } catch {
            #expect(error.localizedDescription.contains("round-trip manifest"))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func relativeArtifactManifestRemainsPortableAfterRunDirectoryMove() async throws {
        let originalRoot = try makeTemporaryRoot("review-portable-original")
        let movedRoot = try makeTemporaryRoot("review-portable-moved")
        defer { removeTemporaryRoot(originalRoot) }
        defer { removeTemporaryRoot(movedRoot) }

        let originalRunDirectory = originalRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: originalRunDirectory, withIntermediateDirectories: true)

        let comparisonURL = originalRunDirectory.appending(path: "post-layout-comparison.json")
        try writeJSON(makeComparisonReport(), to: comparisonURL)

        let signoffURL = originalRunDirectory.appending(path: "external-signoff-review.json")
        try writeJSON(makeApprovedSignoffReview(), to: signoffURL)

        let manifestURL = originalRunDirectory.appending(path: "round-trip-manifest.json")
        try writeJSON(try makeManifest(
            comparisonURL: comparisonURL,
            signoffURL: signoffURL
        ), to: manifestURL)

        let movedRunDirectory = movedRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(
            at: movedRunDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: originalRunDirectory, to: movedRunDirectory)

        let summary = try await RoundTripReviewService().loadReview(
            manifestURL: movedRunDirectory.appending(path: "round-trip-manifest.json")
        )

        #expect(summary.status == .passed)
        #expect(summary.diagnostics.isEmpty)
        #expect(summary.warnings.isEmpty)
        #expect(summary.artifacts.allSatisfy { $0.integrityStatus == .verified })
        #expect(summary.postLayoutComparison?.gateStatus == "passed")
    }

    @Test(.timeLimit(.minutes(1)))
    func tamperedArtifactFailsReviewIntegrityCheck() async throws {
        let root = try makeTemporaryRoot("review-tampered-artifact")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "review-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try writeJSON(makeComparisonReport(), to: comparisonURL)

        let signoffURL = runDirectory.appending(path: "external-signoff-review.json")
        try writeJSON(makeApprovedSignoffReview(), to: signoffURL)

        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeJSON(try makeManifest(
            comparisonURL: comparisonURL,
            signoffURL: signoffURL
        ), to: manifestURL)

        try "tampered\n".write(to: comparisonURL, atomically: true, encoding: .utf8)

        let summary = try await RoundTripReviewService().loadReview(manifestURL: manifestURL)

        #expect(summary.status == .incomplete)
        #expect(summary.postLayoutComparison == nil)
        #expect(summary.artifacts.contains {
            $0.kind == "post-layout-comparison" && $0.integrityStatus == .sha256Mismatch
        })
        #expect(summary.diagnostics.contains { $0.contains("SHA-256 mismatch") })
        #expect(summary.diagnostics.contains { $0.contains("byte count mismatch") })
    }

    private func makeManifest(
        comparisonURL: URL,
        signoffURL: URL
    ) throws -> HeadlessRoundTripService.Manifest {
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
                try makeArtifact(
                    kind: "external-signoff-review",
                    url: signoffURL,
                    sourcePath: "/source/external-signoff-review.json"
                ),
                try makeArtifact(
                    kind: "post-layout-comparison",
                    url: comparisonURL
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

    private func makeArtifact(
        kind: String,
        url: URL,
        sourcePath: String? = nil
    ) throws -> HeadlessRoundTripService.Artifact {
        let path = url.lastPathComponent
        let reference = try ArtifactReference.circuitStudioReference(
            id: "\(kind)-\(path)",
            kind: kind,
            relativePath: path,
            fileURL: url
        )
        return HeadlessRoundTripService.Artifact(
            reference: reference,
            sourcePath: sourcePath
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

    private func makeRejectedSignoffReview() -> ExternalSignoffReview {
        ExternalSignoffReview(
            reports: [
                ExternalSignoffToolReport(
                    kind: .drc,
                    toolName: "replay-drc",
                    success: false,
                    logPath: "/source/drc.log",
                    diagnostics: [
                        ExternalSignoffDiagnostic(
                            severity: .error,
                            message: "DRC violation",
                            ruleID: "met1.spacing",
                            rawLine: "met1.spacing violation"
                        ),
                    ]
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
