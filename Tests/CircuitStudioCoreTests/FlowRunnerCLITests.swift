import Foundation
import CircuiteFoundation
import CircuiteFoundationCrypto
import LayoutCore
import Testing
import Xcircuite
import DesignFlowKernel
@testable import CircuitStudioApp

@Suite("circuit-studio-flow-runner CLI", .serialized)
struct FlowRunnerCLITests {
    @Test("run-layout-trust emits layout trust status without PEX readiness", .timeLimit(.minutes(5)))
    func runLayoutTrustOutputKeysSeparateTrustFromPEXReadiness() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioFlowRunnerCLITests-\(UUID().uuidString)")
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove temporary directory \(root.path(percentEncoded: false)): \(error)")
            }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let layoutURL = root.appending(path: "layout.json")
        try writeTrustedLayout(to: layoutURL)
        let outputRoot = root.appending(path: "out")
        // The layout technology must be explicit — the sampleProcess
        // fallback was a silent default and is gone by contract.
        let workspaceURL = try DesignFlowServiceTestSupport.rootFixtureURL("technology-package", extension: "json")
        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .runLayoutTrust,
            projectRootPath: outputRoot.path(percentEncoded: false),
            runID: "layout-trust-cli",
            technologyPackagePath: workspaceURL.path(percentEncoded: false),
            layoutDocumentPath: layoutURL.path(percentEncoded: false)
        ))
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)
        #expect(keys["layout_trust"] == "passed")
        #expect(keys["layout_trust_passed"] == "true")
        #expect(keys["layout_trust_report"]?.hasSuffix(".xcircuite/runs/layout-trust-cli/layout/layout-trust-report.json") == true)
        #expect(keys["ready_for_pex"] == nil)
    }

    @Test("run-verification emits both PEX readiness and layout trust status", .timeLimit(.minutes(1)))
    func runVerificationOutputKeysSeparatePEXReadinessFromLayoutTrust() {
        let result = DesignFlowCommandResult(
            kind: .runVerification,
            fixtureName: "unit",
            readyForPEX: false,
            layoutTrustPassed: true,
            layoutTrustReportPath: "/tmp/layout-trust-report.json",
            verificationReportPath: "/tmp/verification-report.json"
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["ready_for_pex"] == "false")
        #expect(keys["layout_trust_passed"] == "true")
        #expect(keys["verification_report"] == "/tmp/verification-report.json")
        #expect(keys["layout_trust_report"] == "/tmp/layout-trust-report.json")
    }

    @Test("run-verification arguments construct the verification command", .timeLimit(.minutes(1)))
    func runVerificationArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--run-verification",
            "--fixture", "acc4",
            "--output", "/tmp/flow-output",
            "--run-id", "verify-1",
            "--layout-document", "/tmp/layout.json",
            "--design-unit", "/tmp/design-unit.json",
            "--approve-signoff",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .runVerification)
        #expect(command.kind == .runVerification)
        #expect(command.fixtureName == "acc4")
        #expect(command.projectRootPath == "/tmp/flow-output")
        #expect(command.runID == "verify-1")
        #expect(command.layoutDocumentPath == "/tmp/layout.json")
        #expect(command.designUnitPath == "/tmp/design-unit.json")
        #expect(command.approveSignoff == true)
    }

    @Test("build-timing-library arguments construct the timing command", .timeLimit(.minutes(1)))
    func buildTimingLibraryArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--build-timing-library",
            "--output", "/tmp/flow-output",
            "--run-id", "timing-run-1",
            "--timing-model-profile", "/tmp/timing-profile.json",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .buildTimingLibrary)
        #expect(command.kind == .buildTimingLibrary)
        #expect(command.projectRootPath == "/tmp/flow-output")
        #expect(command.runID == "timing-run-1")
        #expect(command.timingModelProfilePath == "/tmp/timing-profile.json")
    }

    @Test("build-timing-library catalog arguments construct the timing command", .timeLimit(.minutes(1)))
    func buildTimingLibraryCatalogArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--build-timing-library",
            "--output", "/tmp/flow-output",
            "--run-id", "timing-run-1",
            "--timing-model-profile-catalog", "/tmp/timing-profile-catalog.json",
            "--timing-model-profile-id", "profile-1",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .buildTimingLibrary)
        #expect(command.kind == .buildTimingLibrary)
        #expect(command.projectRootPath == "/tmp/flow-output")
        #expect(command.runID == "timing-run-1")
        #expect(command.timingModelProfileCatalogPath == "/tmp/timing-profile-catalog.json")
        #expect(command.timingModelProfileID == "profile-1")
    }

    @Test("build-timing-library corner arguments construct the timing command", .timeLimit(.minutes(1)))
    func buildTimingLibraryCornerArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--build-timing-library",
            "--output", "/tmp/flow-output",
            "--run-id", "timing-run-1",
            "--timing-model-profile-catalog", "/tmp/timing-profile-catalog.json",
            "--timing-model-corner", "tt",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .buildTimingLibrary)
        #expect(command.kind == .buildTimingLibrary)
        #expect(command.projectRootPath == "/tmp/flow-output")
        #expect(command.runID == "timing-run-1")
        #expect(command.timingModelProfileCatalogPath == "/tmp/timing-profile-catalog.json")
        #expect(command.timingModelCornerID == "tt")
    }

    @Test("inspect-timing-model-profiles arguments construct the timing profile inspection command", .timeLimit(.minutes(1)))
    func inspectTimingModelProfilesArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--inspect-timing-model-profiles",
            "--timing-model-profile-catalog", "/tmp/timing-profile-catalog.json",
            "--timing-model-corner", "tt",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .inspectTimingModelProfiles)
        #expect(command.kind == .inspectTimingModelProfiles)
        #expect(command.projectRootPath == nil)
        #expect(command.timingModelProfileCatalogPath == "/tmp/timing-profile-catalog.json")
        #expect(command.timingModelCornerID == "tt")
    }

    @Test("signoff repair cycle history arguments construct the summary command", .timeLimit(.minutes(1)))
    func signoffRepairCycleHistoryArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--summarize-signoff-repair-cycles",
            "--output", "/tmp/flow-output",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .summarizeSignoffRepairCandidateCycles)
        #expect(command.kind == .summarizeSignoffRepairCandidateCycles)
        #expect(command.projectRootPath == "/tmp/flow-output")
    }

    @Test("signoff repair cycle history assessment arguments construct the assessment command", .timeLimit(.minutes(1)))
    func signoffRepairCycleHistoryAssessmentArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--assess-signoff-repair-cycles",
            "--output", "/tmp/flow-output",
            "--history-assessment-profile", "/tmp/history-profile.json",
            "--min-history-runs", "2",
            "--min-history-cycles", "3",
            "--min-history-accepted", "1",
            "--min-history-feedback-rank-changes", "2",
            "--min-history-feedback-score-deltas", "2",
            "--min-history-accepted-per-selected-objective-domain", "1",
            "--require-history-selected-action-domain", "layout-edit",
            "--require-history-selected-objective-domain", "drc",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .assessSignoffRepairCandidateCycles)
        #expect(command.kind == .assessSignoffRepairCandidateCycles)
        #expect(command.projectRootPath == "/tmp/flow-output")
        #expect(command.signoffRepairHistoryAssessmentProfilePath == "/tmp/history-profile.json")
        #expect(command.signoffRepairHistoryMinimumRunCount == 2)
        #expect(command.signoffRepairHistoryMinimumCycleCount == 3)
        #expect(command.signoffRepairHistoryMinimumAcceptedCount == 1)
        #expect(command.signoffRepairHistoryMinimumFeedbackRankChangeCount == 2)
        #expect(command.signoffRepairHistoryMinimumFeedbackScoreDeltaCount == 2)
        #expect(command.signoffRepairHistoryMinimumAcceptedCountPerSelectedObjectiveDomain == 1)
        #expect(command.signoffRepairHistoryRequiredSelectedActionDomainIDs == ["layout-edit"])
        #expect(command.signoffRepairHistoryRequiredSelectedObjectiveDomainIDs == ["drc"])
    }

    @Test("history assessment profile fixture decodes through the public service", .timeLimit(.minutes(1)))
    func historyAssessmentProfileFixtureDecodes() throws {
        let repositoryRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let profileURL = repositoryRoot
            .appending(path: "docs")
            .appending(path: "contract-fixtures")
            .appending(path: "signoff-repair-history-assessment-profile-v1.json")

        let profile = try SignoffRepairHistoryAssessor().loadProfile(from: profileURL)

        #expect(profile.schemaVersion == SignoffRepairHistoryAssessor.Profile.currentSchemaVersion)
        #expect(profile.profileID == "signoff-repair-history-assessment-v1")
        #expect(profile.request.minimumRunCount == 1)
        #expect(profile.request.minimumCycleCount == 1)
    }

    @Test("history assessment report fixture decodes canonically", .timeLimit(.minutes(1)))
    func historyAssessmentReportFixtureDecodesCanonically() throws {
        let repositoryRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let reportURL = repositoryRoot
            .appending(path: "docs")
            .appending(path: "contract-fixtures")
            .appending(path: "signoff-repair-history-assessment-report-v1.json")

        let report = try JSONDecoder().decode(
            SignoffRepairHistoryAssessor.Report.self,
            from: Data(contentsOf: reportURL)
        )

        #expect(report.schemaVersion == SignoffRepairHistoryAssessor.Report.currentSchemaVersion)
        #expect(!report.passed)
        #expect(report.failedGateIDs == ["minimum-run-count", "minimum-cycle-count"])
    }

    @Test("history assessment profile rejects incomplete fail-closed policy", .timeLimit(.minutes(1)))
    func historyAssessmentProfileRejectsIncompletePolicy() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                Issue.record("Failed to remove temporary history assessment fixture: \(error)")
            }
        }
        let profileURL = directory.appending(path: "incomplete-history-assessment.json")
        let incompleteProfile = """
        {
          "schemaVersion": 1,
          "profileID": "incomplete-history-assessment",
          "title": "Incomplete history assessment",
          "request": {
            "minimumRunCount": 1
          }
        }
        """
        try Data(incompleteProfile.utf8).write(to: profileURL)

        #expect(throws: SignoffRepairHistoryAssessor.AssessmentError.self) {
            try SignoffRepairHistoryAssessor().loadProfile(from: profileURL)
        }
    }

    @Test("history assessment rejects invalid programmatic thresholds", .timeLimit(.minutes(1)))
    func historyAssessmentRejectsInvalidProgrammaticThresholds() {
        let request = SignoffRepairHistoryAssessor.Request(minimumRunCount: -1)

        #expect(throws: EncodingError.self) {
            _ = try JSONEncoder().encode(request)
        }
        #expect(throws: SignoffRepairHistoryAssessor.AssessmentError.self) {
            _ = try SignoffRepairHistoryAssessor().assess(
                summary: emptyHistorySummary(),
                request: request
            )
        }
    }

    @Test("history assessment rejects invalid programmatic profiles", .timeLimit(.minutes(1)))
    func historyAssessmentRejectsInvalidProgrammaticProfiles() {
        #expect(throws: SignoffRepairHistoryAssessor.AssessmentError.self) {
            _ = try SignoffRepairHistoryAssessor.Profile(
                profileID: " invalid-profile ",
                title: "Invalid profile",
                request: SignoffRepairHistoryAssessor.Request()
            )
        }
    }

    @Test("history summary rejects incomplete evidence", .timeLimit(.minutes(1)))
    func historySummaryRejectsIncompleteEvidence() throws {
        let encoded = try JSONEncoder().encode(emptyHistorySummary())
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "selectedActionIDs")
        let incomplete = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary.self,
                from: incomplete
            )
        }
    }

    @Test("history assessment rejects inconsistent summary aggregates", .timeLimit(.minutes(1)))
    func historyAssessmentRejectsInconsistentSummaryAggregates() {
        let summary = RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary(
            runCount: 0,
            cycleCount: 1,
            acceptedCount: 1,
            notAcceptedCount: 0,
            consumedRejectedPlanFeedbackRecordCount: 0,
            maximumGlobalRejectedPlanFeedbackCount: 0,
            feedbackRankChangeCount: 0,
            feedbackScoreDeltaCount: 0,
            selectedActionIDs: [],
            selectedActionDomainIDs: [],
            selectedObjectiveDomainIDs: [],
            objectiveDomainSummaries: [],
            feedbackPenalizedActionIDs: [],
            feedbackRankChangedActionIDs: [],
            feedbackScoreDeltaActionIDs: [],
            runs: [],
            recommendations: []
        )

        #expect(throws: RunReviewSignoffRepairCandidateCycleHistoryIndexService.ValidationError.self) {
            _ = try SignoffRepairHistoryAssessor().assess(summary: summary)
        }
        #expect(throws: EncodingError.self) {
            _ = try JSONEncoder().encode(summary)
        }
    }

    @Test("history assessment report rejects tampered decisions", .timeLimit(.minutes(1)))
    func historyAssessmentReportRejectsTamperedDecisions() throws {
        let report = try SignoffRepairHistoryAssessor().assess(summary: emptyHistorySummary())
        let encoded = try JSONEncoder().encode(report)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["status"] = "passed"
        object["passed"] = true
        let tampered = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(SignoffRepairHistoryAssessor.Report.self, from: tampered)
        }
    }

    @Test("signoff repair cycle history output exposes retained aggregate evidence", .timeLimit(.minutes(1)))
    func signoffRepairCycleHistoryOutputIncludesAggregateEvidence() {
        let cycleSummary = RunReviewSignoffRepairCandidateCycleHistorySummary(cycles: [
            RunReviewSignoffRepairCandidateCycleHistoryItem(
                actionID: "cycle-1",
                cycleIndex: 1,
                status: .succeeded,
                planID: "candidate-plan-1",
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
        let runSummary = RunReviewSignoffRepairCandidateCycleHistoryIndexService.RunSummary(
            runID: "run-1",
            summaryPath: ".xcircuite/runs/run-1/planning/candidate-cycle-history/history-1.json",
            summary: cycleSummary
        )
        let history = RunReviewSignoffRepairCandidateCycleHistoryIndexService()
            .summarize(runSummaries: [runSummary])
        let result = DesignFlowCommandResult(
            kind: .summarizeSignoffRepairCandidateCycles,
            projectRootPath: "/tmp/flow-output",
            signoffRepairCandidateCycleHistoryIndex: history
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["signoff_repair_cycle_history"] == "summarized")
        #expect(keys["project_root"] == "/tmp/flow-output")
        #expect(keys["history_run_count"] == "1")
        #expect(keys["history_cycle_count"] == "1")
        #expect(keys["history_accepted_count"] == "1")
        #expect(keys["history_not_accepted_count"] == "0")
        #expect(keys["history_consumed_rejected_feedback_count"] == "2")
        #expect(keys["history_max_global_rejected_feedback_count"] == "3")
        #expect(keys["history_feedback_rank_change_count"] == "1")
        #expect(keys["history_feedback_score_delta_count"] == "1")
        #expect(keys["history_selected_actions"] == "repair-action-1")
        #expect(keys["history_selected_action_domains"] == "layout-edit")
        #expect(keys["history_selected_objective_domains"] == "drc")
        #expect(keys["history_objective_domain"] == "drc,cycles=1,accepted=1,not_accepted=0,acceptance_rate=1.0,rank_changes=1,score_deltas=1,actions=repair-action-1,action_domains=layout-edit")
        #expect(keys["history_feedback_penalized_actions"] == "repair-action-0")
        #expect(keys["history_feedback_rank_changed_actions"] == "repair-action-0")
        #expect(keys["history_feedback_score_delta_actions"] == "repair-action-0")
        #expect(keys["history_run"] == "run-1,cycles=1,accepted=1,rank_changes=1,summary=.xcircuite/runs/run-1/planning/candidate-cycle-history/history-1.json")
    }

    @Test("signoff repair cycle history assessment output exposes failed gates", .timeLimit(.minutes(1)))
    func signoffRepairCycleHistoryAssessmentOutputIncludesFailedGates() throws {
        let cycleSummary = RunReviewSignoffRepairCandidateCycleHistorySummary(cycles: [
            RunReviewSignoffRepairCandidateCycleHistoryItem(
                actionID: "cycle-1",
                cycleIndex: 1,
                status: .succeeded,
                planID: "candidate-plan-1",
                generationStatus: "generated",
                executionStatus: "executed",
                verificationStatus: "rejected",
                accepted: false,
                rejectedPlansPath: ".xcircuite/runs/run-1/planning/rejected-plans.jsonl",
                rejectedPlanFeedbackRecordCount: 1,
                globalRejectedPlanFeedbackCount: 1,
                selectedActionIDs: ["repair-action-1"],
                selectedActionDomainIDs: ["layout-edit"],
                selectedObjectiveDomainIDs: ["drc"],
                feedbackPenalizedActionIDs: ["repair-action-0"],
                feedbackRankChanges: [],
                feedbackScoreDeltas: [],
                candidatePlanArtifact: nil,
                planExecutionArtifact: nil,
                planVerificationArtifact: nil,
                rejectedPlansArtifact: nil,
                designDiffArtifact: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
        ])
        let runSummary = RunReviewSignoffRepairCandidateCycleHistoryIndexService.RunSummary(
            runID: "run-1",
            summaryPath: ".xcircuite/runs/run-1/planning/candidate-cycle-history/history-1.json",
            summary: cycleSummary
        )
        let history = RunReviewSignoffRepairCandidateCycleHistoryIndexService()
            .summarize(runSummaries: [runSummary])
        let report = try SignoffRepairHistoryAssessor()
            .assess(
                summary: history,
                request: SignoffRepairHistoryAssessor.Request(
                    minimumRunCount: 1,
                    minimumCycleCount: 1,
                    minimumAcceptedCount: 1,
                    minimumFeedbackRankChangeCount: 1,
                    minimumFeedbackScoreDeltaCount: 1,
                    minimumAcceptedCountPerSelectedObjectiveDomain: 1,
                    requiredSelectedActionDomainIDs: ["layout-edit", "pex-extraction"],
                    requiredSelectedObjectiveDomainIDs: ["drc", "pex"]
                ),
                profile: try SignoffRepairHistoryAssessor.Profile(
                    profileID: "candidate-cycle-history-smoke",
                    title: "Candidate cycle history smoke",
                    request: SignoffRepairHistoryAssessor.Request()
                ),
                profilePath: "/tmp/history-profile.json"
            )
        let result = DesignFlowCommandResult(
            kind: .assessSignoffRepairCandidateCycles,
            projectRootPath: "/tmp/flow-output",
            signoffRepairCandidateCycleHistoryIndex: history,
            signoffRepairCandidateCycleHistoryAssessment: report,
            signoffRepairCandidateCycleHistoryAssessmentArtifact: try artifactBinding(
                artifactID: SignoffRepairHistoryAssessor.reportArtifactID,
                path: ".xcircuite/retained/history-assessment.json",
                byteCount: 456
            ).reference,
            signoffRepairCandidateCycleHistoryAssessmentPath:
                "/tmp/flow-output/.xcircuite/retained/history-assessment.json"
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["signoff_repair_cycle_history_assessment"] == "failed")
        #expect(keys["assessment_passed"] == "false")
        #expect(keys["assessment_report"] == "/tmp/flow-output/.xcircuite/retained/history-assessment.json")
        #expect(keys["assessment_report_sha256"] == String(repeating: "0", count: 64))
        #expect(keys["assessment_report_bytes"] == "456")
        #expect(keys["assessment_profile_id"] == "candidate-cycle-history-smoke")
        #expect(keys["assessment_profile_title"] == "Candidate cycle history smoke")
        #expect(keys["assessment_profile_path"] == "/tmp/history-profile.json")
        #expect(keys["assessment_failed_gates"] == "minimum-accepted-count,minimum-feedback-rank-change-count,minimum-feedback-score-delta-count,required-selected-action-domains,required-selected-objective-domains,minimum-accepted-count-per-selected-objective-domain")
        #expect(keys["assessment_min_history_accepted"] == "1")
        #expect(keys["assessment_min_history_accepted_per_selected_objective_domain"] == "1")
        #expect(keys["assessment_required_selected_action_domains"] == "layout-edit,pex-extraction")
        #expect(keys["assessment_required_selected_objective_domains"] == "drc,pex")
        #expect(keys["assessment_missing_selected_action_domains"] == "pex-extraction")
        #expect(keys["assessment_missing_selected_objective_domains"] == "pex")
        #expect(keys["assessment_below_threshold_selected_objective_domains"] == "drc,pex")
        #expect(keys["history_run_count"] == "1")
        #expect(keys["history_cycle_count"] == "1")
        #expect(keys["history_accepted_count"] == "0")
        #expect(keys["history_objective_domain"] == "drc,cycles=1,accepted=0,not_accepted=1,acceptance_rate=0.0,rank_changes=0,score_deltas=0,actions=repair-action-1,action_domains=layout-edit")
        #expect(output.contains("assessment_gate=minimum-accepted-count,passed=false,observed=0,required=1"))
        #expect(output.contains("assessment_gate=minimum-feedback-rank-change-count,passed=false,observed=0,required=1"))
        #expect(output.contains("assessment_gate=required-selected-action-domains,passed=false,observed=1,required=2"))
        #expect(output.contains("assessment_gate=required-selected-objective-domains,passed=false,observed=1,required=2"))
        #expect(output.contains("assessment_gate=minimum-accepted-count-per-selected-objective-domain,passed=false,observed=0,required=1"))
        #expect(output.contains("recommendation=Failed gates: minimum-accepted-count,minimum-feedback-rank-change-count,minimum-feedback-score-delta-count,required-selected-action-domains,required-selected-objective-domains,minimum-accepted-count-per-selected-objective-domain"))
        #expect(output.contains("recommendation=Retain candidate-cycle evidence for selected action domains: pex-extraction."))
        #expect(output.contains("recommendation=Retain candidate-cycle evidence for selected objective domains: pex."))
        #expect(output.contains("recommendation=Retain accepted candidate-cycle evidence for selected objective domains: drc,pex."))
    }

    @Test("signoff repair cycle history assessment command reads retained summaries", .timeLimit(.minutes(1)))
    func signoffRepairCycleHistoryAssessmentCommandReadsRetainedSummaries() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioSignoffRepairAssessment-\(UUID().uuidString)")
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove temporary directory \(root.path(percentEncoded: false)): \(error)")
            }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try await DesignFlowServiceTestSupport.createCanonicalRunLedger(
            projectRoot: root,
            runID: "run-1"
        )
        let profileURL = root.appending(path: "history-assessment-profile.json")
        let profile = try SignoffRepairHistoryAssessor.Profile(
            profileID: "candidate-cycle-history-assessed",
            title: "Candidate cycle history assessed",
            description: "Requires retained accepted feedback-sensitive candidate-cycle evidence.",
            request: SignoffRepairHistoryAssessor.Request(
                minimumRunCount: 1,
                minimumCycleCount: 1,
                minimumAcceptedCount: 1,
                minimumFeedbackRankChangeCount: 1,
                minimumFeedbackScoreDeltaCount: 1,
                minimumAcceptedCountPerSelectedObjectiveDomain: 1,
                requiredSelectedActionDomainIDs: ["layout-edit"],
                requiredSelectedObjectiveDomainIDs: ["drc"]
            )
        )
        try JSONEncoder().encode(profile).write(to: profileURL, options: .atomic)
        let summary = RunReviewSignoffRepairCandidateCycleHistorySummary(cycles: [
            RunReviewSignoffRepairCandidateCycleHistoryItem(
                actionID: "cycle-1",
                cycleIndex: 1,
                status: .succeeded,
                planID: "candidate-plan-1",
                generationStatus: "generated",
                executionStatus: "executed",
                verificationStatus: "accepted",
                accepted: true,
                rejectedPlansPath: ".xcircuite/runs/run-1/planning/rejected-plans.jsonl",
                rejectedPlanFeedbackRecordCount: 1,
                globalRejectedPlanFeedbackCount: 2,
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let summaryContent = try encoder.encode(summary)
        let summaryBinding = try RunReviewTestSupport.artifactBinding(
            artifactID: "planning-candidate-cycle-history-summary-1",
            path: ".xcircuite/runs/run-1/planning/candidate-cycle-history/history-1.json",
            payload: summaryContent,
            kind: .other,
            format: .json
        )
        _ = try await store.appendActionArtifacts(
            [XcircuitePreparedArtifact(
                binding: summaryBinding,
                content: summaryContent
            )],
            action: FlowRunActionRecord(
                actionID: "retain-candidate-cycle-history-1",
                runID: "run-1",
                actor: FlowRunActor(kind: .cli, identifier: "circuit-studio-tests"),
                actionKind: "planning.retain-candidate-cycle-history",
                status: .succeeded,
                outputs: [summaryBinding.reference]
            )
        )

        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .assessSignoffRepairCandidateCycles,
            projectRootPath: root.path(percentEncoded: false),
            signoffRepairHistoryAssessmentProfilePath: profileURL.path(percentEncoded: false)
        ))

        #expect(result.signoffRepairCandidateCycleHistoryAssessment?.passed == true)
        #expect(
            result.signoffRepairCandidateCycleHistoryAssessment?.artifactReference
                == result.signoffRepairCandidateCycleHistoryAssessmentArtifact
        )
        #expect(result.signoffRepairCandidateCycleHistoryAssessment?.failedGateIDs.isEmpty == true)
        #expect(result.signoffRepairCandidateCycleHistoryAssessment?.profileID == "candidate-cycle-history-assessed")
        #expect(result.signoffRepairCandidateCycleHistoryAssessment?.profilePath == profileURL.path(percentEncoded: false))
        #expect(result.signoffRepairCandidateCycleHistoryAssessment?.request.minimumAcceptedCount == 1)
        #expect(
            result.signoffRepairCandidateCycleHistoryAssessment?
                .request.minimumAcceptedCountPerSelectedObjectiveDomain == 1
        )
        #expect(
            result.signoffRepairCandidateCycleHistoryAssessment?.request.requiredSelectedActionDomainIDs
                == ["layout-edit"]
        )
        #expect(
            result.signoffRepairCandidateCycleHistoryAssessment?.request.requiredSelectedObjectiveDomainIDs
                == ["drc"]
        )
        #expect(
            result.signoffRepairCandidateCycleHistoryAssessment?.missingSelectedActionDomainIDs.isEmpty == true
        )
        #expect(
            result.signoffRepairCandidateCycleHistoryAssessment?.missingSelectedObjectiveDomainIDs.isEmpty == true
        )
        #expect(
            result.signoffRepairCandidateCycleHistoryAssessment?
                .belowThresholdSelectedObjectiveDomainIDs.isEmpty == true
        )
        #expect(result.signoffRepairCandidateCycleHistoryIndex?.runCount == 1)
        #expect(result.signoffRepairCandidateCycleHistoryIndex?.selectedActionDomainIDs == ["layout-edit"])
        #expect(result.signoffRepairCandidateCycleHistoryIndex?.selectedObjectiveDomainIDs == ["drc"])
        #expect(result.signoffRepairCandidateCycleHistoryIndex?.objectiveDomainSummaries.first?.domainID == "drc")
        #expect(result.signoffRepairCandidateCycleHistoryIndex?.objectiveDomainSummaries.first?.acceptedCount == 1)
        #expect(result.signoffRepairCandidateCycleHistoryIndex?.feedbackRankChangeCount == 1)
        #expect(result.signoffRepairCandidateCycleHistoryIndex?.feedbackScoreDeltaCount == 1)

        let assessmentPath = try #require(result.signoffRepairCandidateCycleHistoryAssessmentPath)
        #expect(FileManager.default.fileExists(atPath: assessmentPath))
        let persistedReport = try JSONDecoder().decode(
            SignoffRepairHistoryAssessor.Report.self,
            from: Data(contentsOf: URL(filePath: assessmentPath))
        )
        let resultReport = try #require(result.signoffRepairCandidateCycleHistoryAssessment)
        #expect(persistedReport.status == resultReport.status)
        #expect(persistedReport.passed == resultReport.passed)
        #expect(persistedReport.profileID == resultReport.profileID)
        #expect(persistedReport.profileTitle == resultReport.profileTitle)
        #expect(persistedReport.profilePath == resultReport.profilePath)
        #expect(persistedReport.request == resultReport.request)
        #expect(persistedReport.summary == resultReport.summary)
        #expect(persistedReport.gates == resultReport.gates)
        #expect(persistedReport.failedGateIDs == resultReport.failedGateIDs)
        #expect(persistedReport.missingSelectedActionDomainIDs == resultReport.missingSelectedActionDomainIDs)
        #expect(persistedReport.missingSelectedObjectiveDomainIDs == resultReport.missingSelectedObjectiveDomainIDs)
        #expect(
            persistedReport.belowThresholdSelectedObjectiveDomainIDs
                == resultReport.belowThresholdSelectedObjectiveDomainIDs
        )
        #expect(persistedReport.recommendations == resultReport.recommendations)
        #expect(persistedReport.artifactReference == nil)
        let assessmentArtifact = try #require(result.signoffRepairCandidateCycleHistoryAssessmentArtifact)
        #expect(assessmentPath.hasSuffix("/.xcircuite/retained/history-assessment.json"))
        #expect(!assessmentArtifact.digest.hexadecimalValue.isEmpty)
        #expect(assessmentArtifact.byteCount > 0)

        let manifest = try await XcircuiteWorkspaceStore(projectRoot: root).loadManifest()
        #expect(manifest.files.contains { file in
            file.artifactID == SignoffRepairHistoryAssessor.reportArtifactID
                && file.path == ".xcircuite/retained/history-assessment.json"
                && file.digest == assessmentArtifact.digest
                && file.byteCount == assessmentArtifact.byteCount
        })
    }

    @Test("json output argument selects JSON command result output", .timeLimit(.minutes(1)))
    func jsonOutputArgumentSelectsCommandResultOutput() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--inspect-timing-model-profiles",
            "--timing-model-corner", "ss",
            "--json",
        ])

        #expect(options.mode == .inspectTimingModelProfiles)
        #expect(options.outputFormat == .json)
        #expect(options.makeCommand().timingModelCornerID == "ss")
    }

    @Test("approve-gate arguments construct a canonical stage approval command", .timeLimit(.minutes(1)))
    func approveGateArgumentsConstructCanonicalStageApprovalCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--approve-gate",
            "--output", "/tmp/flow-output",
            "--run-id", "run-1",
            "--approval-stage", "001-drc",
            "--approval-verdict", "waived",
            "--reviewer", "reviewer-1",
            "--approval-note", "Reviewed waiver evidence.",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .approveGate)
        #expect(command.kind == .approveGate)
        #expect(command.projectRootPath == "/tmp/flow-output")
        #expect(command.runID == "run-1")
        #expect(command.approvalStageID == "001-drc")
        #expect(command.approvalVerdict == .waived)
        #expect(command.approvalReviewer == "reviewer-1")
        #expect(command.approvalNote == "Reviewed waiver evidence.")
    }

    @Test("select-failure-action arguments construct the failure action selection command", .timeLimit(.minutes(1)))
    func selectFailureActionArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--select-failure-action",
            "--failure-envelope", "/tmp/flow-runner-failure.json",
            "--action-id", "review-flow-runner-failure",
            "--reviewer", "agent-1",
            "--json",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .selectFailureSuggestedAction)
        #expect(options.outputFormat == .json)
        #expect(command.kind == .selectFailureSuggestedAction)
        #expect(command.failureEnvelopePath == "/tmp/flow-runner-failure.json")
        #expect(command.suggestedActionID == "review-flow-runner-failure")
        #expect(command.approvalReviewer == "agent-1")
    }

    @Test("run-selected-suggested-action arguments construct the selected action dispatcher", .timeLimit(.minutes(1)))
    func runSelectedSuggestedActionArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--run-selected-suggested-action",
            "--output", "/tmp/flow-output",
            "--run-id", "run-1",
            "--action-id", "review-flow-runner-failure",
            "--json",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .runSelectedSuggestedAction)
        #expect(options.outputFormat == .json)
        #expect(command.kind == .runSelectedSuggestedAction)
        #expect(command.projectRootPath == "/tmp/flow-output")
        #expect(command.runID == "run-1")
        #expect(command.suggestedActionID == "review-flow-runner-failure")
    }

    @Test("select-failure-action output records action log and selected action", .timeLimit(.minutes(1)))
    func selectFailureActionOutputIncludesActionLedger() {
        let result = DesignFlowCommandResult(
            kind: .selectFailureSuggestedAction,
            runID: "run-1",
            projectRootPath: "/tmp/flow-output",
            manifestPath: "/tmp/flow-output/.xcircuite/runs/run-1/round-trip-manifest.json",
            actionLogPath: "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl",
            selectedSuggestedAction: FlowRunSuggestedActionSelection(
                actionRecordID: "round-trip-suggested-action-selection-1",
                runID: "run-1",
                actor: FlowRunActor(kind: .human, identifier: "agent-1"),
                status: .succeeded,
                selectedAt: Date(timeIntervalSince1970: 1_700_000_000),
                nextActionID: "review-flow-runner-failure",
                nextActionKind: "reviewFlowRunnerFailure",
                action: FlowRunSuggestedAction(
                    id: "review-flow-runner-failure",
                    readiness: .ready,
                    operation: .reviewRun,
                    runID: "run-1",
                    reason: "Load the failed run review."
                )
            ),
            message: "round-trip-suggested-action-selection-1"
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["suggested_action_selection"] == "recorded")
        #expect(keys["run_id"] == "run-1")
        #expect(keys["manifest"] == "/tmp/flow-output/.xcircuite/runs/run-1/round-trip-manifest.json")
        #expect(keys["actions"] == "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl")
        #expect(keys["action_id"] == "round-trip-suggested-action-selection-1")
        #expect(keys["suggested_action_id"] == "review-flow-runner-failure")
        #expect(keys["readiness"] == "ready")
        #expect(keys["operation"] == "reviewRun")
    }

    @Test("apply-waiver-edit arguments construct the waiver edit command", .timeLimit(.minutes(1)))
    func applyWaiverEditArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--apply-waiver-edit",
            "--output", "/tmp/flow-output",
            "--run-id", "run-1",
            "--reviewer", "reviewer-1",
            "--approval-note", "Apply obsolete waiver cleanup.",
            "--waiver-review", "drc-waiver:.xcircuite/runs/run-1/stages/001/raw/drc-summary.json",
            "--waiver-proposal", "remove-obsolete-drc-waiver",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .applyWaiverEditProposal)
        #expect(command.kind == .applyWaiverEditProposal)
        #expect(command.projectRootPath == "/tmp/flow-output")
        #expect(command.runID == "run-1")
        #expect(command.approvalReviewer == "reviewer-1")
        #expect(command.approvalNote == "Apply obsolete waiver cleanup.")
        #expect(command.waiverReviewID == "drc-waiver:.xcircuite/runs/run-1/stages/001/raw/drc-summary.json")
        #expect(command.waiverProposalID == "remove-obsolete-drc-waiver")
    }

    @Test("apply-waiver-edit output records action log and action ID", .timeLimit(.minutes(1)))
    func applyWaiverEditOutputIncludesActionLedger() {
        let result = DesignFlowCommandResult(
            kind: .applyWaiverEditProposal,
            runID: "run-1",
            projectRootPath: "/tmp/flow-output",
            actionLogPath: "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl",
            message: "waiver-edit-proposal-application-1"
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["waiver_edit"] == "applied")
        #expect(keys["run_id"] == "run-1")
        #expect(keys["project_root"] == "/tmp/flow-output")
        #expect(keys["actions"] == "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl")
        #expect(keys["action_id"] == "waiver-edit-proposal-application-1")
    }

    @Test("post-waiver-edit verification arguments construct the verification command", .timeLimit(.minutes(1)))
    func postWaiverEditVerificationArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--run-post-waiver-edit-verification",
            "--fixture", "voltage-divider",
            "--output", "/tmp/flow-output",
            "--run-id", "run-1",
            "--reviewer", "agent-1",
            "--approval-note", "Verify after waiver cleanup.",
            "--layout-document", "/tmp/layout.json",
            "--design-unit", "/tmp/design-unit.json",
            "--waiver-review", "drc-waiver:.xcircuite/runs/run-1/stages/001/raw/drc-summary.json",
            "--waiver-proposal", "remove-obsolete-drc-waiver",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .runPostWaiverEditVerification)
        #expect(command.kind == .runPostWaiverEditVerification)
        #expect(command.fixtureName == "voltage-divider")
        #expect(command.projectRootPath == "/tmp/flow-output")
        #expect(command.runID == "run-1")
        #expect(command.approvalReviewer == "agent-1")
        #expect(command.approvalNote == "Verify after waiver cleanup.")
        #expect(command.layoutDocumentPath == "/tmp/layout.json")
        #expect(command.designUnitPath == "/tmp/design-unit.json")
        #expect(command.waiverReviewID == "drc-waiver:.xcircuite/runs/run-1/stages/001/raw/drc-summary.json")
        #expect(command.waiverProposalID == "remove-obsolete-drc-waiver")
    }

    @Test("post-waiver-edit verification output records report and action ledger", .timeLimit(.minutes(1)))
    func postWaiverEditVerificationOutputIncludesReportAndActionLedger() {
        let result = DesignFlowCommandResult(
            kind: .runPostWaiverEditVerification,
            runID: "run-1",
            projectRootPath: "/tmp/flow-output",
            readyForPEX: true,
            actionLogPath: "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl",
            verificationReportPath: "/tmp/flow-output/.xcircuite/runs/run-1/reports/physical-verification.json",
            message: "waiver-edit-proposal-verification-1"
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["waiver_edit_verification"] == "")
        #expect(keys["run_id"] == "run-1")
        #expect(keys["project_root"] == "/tmp/flow-output")
        #expect(keys["ready_for_pex"] == "true")
        #expect(keys["verification_report"] == "/tmp/flow-output/.xcircuite/runs/run-1/reports/physical-verification.json")
        #expect(keys["actions"] == "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl")
        #expect(keys["action_id"] == "waiver-edit-proposal-verification-1")
    }

    @Test("conflicting runner modes are rejected by the shared parser", .timeLimit(.minutes(1)))
    func conflictingRunnerModesAreRejected() {
        #expect(throws: FlowRunnerCommandOptions.ParseError.conflictingModes) {
            _ = try FlowRunnerCommandOptions(arguments: ["--run-layout-trust", "--run-verification"])
        }
    }

    @Test("removed file-backed planning modes are rejected", .timeLimit(.minutes(1)))
    func removedFileBackedPlanningModesAreRejected() {
        for option in [
            "--formulate-signoff-repair-planning",
            "--run-signoff-repair-candidate-cycle",
        ] {
            #expect(throws: FlowRunnerCommandOptions.ParseError.invalidArgument(option)) {
                _ = try FlowRunnerCommandOptions(arguments: [option])
            }
        }
    }

    @Test("value options reject a following option token as a missing value", .timeLimit(.minutes(1)))
    func valueOptionsRejectFollowingOptionToken() {
        #expect(throws: FlowRunnerCommandOptions.ParseError.missingValue("--output")) {
            _ = try FlowRunnerCommandOptions(arguments: ["--run-verification", "--output", "--json"])
        }
    }

    private func emptyHistorySummary()
        -> RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary {
        RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary(
            runCount: 0,
            cycleCount: 0,
            acceptedCount: 0,
            notAcceptedCount: 0,
            consumedRejectedPlanFeedbackRecordCount: 0,
            maximumGlobalRejectedPlanFeedbackCount: 0,
            feedbackRankChangeCount: 0,
            feedbackScoreDeltaCount: 0,
            selectedActionIDs: [],
            feedbackPenalizedActionIDs: [],
            feedbackRankChangedActionIDs: [],
            feedbackScoreDeltaActionIDs: [],
            runs: [],
            recommendations: []
        )
    }

    private func writeTrustedLayout(to url: URL) throws {
        let cellID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let netID = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
        let shapeID = UUID(uuidString: "00000000-0000-0000-0000-000000000403")!
        let layout = LayoutDocument(
            name: "TrustedLayout",
            cells: [
                LayoutCell(
                    id: cellID,
                    name: "TOP",
                    shapes: [
                        LayoutShape(
                            id: shapeID,
                            layer: LayoutLayerID(name: "M1", purpose: "drawing"),
                            netID: netID,
                            geometry: .rect(LayoutRect(
                                origin: LayoutPoint(x: 0, y: 0),
                                size: LayoutSize(width: 2, height: 1)
                            ))
                        ),
                    ],
                    nets: [LayoutNet(id: netID, name: "out")]
                ),
            ],
            topCellID: cellID
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(layout).write(to: url, options: .atomic)
    }

    private func artifactBinding(
        artifactID: String,
        path: String,
        byteCount: UInt64 = 0
    ) throws -> FlowArtifactBinding {
        try RunReviewTestSupport.artifactBinding(
            artifactID: artifactID,
            path: path,
            kind: .other,
            format: .json,
            byteCount: byteCount
        )
    }

    private func keyValueOutput(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(separator: "\n") {
            guard let separator = line.firstIndex(of: "=") else {
                continue
            }
            let key = String(line[..<separator])
            let value = String(line[line.index(after: separator)...])
            result[key] = value
        }
        return result
    }
}
