import Foundation
import LayoutCore
import Testing
import Xcircuite
import XcircuitePackage
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
        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .runLayoutTrust,
            projectRootPath: outputRoot.path(percentEncoded: false),
            runID: "layout-trust-cli",
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

    @Test("signoff repair cycle history qualification arguments construct the qualification command", .timeLimit(.minutes(1)))
    func signoffRepairCycleHistoryQualificationArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--qualify-signoff-repair-cycles",
            "--output", "/tmp/flow-output",
            "--history-qualification-profile", "/tmp/history-profile.json",
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

        #expect(options.mode == .qualifySignoffRepairCandidateCycles)
        #expect(command.kind == .qualifySignoffRepairCandidateCycles)
        #expect(command.projectRootPath == "/tmp/flow-output")
        #expect(command.signoffRepairHistoryQualificationProfilePath == "/tmp/history-profile.json")
        #expect(command.signoffRepairHistoryMinimumRunCount == 2)
        #expect(command.signoffRepairHistoryMinimumCycleCount == 3)
        #expect(command.signoffRepairHistoryMinimumAcceptedCount == 1)
        #expect(command.signoffRepairHistoryMinimumFeedbackRankChangeCount == 2)
        #expect(command.signoffRepairHistoryMinimumFeedbackScoreDeltaCount == 2)
        #expect(command.signoffRepairHistoryMinimumAcceptedCountPerSelectedObjectiveDomain == 1)
        #expect(command.signoffRepairHistoryRequiredSelectedActionDomainIDs == ["layout-edit"])
        #expect(command.signoffRepairHistoryRequiredSelectedObjectiveDomainIDs == ["drc"])
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
            summaryPath: ".xcircuite/runs/run-1/planning/candidate-cycle-history-summary.json",
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
        #expect(keys["history_run"] == "run-1,cycles=1,accepted=1,rank_changes=1,summary=.xcircuite/runs/run-1/planning/candidate-cycle-history-summary.json")
    }

    @Test("signoff repair cycle history qualification output exposes failed gates", .timeLimit(.minutes(1)))
    func signoffRepairCycleHistoryQualificationOutputIncludesFailedGates() {
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
            summaryPath: ".xcircuite/runs/run-1/planning/candidate-cycle-history-summary.json",
            summary: cycleSummary
        )
        let history = RunReviewSignoffRepairCandidateCycleHistoryIndexService()
            .summarize(runSummaries: [runSummary])
        let report = RunReviewSignoffRepairCandidateCycleHistoryQualificationService()
            .qualify(
                summary: history,
                request: RunReviewSignoffRepairCandidateCycleHistoryQualificationService.Request(
                    minimumRunCount: 1,
                    minimumCycleCount: 1,
                    minimumAcceptedCount: 1,
                    minimumFeedbackRankChangeCount: 1,
                    minimumFeedbackScoreDeltaCount: 1,
                    minimumAcceptedCountPerSelectedObjectiveDomain: 1,
                    requiredSelectedActionDomainIDs: ["layout-edit", "pex-extraction"],
                    requiredSelectedObjectiveDomainIDs: ["drc", "pex"]
                ),
                profile: RunReviewSignoffRepairCandidateCycleHistoryQualificationService.Profile(
                    profileID: "candidate-cycle-history-smoke",
                    title: "Candidate cycle history smoke",
                    request: RunReviewSignoffRepairCandidateCycleHistoryQualificationService.Request()
                ),
                profilePath: "/tmp/history-profile.json"
            )
        let result = DesignFlowCommandResult(
            kind: .qualifySignoffRepairCandidateCycles,
            projectRootPath: "/tmp/flow-output",
            signoffRepairCandidateCycleHistoryIndex: history,
            signoffRepairCandidateCycleHistoryQualification: report,
            signoffRepairCandidateCycleHistoryQualificationArtifact: XcircuiteFileReference(
                artifactID: RunReviewSignoffRepairCandidateCycleHistoryQualificationService.reportArtifactID,
                path: ".xcircuite/retained/signoff-repair-cycle-history-qualification.json",
                kind: .other,
                format: .json,
                sha256: "abc123",
                byteCount: 456
            ),
            signoffRepairCandidateCycleHistoryQualificationPath:
                "/tmp/flow-output/.xcircuite/retained/signoff-repair-cycle-history-qualification.json"
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["signoff_repair_cycle_history_qualification"] == "failed")
        #expect(keys["qualification_passed"] == "false")
        #expect(keys["qualification_report"] == "/tmp/flow-output/.xcircuite/retained/signoff-repair-cycle-history-qualification.json")
        #expect(keys["qualification_report_sha256"] == "abc123")
        #expect(keys["qualification_report_bytes"] == "456")
        #expect(keys["qualification_profile_id"] == "candidate-cycle-history-smoke")
        #expect(keys["qualification_profile_title"] == "Candidate cycle history smoke")
        #expect(keys["qualification_profile_path"] == "/tmp/history-profile.json")
        #expect(keys["qualification_failed_gates"] == "minimum-accepted-count,minimum-feedback-rank-change-count,minimum-feedback-score-delta-count,required-selected-action-domains,required-selected-objective-domains,minimum-accepted-count-per-selected-objective-domain")
        #expect(keys["qualification_min_history_accepted"] == "1")
        #expect(keys["qualification_min_history_accepted_per_selected_objective_domain"] == "1")
        #expect(keys["qualification_required_selected_action_domains"] == "layout-edit,pex-extraction")
        #expect(keys["qualification_required_selected_objective_domains"] == "drc,pex")
        #expect(keys["qualification_missing_selected_action_domains"] == "pex-extraction")
        #expect(keys["qualification_missing_selected_objective_domains"] == "pex")
        #expect(keys["qualification_underqualified_selected_objective_domains"] == "drc,pex")
        #expect(keys["history_run_count"] == "1")
        #expect(keys["history_cycle_count"] == "1")
        #expect(keys["history_accepted_count"] == "0")
        #expect(keys["history_objective_domain"] == "drc,cycles=1,accepted=0,not_accepted=1,acceptance_rate=0.0,rank_changes=0,score_deltas=0,actions=repair-action-1,action_domains=layout-edit")
        #expect(output.contains("qualification_gate=minimum-accepted-count,passed=false,observed=0,required=1"))
        #expect(output.contains("qualification_gate=minimum-feedback-rank-change-count,passed=false,observed=0,required=1"))
        #expect(output.contains("qualification_gate=required-selected-action-domains,passed=false,observed=1,required=2"))
        #expect(output.contains("qualification_gate=required-selected-objective-domains,passed=false,observed=1,required=2"))
        #expect(output.contains("qualification_gate=minimum-accepted-count-per-selected-objective-domain,passed=false,observed=0,required=1"))
        #expect(output.contains("recommendation=Failed gates: minimum-accepted-count,minimum-feedback-rank-change-count,minimum-feedback-score-delta-count,required-selected-action-domains,required-selected-objective-domains,minimum-accepted-count-per-selected-objective-domain"))
        #expect(output.contains("recommendation=Retain candidate-cycle evidence for selected action domains: pex-extraction."))
        #expect(output.contains("recommendation=Retain candidate-cycle evidence for selected objective domains: pex."))
        #expect(output.contains("recommendation=Retain accepted candidate-cycle evidence for selected objective domains: drc,pex."))
    }

    @Test("signoff repair cycle history qualification command reads retained summaries", .timeLimit(.minutes(1)))
    func signoffRepairCycleHistoryQualificationCommandReadsRetainedSummaries() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioSignoffRepairQualification-\(UUID().uuidString)")
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove temporary directory \(root.path(percentEncoded: false)): \(error)")
            }
        }
        let planningDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "run-1")
            .appending(path: "planning")
        try FileManager.default.createDirectory(at: planningDirectory, withIntermediateDirectories: true)
        let profileURL = root.appending(path: "history-qualification-profile.json")
        let profile = RunReviewSignoffRepairCandidateCycleHistoryQualificationService.Profile(
            profileID: "candidate-cycle-history-qualified",
            title: "Candidate cycle history qualified",
            description: "Requires retained accepted feedback-sensitive candidate-cycle evidence.",
            request: RunReviewSignoffRepairCandidateCycleHistoryQualificationService.Request(
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
        try encoder.encode(summary).write(
            to: planningDirectory.appending(path: "candidate-cycle-history-summary.json"),
            options: .atomic
        )

        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .qualifySignoffRepairCandidateCycles,
            projectRootPath: root.path(percentEncoded: false),
            signoffRepairHistoryQualificationProfilePath: profileURL.path(percentEncoded: false)
        ))

        #expect(result.signoffRepairCandidateCycleHistoryQualification?.passed == true)
        #expect(result.signoffRepairCandidateCycleHistoryQualification?.failedGateIDs.isEmpty == true)
        #expect(result.signoffRepairCandidateCycleHistoryQualification?.profileID == "candidate-cycle-history-qualified")
        #expect(result.signoffRepairCandidateCycleHistoryQualification?.profilePath == profileURL.path(percentEncoded: false))
        #expect(result.signoffRepairCandidateCycleHistoryQualification?.request.minimumAcceptedCount == 1)
        #expect(
            result.signoffRepairCandidateCycleHistoryQualification?
                .request.minimumAcceptedCountPerSelectedObjectiveDomain == 1
        )
        #expect(
            result.signoffRepairCandidateCycleHistoryQualification?.request.requiredSelectedActionDomainIDs
                == ["layout-edit"]
        )
        #expect(
            result.signoffRepairCandidateCycleHistoryQualification?.request.requiredSelectedObjectiveDomainIDs
                == ["drc"]
        )
        #expect(
            result.signoffRepairCandidateCycleHistoryQualification?.missingSelectedActionDomainIDs.isEmpty == true
        )
        #expect(
            result.signoffRepairCandidateCycleHistoryQualification?.missingSelectedObjectiveDomainIDs.isEmpty == true
        )
        #expect(
            result.signoffRepairCandidateCycleHistoryQualification?
                .underqualifiedSelectedObjectiveDomainIDs.isEmpty == true
        )
        #expect(result.signoffRepairCandidateCycleHistoryIndex?.runCount == 1)
        #expect(result.signoffRepairCandidateCycleHistoryIndex?.selectedActionDomainIDs == ["layout-edit"])
        #expect(result.signoffRepairCandidateCycleHistoryIndex?.selectedObjectiveDomainIDs == ["drc"])
        #expect(result.signoffRepairCandidateCycleHistoryIndex?.objectiveDomainSummaries.first?.domainID == "drc")
        #expect(result.signoffRepairCandidateCycleHistoryIndex?.objectiveDomainSummaries.first?.acceptedCount == 1)
        #expect(result.signoffRepairCandidateCycleHistoryIndex?.feedbackRankChangeCount == 1)
        #expect(result.signoffRepairCandidateCycleHistoryIndex?.feedbackScoreDeltaCount == 1)

        let qualificationPath = try #require(result.signoffRepairCandidateCycleHistoryQualificationPath)
        #expect(FileManager.default.fileExists(atPath: qualificationPath))
        let persistedReport = try JSONDecoder().decode(
            RunReviewSignoffRepairCandidateCycleHistoryQualificationService.Report.self,
            from: Data(contentsOf: URL(filePath: qualificationPath))
        )
        #expect(persistedReport == result.signoffRepairCandidateCycleHistoryQualification)
        let qualificationArtifact = try #require(result.signoffRepairCandidateCycleHistoryQualificationArtifact)
        #expect(qualificationArtifact.artifactID == RunReviewSignoffRepairCandidateCycleHistoryQualificationService.reportArtifactID)
        #expect(qualificationArtifact.path == ".xcircuite/retained/signoff-repair-cycle-history-qualification.json")
        #expect(qualificationArtifact.sha256?.isEmpty == false)
        #expect((qualificationArtifact.byteCount ?? 0) > 0)

        let manifest = try XcircuitePackageStore().loadManifest(forProjectAt: root)
        #expect(manifest.files.contains { file in
            file.artifactID == RunReviewSignoffRepairCandidateCycleHistoryQualificationService.reportArtifactID
                && file.path == qualificationArtifact.path
                && file.sha256 == qualificationArtifact.sha256
                && file.byteCount == qualificationArtifact.byteCount
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

    @Test("select-failure-command arguments construct the failure command selection command", .timeLimit(.minutes(1)))
    func selectFailureCommandArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--select-failure-command",
            "--failure-envelope", "/tmp/flow-runner-failure.json",
            "--command-id", "circuit-studio-flow-runner.review-round-trip",
            "--reviewer", "agent-1",
            "--json",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .selectFailureSuggestedCommand)
        #expect(options.outputFormat == .json)
        #expect(command.kind == .selectFailureSuggestedCommand)
        #expect(command.failureEnvelopePath == "/tmp/flow-runner-failure.json")
        #expect(command.suggestedCommandID == "circuit-studio-flow-runner.review-round-trip")
        #expect(command.approvalReviewer == "agent-1")
    }

    @Test("run-selected-suggested-command arguments construct the selected command dispatcher", .timeLimit(.minutes(1)))
    func runSelectedSuggestedCommandArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--run-selected-suggested-command",
            "--output", "/tmp/flow-output",
            "--run-id", "run-1",
            "--command-id", "circuit-studio-flow-runner.review-round-trip",
            "--json",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .runSelectedSuggestedCommand)
        #expect(options.outputFormat == .json)
        #expect(command.kind == .runSelectedSuggestedCommand)
        #expect(command.projectRootPath == "/tmp/flow-output")
        #expect(command.runID == "run-1")
        #expect(command.suggestedCommandID == "circuit-studio-flow-runner.review-round-trip")
    }

    @Test("select-failure-command output records action log and selected command", .timeLimit(.minutes(1)))
    func selectFailureCommandOutputIncludesActionLedger() {
        let result = DesignFlowCommandResult(
            kind: .selectFailureSuggestedCommand,
            runID: "run-1",
            projectRootPath: "/tmp/flow-output",
            manifestPath: "/tmp/flow-output/.xcircuite/flow-runs/run-1/round-trip-manifest.json",
            actionLogPath: "/tmp/flow-output/.xcircuite/flow-runs/run-1/actions.jsonl",
            selectedSuggestedCommand: XcircuiteSuggestedCommandSelection(
                actionRecordID: "round-trip-suggested-command-selection-1",
                runID: "run-1",
                actor: XcircuiteRunActionActor(kind: .human, identifier: "agent-1"),
                status: .succeeded,
                selectedAt: Date(timeIntervalSince1970: 1_700_000_000),
                nextActionID: "review-flow-runner-failure",
                nextActionKind: "reviewFlowRunnerFailure",
                commandID: "circuit-studio-flow-runner.review-round-trip",
                readiness: "ready",
                executable: "swift",
                arguments: ["run", "--quiet", "circuit-studio-flow-runner", "--review-round-trip"],
                reason: "Load the failed run review."
            ),
            message: "round-trip-suggested-command-selection-1"
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["suggested_command_selection"] == "recorded")
        #expect(keys["run_id"] == "run-1")
        #expect(keys["manifest"] == "/tmp/flow-output/.xcircuite/flow-runs/run-1/round-trip-manifest.json")
        #expect(keys["actions"] == "/tmp/flow-output/.xcircuite/flow-runs/run-1/actions.jsonl")
        #expect(keys["action_id"] == "round-trip-suggested-command-selection-1")
        #expect(keys["command_id"] == "circuit-studio-flow-runner.review-round-trip")
        #expect(keys["readiness"] == "ready")
        #expect(keys["executable"] == "swift")
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

    @Test("signoff repair planning arguments construct the planning command", .timeLimit(.minutes(1)))
    func signoffRepairPlanningArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--formulate-signoff-repair-planning",
            "--output", "/tmp/flow-output",
            "--run-id", "run-1",
            "--reviewer", "agent-1",
            "--actor-kind", "agent",
            "--approval-note", "Plan DRC and LVS repair.",
            "--drc-repair-hints", ".xcircuite/runs/run-1/stages/001/raw/drc-repair-hints.json",
            "--lvs-repair-hints", ".xcircuite/runs/run-1/stages/001/raw/lvs-repair-hints.json",
            "--formulation-id", "signoff-repair-formulation-run-1",
            "--intent-id", "repair-signoff-run-1",
            "--intent", "Repair signoff diagnostics.",
            "--problem-id", "signoff-repair-problem-run-1",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .formulateSignoffRepairPlanningProblem)
        #expect(command.kind == .formulateSignoffRepairPlanningProblem)
        #expect(command.projectRootPath == "/tmp/flow-output")
        #expect(command.runID == "run-1")
        #expect(command.approvalReviewer == "agent-1")
        #expect(command.actionActorKind == .agent)
        #expect(command.approvalNote == "Plan DRC and LVS repair.")
        #expect(command.drcRepairHintPath == ".xcircuite/runs/run-1/stages/001/raw/drc-repair-hints.json")
        #expect(command.lvsRepairHintPath == ".xcircuite/runs/run-1/stages/001/raw/lvs-repair-hints.json")
        #expect(command.planningFormulationID == "signoff-repair-formulation-run-1")
        #expect(command.planningIntentID == "repair-signoff-run-1")
        #expect(command.planningIntent == "Repair signoff diagnostics.")
        #expect(command.planningProblemID == "signoff-repair-problem-run-1")
    }

    @Test("signoff repair candidate cycle arguments construct the dispatch command", .timeLimit(.minutes(1)))
    func signoffRepairCandidateCycleArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--run-signoff-repair-candidate-cycle",
            "--output", "/tmp/flow-output",
            "--run-id", "run-1",
            "--reviewer", "agent-1",
            "--actor-kind", "agent",
            "--approval-note", "Dispatch signoff repair.",
            "--drc-repair-hints", ".xcircuite/runs/run-1/stages/001/raw/drc-repair-hints.json",
            "--candidate-strategy", "first-ready-action-per-objective",
            "--candidate-verification-mode", "post-execution",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .runSignoffRepairCandidateCycle)
        #expect(command.kind == .runSignoffRepairCandidateCycle)
        #expect(command.projectRootPath == "/tmp/flow-output")
        #expect(command.runID == "run-1")
        #expect(command.approvalReviewer == "agent-1")
        #expect(command.actionActorKind == .agent)
        #expect(command.approvalNote == "Dispatch signoff repair.")
        #expect(command.drcRepairHintPath == ".xcircuite/runs/run-1/stages/001/raw/drc-repair-hints.json")
        #expect(command.candidateStrategy == "first-ready-action-per-objective")
        #expect(command.candidateVerificationMode == "post-execution")
    }

    @Test("signoff repair planning output exposes planner artifacts", .timeLimit(.minutes(1)))
    func signoffRepairPlanningOutputIncludesPlannerArtifacts() {
        let actionRecord = XcircuiteRunActionRecord(
            actionID: "signoff-repair-planning-1",
            runID: "run-1",
            actor: XcircuiteRunActionActor(kind: .agent, identifier: "agent-1"),
            actionKind: "review.formulateSignoffRepairPlanningProblem",
            status: .succeeded
        )
        let planningResult = RunReviewSignoffRepairPlanningResult(
            runID: "run-1",
            formulationID: "signoff-repair-formulation-run-1",
            problemID: "signoff-repair-problem-run-1",
            drcRepairHintPath: ".xcircuite/runs/run-1/stages/001/raw/drc-repair-hints.json",
            lvsRepairHintPath: ".xcircuite/runs/run-1/stages/001/raw/lvs-repair-hints.json",
            actionDomainArtifact: XcircuiteFileReference(
                artifactID: "planning-action-domain-snapshot",
                path: ".xcircuite/runs/run-1/planning/action-domain-snapshot.json",
                kind: .other,
                format: .json
            ),
            repairFormulationArtifact: XcircuiteFileReference(
                artifactID: "planning-repair-plan-formulation",
                path: ".xcircuite/runs/run-1/planning/repair-formulation.json",
                kind: .other,
                format: .json
            ),
            planningProblemArtifact: XcircuiteFileReference(
                artifactID: "planning-problem",
                path: ".xcircuite/runs/run-1/planning/problem.json",
                kind: .other,
                format: .json
            ),
            sourceReports: [],
            actionRecord: actionRecord
        )
        let result = DesignFlowCommandResult(
            kind: .formulateSignoffRepairPlanningProblem,
            runID: "run-1",
            projectRootPath: "/tmp/flow-output",
            actionLogPath: "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl",
            signoffRepairPlanningResult: planningResult,
            actionDomainPath: "/tmp/flow-output/.xcircuite/runs/run-1/planning/action-domain-snapshot.json",
            repairFormulationPath: "/tmp/flow-output/.xcircuite/runs/run-1/planning/repair-formulation.json",
            planningProblemPath: "/tmp/flow-output/.xcircuite/runs/run-1/planning/problem.json",
            message: "signoff-repair-planning-1"
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["signoff_repair_planning"] == "generated")
        #expect(keys["run_id"] == "run-1")
        #expect(keys["project_root"] == "/tmp/flow-output")
        #expect(keys["actions"] == "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl")
        #expect(keys["action_id"] == "signoff-repair-planning-1")
        #expect(keys["formulation_id"] == "signoff-repair-formulation-run-1")
        #expect(keys["problem_id"] == "signoff-repair-problem-run-1")
        #expect(keys["action_domain"] == "/tmp/flow-output/.xcircuite/runs/run-1/planning/action-domain-snapshot.json")
        #expect(keys["repair_formulation"] == "/tmp/flow-output/.xcircuite/runs/run-1/planning/repair-formulation.json")
        #expect(keys["planning_problem"] == "/tmp/flow-output/.xcircuite/runs/run-1/planning/problem.json")
        #expect(keys["drc_repair_hints"] == ".xcircuite/runs/run-1/stages/001/raw/drc-repair-hints.json")
        #expect(keys["lvs_repair_hints"] == ".xcircuite/runs/run-1/stages/001/raw/lvs-repair-hints.json")
    }

    @Test("signoff repair candidate cycle output exposes candidate artifacts", .timeLimit(.minutes(1)))
    func signoffRepairCandidateCycleOutputIncludesCandidateArtifacts() {
        let actionRecord = XcircuiteRunActionRecord(
            actionID: "signoff-repair-planning-1",
            runID: "run-1",
            actor: XcircuiteRunActionActor(kind: .agent, identifier: "agent-1"),
            actionKind: "review.formulateSignoffRepairPlanningProblem",
            status: .succeeded
        )
        let planningResult = RunReviewSignoffRepairPlanningResult(
            runID: "run-1",
            formulationID: "signoff-repair-formulation-run-1",
            problemID: "signoff-repair-problem-run-1",
            drcRepairHintPath: ".xcircuite/runs/run-1/stages/001/raw/drc-repair-hints.json",
            lvsRepairHintPath: nil,
            actionDomainArtifact: XcircuiteFileReference(
                artifactID: "planning-action-domain-snapshot",
                path: ".xcircuite/runs/run-1/planning/action-domain-snapshot.json",
                kind: .other,
                format: .json
            ),
            repairFormulationArtifact: XcircuiteFileReference(
                artifactID: "planning-repair-plan-formulation",
                path: ".xcircuite/runs/run-1/planning/repair-formulation.json",
                kind: .other,
                format: .json
            ),
            planningProblemArtifact: XcircuiteFileReference(
                artifactID: "planning-problem",
                path: ".xcircuite/runs/run-1/planning/problem.json",
                kind: .other,
                format: .json
            ),
            sourceReports: [],
            actionRecord: actionRecord
        )
        let generation = XcircuiteCandidatePlanGenerationResult(
            status: "generated",
            runID: "run-1",
            problemID: "signoff-repair-problem-run-1",
            planID: "candidate-plan-1",
            executionReadiness: "ready",
            problemPath: ".xcircuite/runs/run-1/planning/problem.json",
            candidatePlanArtifact: XcircuiteFileReference(
                artifactID: "planning-candidate-plan",
                path: ".xcircuite/runs/run-1/planning/candidate-plan.json",
                kind: .other,
                format: .json
            ),
            symbolicPlannerTrace: XcircuiteSymbolicPlannerTrace(
                runID: "run-1",
                problemID: "signoff-repair-problem-run-1",
                strategy: "first-ready-action-per-objective",
                problemPath: ".xcircuite/runs/run-1/planning/problem.json",
                rejectedPlansPath: ".xcircuite/runs/run-1/planning/rejected-plans.jsonl",
                rejectedPlanFeedbackRecordCount: 2,
                globalRejectedPlanFeedbackCount: 1,
                generatedPlanID: "candidate-plan-1",
                selectedActionIDs: ["repair-action-1"],
                unresolvedObjectiveIDs: [],
                objectiveTraces: [
                    XcircuiteSymbolicPlannerObjectiveTrace(
                        objectiveID: "repair-objective-1",
                        selectedActionID: "repair-action-1",
                        candidateActions: [
                            XcircuiteSymbolicPlannerActionTrace(
                                rank: 1,
                                actionID: "repair-action-1",
                                domainID: "layout-edit",
                                operationID: "layout.add-label",
                                maturity: "implemented",
                                score: 12,
                                scoreBeforeRejectedFeedback: 12,
                                rejectedFeedbackScoreDelta: 0,
                                rankBeforeRejectedFeedback: 2,
                                rejectedFeedbackRankDelta: -1,
                                scoreComponents: [
                                    XcircuiteSymbolicPlannerScoreComponent(
                                        termID: "goal.coverage",
                                        contribution: 12,
                                        reason: "Action covers the repair objective."
                                    ),
                                ],
                                requiredInputRefs: [],
                                missingInputRefs: [],
                                verificationGates: ["native-lvs"],
                                actionDomainSupported: true,
                                operationSupported: true,
                                selected: true,
                                blockedReasons: [],
                                reason: "Selected by feedback-aware ranking."
                            ),
                            XcircuiteSymbolicPlannerActionTrace(
                                rank: 2,
                                actionID: "repair-action-0",
                                domainID: "layout-edit",
                                operationID: "layout.resize-shape",
                                maturity: "implemented",
                                score: 4,
                                scoreBeforeRejectedFeedback: 10,
                                rejectedFeedbackScoreDelta: -6,
                                rankBeforeRejectedFeedback: 1,
                                rejectedFeedbackRankDelta: 1,
                                scoreComponents: [
                                    XcircuiteSymbolicPlannerScoreComponent(
                                        termID: "goal.coverage",
                                        contribution: 10,
                                        reason: "Action covers the repair objective."
                                    ),
                                    XcircuiteSymbolicPlannerScoreComponent(
                                        termID: "feedback.global.failed-gate",
                                        contribution: -6,
                                        reason: "Rejected feedback matches native DRC."
                                    ),
                                ],
                                requiredInputRefs: [],
                                missingInputRefs: [],
                                verificationGates: ["native-drc"],
                                actionDomainSupported: true,
                                operationSupported: true,
                                selected: false,
                                blockedReasons: [],
                                reason: "Penalized by rejected feedback."
                            ),
                        ]
                    ),
                ]
            )
        )
        let execution = XcircuiteCandidatePlanExecutionResult(
            status: "executed",
            runID: "run-1",
            problemID: "signoff-repair-problem-run-1",
            planID: "candidate-plan-1",
            candidatePlanPath: ".xcircuite/runs/run-1/planning/candidate-plan.json",
            planExecutionArtifact: XcircuiteFileReference(
                artifactID: "planning-plan-execution",
                path: ".xcircuite/runs/run-1/planning/plan-execution.json",
                kind: .other,
                format: .json
            ),
            designDiffArtifact: XcircuiteFileReference(
                artifactID: "design-diff",
                path: ".xcircuite/runs/run-1/design-diff.json",
                kind: .other,
                format: .json
            ),
            producedArtifacts: [],
            nextActions: []
        )
        let verification = XcircuiteCandidatePlanVerificationResult(
            status: "accepted",
            runID: "run-1",
            problemID: "signoff-repair-problem-run-1",
            planID: "candidate-plan-1",
            accepted: true,
            candidatePlanPath: ".xcircuite/runs/run-1/planning/candidate-plan.json",
            planVerificationArtifact: XcircuiteFileReference(
                artifactID: "planning-plan-verification",
                path: ".xcircuite/runs/run-1/planning/plan-verification.json",
                kind: .other,
                format: .json
            ),
            nextActions: []
        )
        let cycleRecord = XcircuiteRunActionRecord(
            actionID: "signoff-repair-candidate-cycle-1",
            runID: "run-1",
            actor: XcircuiteRunActionActor(kind: .agent, identifier: "agent-1"),
            actionKind: "review.runSignoffRepairCandidateCycle",
            status: .succeeded
        )
        let cycleResult = RunReviewSignoffRepairCandidateCycleResult(
            runID: "run-1",
            cycleIndex: 3,
            strategy: "first-ready-action-per-objective",
            verificationMode: "post-execution",
            planningResult: planningResult,
            candidateGeneration: generation,
            candidateExecution: execution,
            candidateVerification: verification,
            cycleActionRecord: cycleRecord
        )
        let cycleHistorySummary = RunReviewSignoffRepairCandidateCycleHistorySummary(cycles: [
            RunReviewSignoffRepairCandidateCycleHistoryItem(
                actionID: "signoff-repair-candidate-cycle-0",
                cycleIndex: 2,
                status: .blocked,
                planID: "candidate-plan-0",
                generationStatus: "generated",
                executionStatus: "executed",
                verificationStatus: "rejected",
                accepted: false,
                rejectedPlansPath: ".xcircuite/runs/run-1/planning/rejected-plans.jsonl",
                rejectedPlanFeedbackRecordCount: 1,
                globalRejectedPlanFeedbackCount: 1,
                selectedActionIDs: ["repair-action-0"],
                selectedActionDomainIDs: ["lvs-signoff"],
                selectedObjectiveDomainIDs: ["lvs"],
                feedbackPenalizedActionIDs: [],
                feedbackRankChanges: [],
                feedbackScoreDeltas: [],
                candidatePlanArtifact: nil,
                planExecutionArtifact: nil,
                planVerificationArtifact: nil,
                rejectedPlansArtifact: nil,
                designDiffArtifact: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            RunReviewSignoffRepairCandidateCycleHistoryItem(
                actionID: "signoff-repair-candidate-cycle-1",
                cycleIndex: 3,
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
                feedbackRankChanges: [
                    "repair-action-1:2->1",
                    "repair-action-0:1->2",
                ],
                feedbackScoreDeltas: ["repair-action-0:-6"],
                candidatePlanArtifact: nil,
                planExecutionArtifact: nil,
                planVerificationArtifact: nil,
                rejectedPlansArtifact: nil,
                designDiffArtifact: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_001)
            ),
        ])
        let result = DesignFlowCommandResult(
            kind: .runSignoffRepairCandidateCycle,
            runID: "run-1",
            projectRootPath: "/tmp/flow-output",
            actionLogPath: "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl",
            designDiffPath: "/tmp/flow-output/.xcircuite/runs/run-1/design-diff.json",
            signoffRepairPlanningResult: planningResult,
            signoffRepairCandidateCycleResult: cycleResult,
            signoffRepairCandidateCycleHistorySummary: cycleHistorySummary,
            actionDomainPath: "/tmp/flow-output/.xcircuite/runs/run-1/planning/action-domain-snapshot.json",
            repairFormulationPath: "/tmp/flow-output/.xcircuite/runs/run-1/planning/repair-formulation.json",
            planningProblemPath: "/tmp/flow-output/.xcircuite/runs/run-1/planning/problem.json",
            candidatePlanPath: "/tmp/flow-output/.xcircuite/runs/run-1/planning/candidate-plan.json",
            planExecutionPath: "/tmp/flow-output/.xcircuite/runs/run-1/planning/plan-execution.json",
            planVerificationPath: "/tmp/flow-output/.xcircuite/runs/run-1/planning/plan-verification.json",
            candidateCycleHistorySummaryPath: "/tmp/flow-output/.xcircuite/runs/run-1/planning/candidate-cycle-history-summary.json",
            candidateAccepted: true,
            message: "signoff-repair-candidate-cycle-1"
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["signoff_repair_candidate_cycle"] == "accepted")
        #expect(keys["cycle_action_id"] == "signoff-repair-candidate-cycle-1")
        #expect(keys["planning_action_id"] == "signoff-repair-planning-1")
        #expect(keys["cycle_index"] == "3")
        #expect(keys["strategy"] == "first-ready-action-per-objective")
        #expect(keys["verification_mode"] == "post-execution")
        #expect(keys["generation_status"] == "generated")
        #expect(keys["execution_status"] == "executed")
        #expect(keys["verification_status"] == "accepted")
        #expect(keys["accepted"] == "true")
        #expect(keys["feedback_rejected_plans"] == ".xcircuite/runs/run-1/planning/rejected-plans.jsonl")
        #expect(keys["rejected_feedback_count"] == "2")
        #expect(keys["global_rejected_feedback_count"] == "1")
        #expect(keys["selected_actions"] == "repair-action-1")
        #expect(keys["selected_action_domains"] == "layout-edit")
        #expect(keys["feedback_penalized_actions"] == "repair-action-0")
        #expect(keys["feedback_penalty_terms"] == "repair-action-0:feedback.global.failed-gate")
        #expect(keys["feedback_rank_changes"] == "repair-action-1:2->1,repair-action-0:1->2")
        #expect(keys["feedback_score_deltas"] == "repair-action-0:-6")
        #expect(keys["cycle_history_count"] == "2")
        #expect(keys["cycle_history_accepted_count"] == "1")
        #expect(keys["cycle_history_not_accepted_count"] == "1")
        #expect(keys["cycle_history_latest_index"] == "3")
        #expect(keys["cycle_history_latest_accepted"] == "true")
        #expect(keys["cycle_history_consumed_rejected_feedback_count"] == "3")
        #expect(keys["cycle_history_max_global_rejected_feedback_count"] == "3")
        #expect(keys["cycle_history_selected_actions"] == "repair-action-0,repair-action-1")
        #expect(keys["cycle_history_selected_action_domains"] == "lvs-signoff,layout-edit")
        #expect(keys["cycle_history_selected_objective_domains"] == "lvs,drc")
        #expect(output.contains("cycle_history_objective_domain=lvs,cycles=1,accepted=0,not_accepted=1,acceptance_rate=0.0,rank_changes=0,score_deltas=0,actions=repair-action-0,action_domains=lvs-signoff"))
        #expect(output.contains("cycle_history_objective_domain=drc,cycles=1,accepted=1,not_accepted=0,acceptance_rate=1.0,rank_changes=2,score_deltas=1,actions=repair-action-1,action_domains=layout-edit"))
        #expect(keys["cycle_history_feedback_penalized_actions"] == "repair-action-0")
        #expect(keys["cycle_history_feedback_rank_change_count"] == "2")
        #expect(keys["cycle_history_feedback_rank_changed_actions"] == "repair-action-1,repair-action-0")
        #expect(keys["cycle_history_feedback_score_delta_count"] == "1")
        #expect(keys["cycle_history_feedback_score_delta_actions"] == "repair-action-0")
        #expect(keys["candidate_plan"] == "/tmp/flow-output/.xcircuite/runs/run-1/planning/candidate-plan.json")
        #expect(keys["plan_execution"] == "/tmp/flow-output/.xcircuite/runs/run-1/planning/plan-execution.json")
        #expect(keys["design_diff"] == "/tmp/flow-output/.xcircuite/runs/run-1/design-diff.json")
        #expect(keys["plan_verification"] == "/tmp/flow-output/.xcircuite/runs/run-1/planning/plan-verification.json")
        #expect(keys["cycle_history_summary"] == "/tmp/flow-output/.xcircuite/runs/run-1/planning/candidate-cycle-history-summary.json")
    }

    @Test("apply-waiver-edit-and-verify arguments construct the combined command", .timeLimit(.minutes(1)))
    func applyWaiverEditAndVerifyArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--apply-waiver-edit-and-verify",
            "--fixture", "voltage-divider",
            "--output", "/tmp/flow-output",
            "--run-id", "run-1",
            "--reviewer", "agent-1",
            "--approval-note", "Apply and verify waiver cleanup.",
            "--layout-document", "/tmp/layout.json",
            "--design-unit", "/tmp/design-unit.json",
            "--waiver-review", "drc-waiver:.xcircuite/runs/run-1/stages/001/raw/drc-summary.json",
            "--waiver-proposal", "remove-obsolete-drc-waiver",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .applyWaiverEditProposalAndRunPostVerification)
        #expect(command.kind == .applyWaiverEditProposalAndRunPostVerification)
        #expect(command.fixtureName == "voltage-divider")
        #expect(command.projectRootPath == "/tmp/flow-output")
        #expect(command.runID == "run-1")
        #expect(command.approvalReviewer == "agent-1")
        #expect(command.approvalNote == "Apply and verify waiver cleanup.")
        #expect(command.layoutDocumentPath == "/tmp/layout.json")
        #expect(command.designUnitPath == "/tmp/design-unit.json")
        #expect(command.waiverReviewID == "drc-waiver:.xcircuite/runs/run-1/stages/001/raw/drc-summary.json")
        #expect(command.waiverProposalID == "remove-obsolete-drc-waiver")
    }

    @Test("apply-waiver-edit-and-verify output records both action IDs", .timeLimit(.minutes(1)))
    func applyWaiverEditAndVerifyOutputIncludesBothActionIDs() {
        let result = DesignFlowCommandResult(
            kind: .applyWaiverEditProposalAndRunPostVerification,
            runID: "run-1",
            projectRootPath: "/tmp/flow-output",
            readyForPEX: true,
            actionLogPath: "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl",
            verificationReportPath: "/tmp/flow-output/.xcircuite/runs/run-1/reports/physical-verification.json",
            actionRecordIDs: [
                "waiver-edit-proposal-application-1",
                "waiver-edit-proposal-verification-1",
            ],
            message: "waiver-edit-proposal-verification-1"
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["waiver_edit"] == "applied")
        #expect(keys["waiver_edit_verification"] == "")
        #expect(keys["run_id"] == "run-1")
        #expect(keys["project_root"] == "/tmp/flow-output")
        #expect(keys["ready_for_pex"] == "true")
        #expect(keys["verification_report"] == "/tmp/flow-output/.xcircuite/runs/run-1/reports/physical-verification.json")
        #expect(keys["actions"] == "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl")
        #expect(keys["application_action_id"] == "waiver-edit-proposal-application-1")
        #expect(keys["verification_action_id"] == "waiver-edit-proposal-verification-1")
        #expect(keys["action_id"] == "waiver-edit-proposal-verification-1")
    }

    @Test("apply-waiver-edit-and-verify leaves verification_action_id empty when the ledger did not record one", .timeLimit(.minutes(1)))
    func applyWaiverEditAndVerifyOutputDoesNotInventVerificationActionID() {
        let result = DesignFlowCommandResult(
            kind: .applyWaiverEditProposalAndRunPostVerification,
            runID: "run-1",
            projectRootPath: "/tmp/flow-output",
            readyForPEX: false,
            actionLogPath: "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl",
            verificationReportPath: "/tmp/flow-output/.xcircuite/runs/run-1/reports/physical-verification.json",
            actionRecordIDs: [
                "waiver-edit-proposal-application-1",
            ],
            message: "waiver-edit-proposal-verification-1"
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["application_action_id"] == "waiver-edit-proposal-application-1")
        #expect(keys["verification_action_id"] == "")
        #expect(keys["action_id"] == "waiver-edit-proposal-verification-1")
    }

    @Test("apply-waiver-edit output prefers recorded action IDs over message fallback", .timeLimit(.minutes(1)))
    func applyWaiverEditOutputPrefersRecordedActionID() {
        let result = DesignFlowCommandResult(
            kind: .applyWaiverEditProposal,
            runID: "run-1",
            projectRootPath: "/tmp/flow-output",
            actionLogPath: "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl",
            actionRecordIDs: ["waiver-edit-proposal-application-1"]
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["action_id"] == "waiver-edit-proposal-application-1")
    }

    @Test("post-waiver-edit verification output prefers recorded action IDs over message fallback", .timeLimit(.minutes(1)))
    func postWaiverEditVerificationOutputPrefersRecordedActionID() {
        let result = DesignFlowCommandResult(
            kind: .runPostWaiverEditVerification,
            runID: "run-1",
            projectRootPath: "/tmp/flow-output",
            actionLogPath: "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl",
            actionRecordIDs: ["waiver-edit-proposal-verification-1"]
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["action_id"] == "waiver-edit-proposal-verification-1")
    }

    @Test("planning output prefers recorded action IDs over message fallback", .timeLimit(.minutes(1)))
    func planningOutputPrefersRecordedActionID() {
        let result = DesignFlowCommandResult(
            kind: .formulateSignoffRepairPlanningProblem,
            runID: "run-1",
            projectRootPath: "/tmp/flow-output",
            actionLogPath: "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl",
            actionRecordIDs: ["signoff-repair-planning-1"]
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["action_id"] == "signoff-repair-planning-1")
    }

    @Test("candidate-cycle output does not invent cycle_action_id when the cycle result is absent", .timeLimit(.minutes(1)))
    func candidateCycleOutputDoesNotInventCycleActionID() {
        let result = DesignFlowCommandResult(
            kind: .runSignoffRepairCandidateCycle,
            runID: "run-1",
            projectRootPath: "/tmp/flow-output",
            actionLogPath: "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl",
            message: "signoff-repair-candidate-cycle-1"
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["cycle_action_id"] == "")
        #expect(keys["action_id"] == nil || keys["action_id"] == "")
    }

    @Test("candidate-cycle output falls back to recorded action IDs when the cycle result is absent", .timeLimit(.minutes(1)))
    func candidateCycleOutputFallsBackToRecordedActionIDs() {
        let result = DesignFlowCommandResult(
            kind: .runSignoffRepairCandidateCycle,
            runID: "run-1",
            projectRootPath: "/tmp/flow-output",
            actionLogPath: "/tmp/flow-output/.xcircuite/runs/run-1/actions.jsonl",
            actionRecordIDs: [
                "signoff-repair-planning-1",
                "candidate-plan-1-execution",
                "candidate-plan-1-verification",
                "signoff-repair-candidate-cycle-1",
            ]
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["planning_action_id"] == "signoff-repair-planning-1")
        #expect(keys["cycle_action_id"] == "signoff-repair-candidate-cycle-1")
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
