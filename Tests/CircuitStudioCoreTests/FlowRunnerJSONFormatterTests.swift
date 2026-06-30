import Foundation
import Testing
import XcircuitePackage
@testable import CircuitStudioApp

@Suite("FlowRunnerJSONFormatter Tests")
struct FlowRunnerJSONFormatterTests {
    @Test("JSON output preserves signoff repair cycle history summary", .timeLimit(.minutes(1)))
    func jsonOutputPreservesSignoffRepairCycleHistorySummary() throws {
        let summary = RunReviewSignoffRepairCandidateCycleHistorySummary(cycles: [
            RunReviewSignoffRepairCandidateCycleHistoryItem(
                actionID: "cycle-1",
                cycleIndex: 1,
                status: .succeeded,
                planID: "plan-1",
                generationStatus: "generated",
                executionStatus: "executed",
                verificationStatus: "accepted",
                accepted: true,
                rejectedPlansPath: ".xcircuite/runs/run-1/planning/rejected-plans.jsonl",
                rejectedPlanFeedbackRecordCount: 2,
                globalRejectedPlanFeedbackCount: 3,
                selectedActionIDs: ["repair-action-1"],
                selectedActionDomainIDs: ["layout-edit"],
                selectedObjectiveDomainIDs: ["drc"],
                feedbackPenalizedActionIDs: ["repair-action-0"],
                feedbackRankChanges: ["repair-action-0:1->2"],
                feedbackScoreDeltas: ["repair-action-0:-6"],
                candidatePlanArtifact: nil,
                planExecutionArtifact: nil,
                planVerificationArtifact: nil,
                rejectedPlansArtifact: nil,
                designDiffArtifact: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
        ])
        let result = DesignFlowCommandResult(
            kind: .runSignoffRepairCandidateCycle,
            runID: "run-1",
            signoffRepairCandidateCycleHistorySummary: summary
        )

        let data = try FlowRunnerJSONFormatter.data(for: result)
        let decoded = try JSONDecoder().decode(DesignFlowCommandResult.self, from: data)
        let decodedSummary = try #require(decoded.signoffRepairCandidateCycleHistorySummary)

        #expect(decoded.kind == .runSignoffRepairCandidateCycle)
        #expect(decoded.runID == "run-1")
        #expect(decodedSummary.cycleCount == 1)
        #expect(decodedSummary.acceptedCount == 1)
        #expect(decodedSummary.latestAccepted == .some(true))
        #expect(decodedSummary.consumedRejectedPlanFeedbackRecordCount == 2)
        #expect(decodedSummary.maximumGlobalRejectedPlanFeedbackCount == 3)
        #expect(decodedSummary.selectedActionDomainIDs == ["layout-edit"])
        #expect(decodedSummary.selectedObjectiveDomainIDs == ["drc"])
        #expect(decodedSummary.objectiveDomainSummaries.first?.domainID == "drc")
        #expect(decodedSummary.objectiveDomainSummaries.first?.acceptedCount == 1)
        #expect(decodedSummary.objectiveDomainSummaries.first?.acceptanceRate == 1.0)
        #expect(decodedSummary.feedbackRankChangedActionIDs == ["repair-action-0"])
        #expect(decodedSummary.feedbackScoreDeltaActionIDs == ["repair-action-0"])
        #expect(decodedSummary.hasFeedbackImpact)
    }

    @Test("JSON output preserves timing profile inspection diagnostics", .timeLimit(.minutes(1)))
    func jsonOutputPreservesTimingProfileInspectionDiagnostics() throws {
        let inspection = TimingModelProfileCatalogInspection(
            catalogID: "catalog-1",
            catalogPath: "/tmp/timing-profile-catalog.json",
            profiles: [
                TimingModelProfileCatalogInspection.Profile(
                    profileID: "profile-1",
                    displayName: "Profile 1",
                    sourceKind: .externalFile,
                    declaredCornerID: "ss",
                    profileResourceName: nil,
                    profilePath: "/tmp/profile-1.json",
                    defaultProfile: true,
                    status: .failed,
                    schemaVersion: nil,
                    processName: nil,
                    cornerID: nil,
                    deviceModelID: nil,
                    supplyVoltage: nil,
                    deviceModelHash: nil,
                    sha256: nil,
                    diagnostics: [
                        TimingModelProfileCatalogInspection.Diagnostic(
                            severity: "error",
                            code: "profile_load_failed",
                            message: "Profile resource could not be decoded."
                        ),
                    ]
                ),
            ]
        )
        let result = DesignFlowCommandResult(
            kind: .inspectTimingModelProfiles,
            timingModelProfileID: "profile-1",
            timingModelProfileCatalogID: "catalog-1",
            timingModelProfileCatalogPath: "/tmp/timing-profile-catalog.json",
            timingModelProfileCatalogInspection: inspection,
            timingModelCornerID: "ss"
        )

        let data = try FlowRunnerJSONFormatter.data(for: result)
        let decoded = try JSONDecoder().decode(DesignFlowCommandResult.self, from: data)
        let decodedProfile = decoded.timingModelProfileCatalogInspection?.profiles.first

        #expect(decoded.kind == .inspectTimingModelProfiles)
        #expect(decoded.timingModelCornerID == "ss")
        #expect(decodedProfile?.profileID == "profile-1")
        #expect(decodedProfile?.status == .failed)
        #expect(decodedProfile?.diagnostics.first?.code == "profile_load_failed")
        #expect(decodedProfile?.diagnostics.first?.severity == "error")
    }

    @Test("JSON output preserves failure envelope context", .timeLimit(.minutes(1)))
    func jsonOutputPreservesFailureEnvelopeContext() throws {
        let failure = FlowRunnerFailureEnvelope(
            errorKind: "command_validation",
            errorType: "DesignFlowCommandError",
            message: "Missing project root.",
            helpHint: nil,
            runID: "run-1",
            projectRoot: "/tmp/flow-output",
            manifest: "/tmp/flow-output/.xcircuite/flow-runs/run-1/round-trip-manifest.json",
            stage: "post-layout-comparison",
            manifestInspectionError: "Failed to inspect manifest '/tmp/flow-output/.xcircuite/flow-runs/run-1/round-trip-manifest.json': malformed JSON.",
            recommendation: "Inspect the manifest and stage artifacts for the structured failure evidence."
        )

        let data = try FlowRunnerJSONFormatter.data(for: failure)
        let decoded = try JSONDecoder().decode(FlowRunnerFailureEnvelope.self, from: data)

        #expect(decoded.schemaVersion == FlowRunnerFailureEnvelope.currentSchemaVersion)
        #expect(decoded.kind == FlowRunnerFailureEnvelope.envelopeKind)
        #expect(decoded.flowCommand == "failed")
        #expect(decoded.errorKind == "command_validation")
        #expect(decoded.errorType == "DesignFlowCommandError")
        #expect(decoded.message == "Missing project root.")
        #expect(decoded.runID == "run-1")
        #expect(decoded.projectRoot == "/tmp/flow-output")
        #expect(decoded.stage == "post-layout-comparison")
        #expect(decoded.manifestInspectionError == "Failed to inspect manifest '/tmp/flow-output/.xcircuite/flow-runs/run-1/round-trip-manifest.json': malformed JSON.")
        #expect(decoded.recommendation.contains("structured failure evidence"))
        #expect(decoded.nextActions.isEmpty)
    }

    @Test("Runtime failure envelope includes failed manifest stage", .timeLimit(.minutes(1)))
    func runtimeFailureEnvelopeIncludesFailedManifestStage() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "FlowRunnerFailureEnvelopeTests-\(UUID().uuidString)")
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove temporary directory \(root.path(percentEncoded: false)): \(error)")
            }
        }

        let runID = "failed-run"
        let manifestURL = root
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: runID)
            .appending(path: "round-trip-manifest.json")
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let manifest = HeadlessRoundTripService.Manifest(
            runID: runID,
            title: "Failed run",
            createdAt: Date(timeIntervalSince1970: 1_000),
            isRoundTripComplete: false,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(
                    name: "pre-layout-simulation",
                    status: .passed,
                    durationSeconds: 0.1
                ),
                HeadlessRoundTripService.Stage(
                    name: "post-layout-comparison",
                    status: .failed,
                    durationSeconds: 0.2
                ),
            ],
            artifacts: [],
            bottleneckSummary: HeadlessRoundTripService.BottleneckSummary(
                totalMeasuredDurationSeconds: 0.3,
                longestStageName: "post-layout-comparison",
                longestStageDurationSeconds: 0.2,
                failedStageName: "post-layout-comparison",
                recommendations: []
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        let options = try FlowRunnerCommandOptions(arguments: [
            "--output", root.path(percentEncoded: false),
            "--run-id", runID,
            "--json",
        ])
        let failure = FlowRunnerFailureEnvelopeBuilder.runtime(
            error: RuntimeTestError("Post-layout comparison exceeded configured limits."),
            options: options
        )

        #expect(failure.errorKind == "runtime")
        #expect(failure.runID == runID)
        #expect(failure.projectRoot == root.path(percentEncoded: false))
        #expect(failure.manifest == manifestURL.path(percentEncoded: false))
        #expect(failure.stage == "post-layout-comparison")
        #expect(failure.recommendation == "Inspect post-layout-comparison.json and adjust the design or comparison limits.")
        let nextAction = try #require(failure.nextActions.first)
        #expect(nextAction.kind == "reviewFlowRunnerFailure")
        #expect(nextAction.stageID == "post-layout-comparison")
        #expect(nextAction.suggestedCommands.map(\.commandID).contains("circuit-studio-flow-runner.review-round-trip"))
        #expect(nextAction.suggestedCommands.map(\.commandID).contains("circuit-studio-flow-runner.summarize-bottlenecks"))
        let reviewCommand = try #require(nextAction.suggestedCommands.first {
            $0.commandID == "circuit-studio-flow-runner.review-round-trip"
        })
        #expect(reviewCommand.readiness == .ready)
        #expect(reviewCommand.executable == "swift")
        #expect(reviewCommand.arguments.contains("--review-round-trip"))
        #expect(reviewCommand.arguments.contains(manifestURL.path(percentEncoded: false)))
    }

    @Test("Runtime failure envelope records unreadable manifest inspection failures", .timeLimit(.minutes(1)))
    func runtimeFailureEnvelopeRecordsUnreadableManifestInspectionFailures() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "FlowRunnerFailureEnvelopeMalformedManifestTests-\(UUID().uuidString)")
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove temporary directory \(root.path(percentEncoded: false)): \(error)")
            }
        }

        let runID = "failed-run"
        let manifestURL = root
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: runID)
            .appending(path: "round-trip-manifest.json")
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{not-json}".utf8).write(to: manifestURL, options: .atomic)

        let options = try FlowRunnerCommandOptions(arguments: [
            "--output", root.path(percentEncoded: false),
            "--run-id", runID,
            "--json",
        ])
        let failure = FlowRunnerFailureEnvelopeBuilder.runtime(
            error: RuntimeTestError("Unexpected runtime failure."),
            options: options
        )

        #expect(failure.manifest == manifestURL.path(percentEncoded: false))
        #expect(failure.stage == nil)
        #expect(failure.manifestInspectionError?.contains("Failed to inspect manifest") == true)
        #expect(failure.recommendation.contains("Repair or regenerate the manifest") == true)
        let nextAction = try #require(failure.nextActions.first)
        #expect(nextAction.diagnosticCodes.contains("manifest_unreadable"))
    }

    @Test("Usage failure envelope suggests help command", .timeLimit(.minutes(1)))
    func usageFailureEnvelopeSuggestsHelpCommand() throws {
        let failure = FlowRunnerFailureEnvelopeBuilder.usage(error: FlowRunnerCommandOptions.ParseError.invalidArgument("--bad"))
        let nextAction = try #require(failure.nextActions.first)
        let command = try #require(nextAction.suggestedCommands.first)

        #expect(failure.errorKind == "usage")
        #expect(nextAction.kind == "showFlowRunnerHelp")
        #expect(command.commandID == "circuit-studio-flow-runner.help")
        #expect(command.readiness == .ready)
        #expect(command.arguments == ["run", "--quiet", "circuit-studio-flow-runner", "--help"])
    }

    private struct RuntimeTestError: LocalizedError {
        let message: String

        init(_ message: String) {
            self.message = message
        }

        var errorDescription: String? {
            message
        }
    }
}
