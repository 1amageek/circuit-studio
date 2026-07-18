import CircuitSignoff
import Foundation

public struct FlowRunnerOutputContext: Sendable, Hashable {
    public let fixtureName: String
    public let usesImportedSignoff: Bool
    public let approveSignoff: Bool

    public init(
        fixtureName: String = DesignFlowFixtureLibrary.defaultFixtureName,
        usesImportedSignoff: Bool = false,
        approveSignoff: Bool = false
    ) {
        self.fixtureName = fixtureName
        self.usesImportedSignoff = usesImportedSignoff
        self.approveSignoff = approveSignoff
    }
}

public enum FlowRunnerKeyValueFormatter {
    public static func lines(
        for result: DesignFlowCommandResult,
        context: FlowRunnerOutputContext = FlowRunnerOutputContext()
    ) -> [String] {
        var lines: [String] = []
        switch result.kind {
        case .listFixtures:
            for fixtureName in result.fixtureNames {
                lines.append("fixture=\(fixtureName)")
            }
        case .generateFixtureNetlist:
            lines.append("netlist=generated")
            appendDesignOrFixture(result: result, context: context, to: &lines)
            appendNetlist(result.netlist, to: &lines)
        case .generateDesignNetlist:
            lines.append("netlist=generated")
            appendDesignOrFixture(result: result, context: context, to: &lines)
            appendNetlist(result.netlist, to: &lines)
        case .runFixtureSimulation:
            lines.append("simulation=\(result.simulationStatus ?? "")")
            appendDesignOrFixture(result: result, context: context, to: &lines)
            appendNetlist(result.netlist, to: &lines)
        case .runDesignSimulation:
            lines.append("simulation=\(result.simulationStatus ?? "")")
            appendDesignOrFixture(result: result, context: context, to: &lines)
            appendNetlist(result.netlist, to: &lines)
        case .runFixtureRoundTrip:
            appendRoundTrip(result: result, context: context, to: &lines)
        case .runDesignRoundTrip:
            appendRoundTrip(result: result, context: context, to: &lines)
        case .summarizeBottlenecks:
            let summary = result.bottleneckHistory
            lines.append("bottlenecks=summarized")
            lines.append("project_root=\(result.projectRootPath ?? "")")
            lines.append("run_count=\(summary?.runCount ?? 0)")
            lines.append("failed_run_count=\(summary?.failedRunCount ?? 0)")
            lines.append("most_frequent_failed_stage=\(summary?.mostFrequentFailedStageName ?? "")")
            lines.append("most_expensive_stage=\(summary?.mostExpensiveStageName ?? "")")
            for stageSummary in summary?.stageSummaries ?? [] {
                lines.append(
                    "stage=\(stageSummary.stageName),observed=\(stageSummary.observedCount),failed=\(stageSummary.failedCount),avg_seconds=\(stageSummary.averageDurationSeconds)"
                )
            }
            for recommendation in summary?.recommendations ?? [] {
                lines.append("recommendation=\(recommendation)")
            }
        case .summarizeSignoffRepairCandidateCycles:
            let summary = result.signoffRepairCandidateCycleHistoryIndex
            lines.append("signoff_repair_cycle_history=summarized")
            lines.append("project_root=\(result.projectRootPath ?? "")")
            appendSignoffRepairCandidateCycleHistory(summary, includeRecommendations: true, to: &lines)
        case .assessSignoffRepairCandidateCycles:
            let report = result.signoffRepairCandidateCycleHistoryAssessment
            let summary = report?.summary ?? result.signoffRepairCandidateCycleHistoryIndex
            lines.append("signoff_repair_cycle_history_assessment=\(report?.status.rawValue ?? "")")
            lines.append("project_root=\(result.projectRootPath ?? "")")
            lines.append("assessment_passed=\(report?.passed ?? false)")
            lines.append("assessment_report=\(result.signoffRepairCandidateCycleHistoryAssessmentPath ?? "")")
            lines.append(
                "assessment_report_sha256=\(result.signoffRepairCandidateCycleHistoryAssessmentArtifact?.digest.hexadecimalValue ?? "")"
            )
            lines.append(
                "assessment_report_bytes=\(result.signoffRepairCandidateCycleHistoryAssessmentArtifact?.byteCount ?? 0)"
            )
            lines.append("assessment_profile_id=\(report?.profileID ?? "")")
            lines.append("assessment_profile_title=\(report?.profileTitle ?? "")")
            lines.append("assessment_profile_path=\(report?.profilePath ?? "")")
            lines.append("assessment_failed_gates=\(report?.failedGateIDs.joined(separator: ",") ?? "")")
            if let request = report?.request {
                lines.append("assessment_min_history_runs=\(request.minimumRunCount)")
                lines.append("assessment_min_history_cycles=\(request.minimumCycleCount)")
                lines.append("assessment_min_history_accepted=\(request.minimumAcceptedCount)")
                lines.append(
                    "assessment_min_history_feedback_rank_changes=\(request.minimumFeedbackRankChangeCount)"
                )
                lines.append(
                    "assessment_min_history_feedback_score_deltas=\(request.minimumFeedbackScoreDeltaCount)"
                )
                lines.append(
                    "assessment_min_history_accepted_per_selected_objective_domain=\(request.minimumAcceptedCountPerSelectedObjectiveDomain)"
                )
                lines.append(
                    "assessment_required_selected_action_domains=\(request.requiredSelectedActionDomainIDs.joined(separator: ","))"
                )
                lines.append(
                    "assessment_required_selected_objective_domains=\(request.requiredSelectedObjectiveDomainIDs.joined(separator: ","))"
                )
            }
            lines.append(
                "assessment_missing_selected_action_domains=\(report?.missingSelectedActionDomainIDs.joined(separator: ",") ?? "")"
            )
            lines.append(
                "assessment_missing_selected_objective_domains=\(report?.missingSelectedObjectiveDomainIDs.joined(separator: ",") ?? "")"
            )
            lines.append(
                "assessment_below_threshold_selected_objective_domains=\(report?.belowThresholdSelectedObjectiveDomainIDs.joined(separator: ",") ?? "")"
            )
            appendSignoffRepairCandidateCycleHistory(summary, includeRecommendations: false, to: &lines)
            for gate in report?.gates ?? [] {
                lines.append(
                    "assessment_gate=\(gate.gateID),passed=\(gate.passed),observed=\(gate.observed),required=\(gate.required)"
                )
            }
            for recommendation in report?.recommendations ?? [] {
                lines.append("recommendation=\(recommendation)")
            }
        case .loadTechnologyPackage:
            lines.append("technology_package=loaded")
            lines.append("technology_package_id=\(result.technologyPackageID ?? "")")
            lines.append("technology_package_path=\(result.technologyPackagePath ?? "")")
            lines.append("diagnostic_count=\(result.validationDiagnostics?.count ?? 0)")
        case .runPEXExtraction:
            lines.append("pex_extraction=passed")
            lines.append("pex_manifest=\(result.pexManifestPath ?? "")")
            lines.append("pex_corner=\(result.pexCornerID ?? "")")
            lines.append("pex_elements=\(result.pexElementCount ?? 0)")
        case .inspectTimingModelProfiles:
            let inspection = result.timingModelProfileCatalogInspection
            lines.append("timing_model_profile_catalog=inspected")
            lines.append("timing_model_profile_catalog_status=\(inspection?.status.rawValue ?? "")")
            lines.append("timing_model_profile_catalog_id=\(result.timingModelProfileCatalogID ?? inspection?.catalogID ?? "")")
            lines.append("timing_model_profile_catalog_path=\(result.timingModelProfileCatalogPath ?? inspection?.catalogPath ?? "")")
            lines.append("timing_model_profile_selected_id=\(result.timingModelProfileID ?? "")")
            lines.append("timing_model_corner_id=\(result.timingModelCornerID ?? "")")
            lines.append("timing_model_profile_default_id=\(inspection?.defaultProfileID ?? "")")
            lines.append("timing_model_profile_count=\(inspection?.profileCount ?? 0)")
            lines.append("timing_model_profile_passed_count=\(inspection?.passedProfileCount ?? 0)")
            lines.append("timing_model_profile_failed_count=\(inspection?.failedProfileCount ?? 0)")
            lines.append("timing_model_profile_ids=\(inspection?.profiles.map(\.profileID).joined(separator: ",") ?? "")")
        case .buildTimingLibrary:
            lines.append("timing_library=generated")
            lines.append("run_id=\(result.runID ?? "")")
            lines.append("project_root=\(result.projectRootPath ?? "")")
            lines.append("timing_manifest=\(result.timingArtifactManifestPath ?? "")")
            lines.append("timing_library_artifact=\(result.timingLibraryPath ?? "")")
            lines.append("timing_model_profile_selection=\(result.timingModelProfileSelectionPath ?? "")")
            lines.append("timing_model_profile_id=\(result.timingModelProfileID ?? "")")
            lines.append("timing_model_profile_path=\(result.timingModelProfilePath ?? "")")
            lines.append("timing_model_profile_catalog_id=\(result.timingModelProfileCatalogID ?? "")")
            lines.append("timing_model_profile_catalog_path=\(result.timingModelProfileCatalogPath ?? "")")
            lines.append("timing_model_corner_id=\(result.timingModelCornerID ?? "")")
        case .applyDesignEdit:
            lines.append("design_edit=applied")
            lines.append("design=\(result.designName ?? "")")
            lines.append("design_spec=\(result.designSpecPath ?? "")")
            lines.append("actions=\(result.actionLogPath ?? "")")
            lines.append("design_diff=\(result.designDiffPath ?? "")")
        case .applyLayoutEdit:
            lines.append("layout_edit=applied")
            lines.append("layout_document=\(result.layoutDocumentPath ?? "")")
            lines.append("actions=\(result.actionLogPath ?? "")")
            lines.append("layout_diff=\(result.layoutDiffPath ?? "")")
        case .runLayoutTrust:
            lines.append("layout_trust=\(result.layoutTrustReport?.status.rawValue ?? "")")
            lines.append("layout_trust_passed=\(result.layoutTrustPassed ?? false)")
            lines.append("layout_trust_report=\(result.layoutTrustReportPath ?? "")")
            lines.append("owned_shapes=\(result.layoutTrustReport?.ownedShapeCount ?? 0)")
            lines.append("unowned_shapes=\(result.layoutTrustReport?.unownedShapeCount ?? 0)")
            lines.append("shorts=\(result.layoutTrustReport?.netAwareReport.shorts.count ?? 0)")
            lines.append("opens=\(result.layoutTrustReport?.netAwareReport.opens.count ?? 0)")
        case .runVerification:
            lines.append("verification=\(result.verificationReport?.status ?? "")")
            appendDesignOrFixture(result: result, context: context, to: &lines)
            lines.append("ready_for_pex=\(result.readyForPEX ?? false)")
            lines.append("layout_trust_passed=\(result.layoutTrustPassed ?? false)")
            lines.append("verification_report=\(result.verificationReportPath ?? "")")
            lines.append("layout_trust_report=\(result.layoutTrustReportPath ?? "")")
            lines.append("drc_passed=\(result.verificationReport?.drc.passed ?? false)")
            lines.append("drc_violations=\(result.verificationReport?.drc.violationCount ?? 0)")
            lines.append("lvs_passed=\(result.verificationReport?.lvs.passed ?? false)")
            lines.append("external_signoff=\(signoffSource(result: result, context: context))")
            lines.append("signoff_approved=\(result.verificationReport?.externalSignoff?.approved ?? false)")
            lines.append("signoff_approval_kind=\(result.verificationReport?.externalSignoff?.approvalKind?.rawValue ?? "")")
            lines.append("signoff_approved_by=\(result.verificationReport?.externalSignoff?.approvedBy ?? "")")
        case .approveGate:
            lines.append("stage_approval=\(result.approvalRecord?.verdict.rawValue ?? "")")
            lines.append("stage=\(result.approvalRecord?.stageID ?? "")")
            lines.append("reviewer=\(result.approvalRecord?.reviewer ?? "")")
            lines.append("run_id=\(result.approvalRecord?.runID ?? "")")
            lines.append("plan_artifact=\(result.approvalRecord?.evidence.plan.id.rawValue ?? "")")
            lines.append("stage_result_artifact=\(result.approvalRecord?.evidence.stageResult.id.rawValue ?? "")")
        case .reviewRoundTrip:
            appendRoundTripReview(result: result, to: &lines)
        case .selectFailureSuggestedAction:
            lines.append("suggested_action_selection=recorded")
            lines.append("run_id=\(result.runID ?? "")")
            lines.append("project_root=\(result.projectRootPath ?? "")")
            lines.append("manifest=\(result.manifestPath ?? "")")
            lines.append("actions=\(result.actionLogPath ?? "")")
            lines.append("action_id=\(firstActionRecordID(from: result) ?? result.message ?? "")")
            lines.append("suggested_action_id=\(result.selectedSuggestedAction?.action.id ?? "")")
            lines.append("readiness=\(result.selectedSuggestedAction?.action.readiness.rawValue ?? "")")
            lines.append("operation=\(result.selectedSuggestedAction.map { String(describing: $0.action.operation) } ?? "")")
        case .runSelectedSuggestedAction:
            lines.append("selected_suggested_action=dispatched")
            lines.append("run_id=\(result.runID ?? "")")
            lines.append("project_root=\(result.projectRootPath ?? "")")
            lines.append("suggested_action_id=\(result.selectedSuggestedAction?.action.id ?? "")")
        case .applyWaiverEditProposal:
            lines.append("waiver_edit=applied")
            lines.append("run_id=\(result.runID ?? "")")
            lines.append("project_root=\(result.projectRootPath ?? "")")
            lines.append("actions=\(result.actionLogPath ?? "")")
            lines.append("action_id=\(firstActionRecordID(from: result) ?? result.message ?? "")")
        case .runPostWaiverEditVerification:
            lines.append("waiver_edit_verification=\(result.verificationReport?.status ?? "")")
            lines.append("run_id=\(result.runID ?? "")")
            lines.append("project_root=\(result.projectRootPath ?? "")")
            lines.append("ready_for_pex=\(result.readyForPEX ?? false)")
            lines.append("verification_report=\(result.verificationReportPath ?? "")")
            lines.append("layout_trust_report=\(result.layoutTrustReportPath ?? "")")
            lines.append("drc_passed=\(result.verificationReport?.drc.passed ?? false)")
            lines.append("drc_violations=\(result.verificationReport?.drc.violationCount ?? 0)")
            lines.append("lvs_passed=\(result.verificationReport?.lvs.passed ?? false)")
            lines.append("actions=\(result.actionLogPath ?? "")")
            lines.append("action_id=\(firstActionRecordID(from: result) ?? result.message ?? "")")
        case .applyWaiverEditProposalAndRunPostVerification:
            lines.append("waiver_edit=applied")
            lines.append("waiver_edit_verification=\(result.verificationReport?.status ?? "")")
            lines.append("run_id=\(result.runID ?? "")")
            lines.append("project_root=\(result.projectRootPath ?? "")")
            lines.append("ready_for_pex=\(result.readyForPEX ?? false)")
            lines.append("verification_report=\(result.verificationReportPath ?? "")")
            lines.append("layout_trust_report=\(result.layoutTrustReportPath ?? "")")
            lines.append("drc_passed=\(result.verificationReport?.drc.passed ?? false)")
            lines.append("drc_violations=\(result.verificationReport?.drc.violationCount ?? 0)")
            lines.append("lvs_passed=\(result.verificationReport?.lvs.passed ?? false)")
            lines.append("actions=\(result.actionLogPath ?? "")")
            let actionRecordIDs = result.actionRecordIDs ?? []
            lines.append("application_action_id=\(actionRecordIDs.first ?? "")")
            lines.append("verification_action_id=\(actionRecordIDs.dropFirst().first ?? "")")
            lines.append("action_id=\(lastActionRecordID(from: result) ?? result.message ?? "")")
        case .formulateSignoffRepairPlanningProblem:
            lines.append("signoff_repair_planning=generated")
            lines.append("run_id=\(result.runID ?? "")")
            lines.append("project_root=\(result.projectRootPath ?? "")")
            lines.append("actions=\(result.actionLogPath ?? "")")
            lines.append("action_id=\(firstActionRecordID(from: result) ?? result.message ?? "")")
            lines.append("formulation_id=\(result.signoffRepairPlanningResult?.formulationID ?? "")")
            lines.append("problem_id=\(result.signoffRepairPlanningResult?.problemID ?? "")")
            lines.append("action_domain=\(result.actionDomainPath ?? "")")
            lines.append("repair_formulation=\(result.repairFormulationPath ?? "")")
            lines.append("planning_problem=\(result.planningProblemPath ?? "")")
            lines.append("drc_repair_hints=\(result.signoffRepairPlanningResult?.drcRepairHintPath ?? "")")
            lines.append("lvs_repair_hints=\(result.signoffRepairPlanningResult?.lvsRepairHintPath ?? "")")
            lines.append("source_report_count=\(result.signoffRepairPlanningResult?.sourceReports.count ?? 0)")
        case .runSignoffRepairCandidateCycle:
            let cycle = result.signoffRepairCandidateCycleResult
            lines.append("signoff_repair_candidate_cycle=\(cycle?.candidateVerification.status ?? "")")
            lines.append("run_id=\(result.runID ?? "")")
            lines.append("project_root=\(result.projectRootPath ?? "")")
            lines.append("actions=\(result.actionLogPath ?? "")")
            lines.append("cycle_action_id=\(cycle?.cycleActionRecord.actionID ?? actionRecordID(from: result, at: 3) ?? "")")
            lines.append("planning_action_id=\(cycle?.planningResult.actionRecord.actionID ?? actionRecordID(from: result, at: 0) ?? "")")
            lines.append("cycle_index=\(cycle?.cycleIndex ?? 0)")
            lines.append("strategy=\(cycle?.strategy ?? "")")
            lines.append("verification_mode=\(cycle?.verificationMode ?? "")")
            lines.append("formulation_id=\(cycle?.planningResult.formulationID ?? "")")
            lines.append("problem_id=\(cycle?.planningResult.problemID ?? "")")
            lines.append("plan_id=\(cycle?.candidateGeneration.planID ?? "")")
            lines.append("generation_status=\(cycle?.candidateGeneration.status ?? "")")
            lines.append("execution_status=\(cycle?.candidateExecution.status ?? "")")
            lines.append("verification_status=\(cycle?.candidateVerification.status ?? "")")
            lines.append("accepted=\(result.candidateAccepted ?? false)")
            lines.append("feedback_rejected_plans=\(cycle?.candidateGeneration.symbolicPlannerTrace?.rejectedPlansPath ?? "")")
            lines.append(
                "rejected_feedback_count=\(cycle?.candidateGeneration.symbolicPlannerTrace?.rejectedPlanFeedbackRecordCount ?? 0)"
            )
            lines.append(
                "global_rejected_feedback_count=\(cycle?.candidateGeneration.symbolicPlannerTrace?.globalRejectedPlanFeedbackCount ?? 0)"
            )
            lines.append(
                "selected_actions=\(cycle?.candidateGeneration.symbolicPlannerTrace?.selectedActionIDs.joined(separator: ",") ?? "")"
            )
            lines.append(
                "selected_action_domains=\(selectedActionDomainIDs(from: cycle).joined(separator: ","))"
            )
            lines.append(
                "feedback_penalized_actions=\(feedbackPenalizedActionIDs(from: cycle).joined(separator: ","))"
            )
            lines.append(
                "feedback_penalty_terms=\(feedbackPenaltyTerms(from: cycle).joined(separator: ","))"
            )
            lines.append(
                "feedback_rank_changes=\(feedbackRankChanges(from: cycle).joined(separator: ","))"
            )
            lines.append(
                "feedback_score_deltas=\(feedbackScoreDeltas(from: cycle).joined(separator: ","))"
            )
            appendSignoffRepairCandidateCycleHistorySummary(
                result.signoffRepairCandidateCycleHistorySummary,
                to: &lines
            )
            lines.append("action_domain=\(result.actionDomainPath ?? "")")
            lines.append("repair_formulation=\(result.repairFormulationPath ?? "")")
            lines.append("planning_problem=\(result.planningProblemPath ?? "")")
            lines.append("candidate_plan=\(result.candidatePlanPath ?? "")")
            lines.append("plan_execution=\(result.planExecutionPath ?? "")")
            lines.append("design_diff=\(result.designDiffPath ?? "")")
            lines.append("plan_verification=\(result.planVerificationPath ?? "")")
            lines.append("rejected_plans=\(result.rejectedPlansPath ?? "")")
            lines.append("cycle_history_summary=\(result.candidateCycleHistorySummaryPath ?? "")")
        case .runGoalLayoutAgent:
            lines.append("goal_layout_agent=\(result.message ?? "")")
            lines.append("design_name=\(result.designName ?? "")")
            lines.append("run_id=\(result.runID ?? "")")
            lines.append("project_root=\(result.projectRootPath ?? "")")
            lines.append("technology_package_id=\(result.technologyPackageID ?? "")")
            lines.append("closed=\(result.goalAgentClosed ?? false)")
            lines.append("evidence=\(result.goalAgentEvidencePath ?? "")")
            lines.append("gds=\(result.exportedLayoutPath ?? "")")
        case .scaffoldDesignSpec:
            lines.append("design_spec_scaffold=\(result.message ?? "")")
            lines.append("design=\(result.designName ?? "")")
            lines.append("design_spec=\(result.designSpecPath ?? "")")
        }
        return sanitizedKeyValueLines(lines)
    }

    private static func sanitizedKeyValueLines(_ lines: [String]) -> [String] {
        var sanitized: [String] = []
        var inRawBlock = false
        sanitized.reserveCapacity(lines.count)

        for line in lines {
            if line == "netlist_begin" {
                inRawBlock = true
                sanitized.append(line)
                continue
            }
            if line == "netlist_end" {
                inRawBlock = false
                sanitized.append(line)
                continue
            }
            if inRawBlock {
                sanitized.append(line)
                continue
            }
            sanitized.append(sanitizedKeyValueLine(line))
        }
        return sanitized
    }

    private static func sanitizedKeyValueLine(_ line: String) -> String {
        guard let separator = line.firstIndex(of: "=") else {
            return escapedScalarValue(line)
        }
        let key = String(line[..<separator])
        let value = String(line[line.index(after: separator)...])
        return "\(key)=\(escapedScalarValue(value))"
    }

    private static func escapedScalarValue(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "\\":
                result += "\\\\"
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            default:
                result.append(character)
            }
        }
        return result
    }

    private static func appendSignoffRepairCandidateCycleHistorySummary(
        _ summary: RunReviewSignoffRepairCandidateCycleHistorySummary?,
        to lines: inout [String]
    ) {
        lines.append("cycle_history_count=\(summary?.cycleCount ?? 0)")
        lines.append("cycle_history_accepted_count=\(summary?.acceptedCount ?? 0)")
        lines.append("cycle_history_not_accepted_count=\(summary?.notAcceptedCount ?? 0)")
        lines.append("cycle_history_latest_index=\(summary?.latestCycleIndex ?? 0)")
        lines.append("cycle_history_latest_accepted=\(summary?.latestAccepted ?? false)")
        lines.append(
            "cycle_history_consumed_rejected_feedback_count=\(summary?.consumedRejectedPlanFeedbackRecordCount ?? 0)"
        )
        lines.append(
            "cycle_history_max_global_rejected_feedback_count=\(summary?.maximumGlobalRejectedPlanFeedbackCount ?? 0)"
        )
        lines.append(
            "cycle_history_selected_actions=\(summary?.selectedActionIDs.joined(separator: ",") ?? "")"
        )
        lines.append(
            "cycle_history_selected_action_domains=\(summary?.selectedActionDomainIDs.joined(separator: ",") ?? "")"
        )
        lines.append(
            "cycle_history_selected_objective_domains=\(summary?.selectedObjectiveDomainIDs.joined(separator: ",") ?? "")"
        )
        lines.append(
            "cycle_history_feedback_penalized_actions=\(summary?.feedbackPenalizedActionIDs.joined(separator: ",") ?? "")"
        )
        lines.append(
            "cycle_history_feedback_rank_change_count=\(summary?.feedbackRankChangeCount ?? 0)"
        )
        lines.append(
            "cycle_history_feedback_rank_changed_actions=\(summary?.feedbackRankChangedActionIDs.joined(separator: ",") ?? "")"
        )
        lines.append(
            "cycle_history_feedback_score_delta_count=\(summary?.feedbackScoreDeltaCount ?? 0)"
        )
        lines.append(
            "cycle_history_feedback_score_delta_actions=\(summary?.feedbackScoreDeltaActionIDs.joined(separator: ",") ?? "")"
        )
        for domainSummary in summary?.objectiveDomainSummaries ?? [] {
            lines.append(objectiveDomainSummaryLine(prefix: "cycle_history_objective_domain", summary: domainSummary))
        }
    }

    private static func feedbackPenalizedActionIDs(
        from cycle: RunReviewSignoffRepairCandidateCycleResult?
    ) -> [String] {
        let actionIDs = cycle?.candidateGeneration.symbolicPlannerTrace?.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.compactMap { actionTrace in
                actionTrace.scoreComponents.contains {
                    $0.termID.hasPrefix("feedback.") && $0.contribution < 0
                } ? actionTrace.actionID : nil
            }
        } ?? []
        return uniquePreservingOrder(actionIDs)
    }

    private static func feedbackPenaltyTerms(
        from cycle: RunReviewSignoffRepairCandidateCycleResult?
    ) -> [String] {
        let terms = cycle?.candidateGeneration.symbolicPlannerTrace?.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.flatMap { actionTrace in
                actionTrace.scoreComponents.compactMap { component in
                    component.termID.hasPrefix("feedback.") && component.contribution < 0
                        ? "\(actionTrace.actionID):\(component.termID)"
                        : nil
                }
            }
        } ?? []
        return uniquePreservingOrder(terms)
    }

    private static func selectedActionDomainIDs(
        from cycle: RunReviewSignoffRepairCandidateCycleResult?
    ) -> [String] {
        let domainIDs = cycle?.candidateGeneration.symbolicPlannerTrace?.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.compactMap { actionTrace in
                actionTrace.selected ? actionTrace.domainID : nil
            }
        } ?? []
        return uniquePreservingOrder(domainIDs)
    }

    private static func feedbackRankChanges(
        from cycle: RunReviewSignoffRepairCandidateCycleResult?
    ) -> [String] {
        let changes: [String] = cycle?.candidateGeneration.symbolicPlannerTrace?.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.compactMap { actionTrace in
                guard actionTrace.rejectedFeedbackRankDelta != 0 else {
                    return nil
                }
                return "\(actionTrace.actionID):\(actionTrace.rankBeforeRejectedFeedback)->\(actionTrace.rank)"
            }
        } ?? []
        return uniquePreservingOrder(changes)
    }

    private static func feedbackScoreDeltas(
        from cycle: RunReviewSignoffRepairCandidateCycleResult?
    ) -> [String] {
        let deltas: [String] = cycle?.candidateGeneration.symbolicPlannerTrace?.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.compactMap { actionTrace in
                guard actionTrace.rejectedFeedbackScoreDelta != 0 else {
                    return nil
                }
                return "\(actionTrace.actionID):\(actionTrace.rejectedFeedbackScoreDelta)"
            }
        } ?? []
        return uniquePreservingOrder(deltas)
    }

    private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private static func objectiveDomainSummaryLine(
        prefix: String,
        summary: RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary
    ) -> String {
        "\(prefix)=\(summary.domainID),cycles=\(summary.cycleCount),accepted=\(summary.acceptedCount),not_accepted=\(summary.notAcceptedCount),acceptance_rate=\(summary.acceptanceRate),rank_changes=\(summary.feedbackRankChangeCount),score_deltas=\(summary.feedbackScoreDeltaCount),actions=\(summary.selectedActionIDs.joined(separator: ",")),action_domains=\(summary.selectedActionDomainIDs.joined(separator: ","))"
    }

    private static func appendSignoffRepairCandidateCycleHistory(
        _ summary: RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary?,
        includeRecommendations: Bool,
        to lines: inout [String]
    ) {
        lines.append("history_run_count=\(summary?.runCount ?? 0)")
        lines.append("history_cycle_count=\(summary?.cycleCount ?? 0)")
        lines.append("history_accepted_count=\(summary?.acceptedCount ?? 0)")
        lines.append("history_not_accepted_count=\(summary?.notAcceptedCount ?? 0)")
        lines.append(
            "history_consumed_rejected_feedback_count=\(summary?.consumedRejectedPlanFeedbackRecordCount ?? 0)"
        )
        lines.append(
            "history_max_global_rejected_feedback_count=\(summary?.maximumGlobalRejectedPlanFeedbackCount ?? 0)"
        )
        lines.append("history_feedback_rank_change_count=\(summary?.feedbackRankChangeCount ?? 0)")
        lines.append("history_feedback_score_delta_count=\(summary?.feedbackScoreDeltaCount ?? 0)")
        lines.append(
            "history_selected_actions=\(summary?.selectedActionIDs.joined(separator: ",") ?? "")"
        )
        lines.append(
            "history_selected_action_domains=\(summary?.selectedActionDomainIDs.joined(separator: ",") ?? "")"
        )
        lines.append(
            "history_selected_objective_domains=\(summary?.selectedObjectiveDomainIDs.joined(separator: ",") ?? "")"
        )
        lines.append(
            "history_feedback_penalized_actions=\(summary?.feedbackPenalizedActionIDs.joined(separator: ",") ?? "")"
        )
        lines.append(
            "history_feedback_rank_changed_actions=\(summary?.feedbackRankChangedActionIDs.joined(separator: ",") ?? "")"
        )
        lines.append(
            "history_feedback_score_delta_actions=\(summary?.feedbackScoreDeltaActionIDs.joined(separator: ",") ?? "")"
        )
        for domainSummary in summary?.objectiveDomainSummaries ?? [] {
            lines.append(objectiveDomainSummaryLine(prefix: "history_objective_domain", summary: domainSummary))
        }
        for run in summary?.runs ?? [] {
            lines.append(
                "history_run=\(run.runID),cycles=\(run.cycleCount),accepted=\(run.acceptedCount),rank_changes=\(run.feedbackRankChangeCount),summary=\(run.summaryPath)"
            )
        }
        if includeRecommendations {
            for recommendation in summary?.recommendations ?? [] {
                lines.append("recommendation=\(recommendation)")
            }
        }
    }

    private static func appendNetlist(_ netlist: String?, to lines: inout [String]) {
        lines.append("netlist_begin")
        lines.append(netlist ?? "")
        lines.append("netlist_end")
    }

    private static func appendRoundTrip(
        result: DesignFlowCommandResult,
        context: FlowRunnerOutputContext,
        to lines: inout [String]
    ) {
        lines.append("round_trip=passed")
        appendDesignOrFixture(result: result, context: context, to: &lines)
        lines.append("run_id=\(result.runID ?? "")")
        lines.append("project_root=\(result.projectRootPath ?? "")")
        lines.append("manifest=\(result.manifestPath ?? "")")
        lines.append("ready_for_pex=\(result.readyForPEX ?? false)")
        lines.append("pex_corner=\(result.pexCornerID ?? "")")
        lines.append("pex_elements=\(result.pexElementCount ?? 0)")
        lines.append("external_signoff=\(signoffSource(result: result, context: context))")
        let approved = signoffApproved(result: result, context: context)
        lines.append("signoff_approved=\(approved)")
        // The --approve-signoff flag is the only approval source on this path
        // and the service records it as an automated approval; human approvals
        // arrive through review/approval records, never through this command.
        lines.append("signoff_approval_kind=\(approved ? ExternalSignoffReview.ApprovalKind.automated.rawValue : "")")
        lines.append("comparison_limits=\(result.comparisonLimitsConfigured == true ? "configured" : "none")")
    }

    private static func appendRoundTripReview(
        result: DesignFlowCommandResult,
        to lines: inout [String]
    ) {
        let review = result.roundTripReview
        lines.append("round_trip_review=\(review?.status.rawValue ?? "")")
        lines.append("run_id=\(review?.runID ?? result.runID ?? "")")
        lines.append("manifest=\(review?.manifestPath ?? result.manifestPath ?? "")")
        lines.append("ready_for_pex=\(review?.isReadyForPEX ?? false)")
        lines.append("stage_count=\(review?.stages.count ?? 0)")
        lines.append("artifact_count=\(review?.artifacts.count ?? 0)")
        lines.append("diagnostic_count=\(review?.diagnostics.count ?? 0)")
        lines.append("warning_count=\(review?.warnings.count ?? 0)")
        for warning in review?.warnings ?? [] {
            lines.append("warning=\(warning)")
        }
        if let comparison = review?.postLayoutComparison {
            lines.append("comparison_status=\(comparison.status)")
            lines.append("comparison_gate=\(comparison.gateStatus)")
            for metric in comparison.oscillationMetrics {
                lines.append("oscillation_metric=\(metric.variableName)")
                if let preFrequency = metric.preLayoutFrequency {
                    lines.append("oscillation_pre_frequency=\(preFrequency)")
                }
                if let postFrequency = metric.postLayoutFrequency {
                    lines.append("oscillation_post_frequency=\(postFrequency)")
                }
                if let frequencyRelativeDelta = metric.frequencyRelativeDelta {
                    lines.append("oscillation_frequency_relative_delta=\(frequencyRelativeDelta)")
                }
                if let preAmplitude = metric.preLayoutAmplitude {
                    lines.append("oscillation_pre_amplitude=\(preAmplitude)")
                }
                if let postAmplitude = metric.postLayoutAmplitude {
                    lines.append("oscillation_post_amplitude=\(postAmplitude)")
                }
            }
        }
        if let externalSignoff = review?.externalSignoff {
            lines.append("signoff_passed=\(externalSignoff.passed)")
            lines.append("signoff_approved=\(externalSignoff.approved)")
            lines.append("signoff_approval_kind=\(externalSignoff.approvalKind?.rawValue ?? "")")
            lines.append("signoff_approved_by=\(externalSignoff.approvedBy ?? "")")
        }
        lines.append("approval_count=\(review?.approvals.count ?? 0)")
        for approval in review?.approvals ?? [] {
            lines.append("approval_stage=\(approval.stageID)")
            lines.append("approval_verdict=\(approval.verdict.rawValue)")
        }
        lines.append("suggested_action_selection_count=\(review?.suggestedActionSelections.count ?? 0)")
        for selection in review?.suggestedActionSelections ?? [] {
            lines.append("selected_suggested_action=\(selection.action.id)")
            lines.append("selected_action_record=\(selection.actionRecordID)")
        }
        lines.append("toolchain_stage_count=\(review?.toolchain?.stageCount ?? 0)")
        lines.append("toolchain_selected_tools=\(review?.toolchain?.selectedToolIDs.joined(separator: ",") ?? "")")
        lines.append("toolchain_rejected_evaluation_count=\(review?.toolchain?.rejectedEvaluationCount ?? 0)")
        lines.append(
            "toolchain_missing_selection_stages=\(review?.toolchain?.missingSelectionStageIDs.joined(separator: ",") ?? "")"
        )
        lines.append("toolchain_profile_id=\(review?.toolchain?.profileID ?? "")")
        lines.append("toolchain_pdk_id=\(review?.toolchain?.pdkID ?? "")")
        lines.append("toolchain_catalog_id=\(review?.toolchain?.technologyCatalogID ?? "")")
        lines.append("toolchain_catalog_path=\(review?.toolchain?.technologyCatalogPath ?? "")")
        lines.append("toolchain_profile_artifact_path=\(review?.toolchain?.profileArtifactPath ?? "")")
        for artifact in review?.toolchainArtifacts ?? [] {
            lines.append("toolchain_artifact=\(artifact.reference.locator.location.value)")
            lines.append("toolchain_artifact_integrity=\(artifact.integrity?.status.rawValue ?? "untracked")")
        }
        for recommendation in review?.recommendations ?? [] {
            lines.append("recommendation=\(recommendation)")
        }
    }

    private static func appendDesignOrFixture(
        result: DesignFlowCommandResult,
        context: FlowRunnerOutputContext,
        to lines: inout [String]
    ) {
        if let designName = result.designName {
            lines.append("design=\(designName)")
        } else {
            lines.append("fixture=\(result.fixtureName ?? context.fixtureName)")
        }
        if let technologyPackageID = result.technologyPackageID {
            lines.append("technology_package_id=\(technologyPackageID)")
        }
    }

    private static func signoffSource(
        result: DesignFlowCommandResult,
        context: FlowRunnerOutputContext
    ) -> String {
        if context.usesImportedSignoff {
            return "imported-logs"
        }
        if result.technologyPackageID != nil {
            return "technology-package"
        }
        return "none"
    }

    private static func signoffApproved(
        result: DesignFlowCommandResult,
        context: FlowRunnerOutputContext
    ) -> Bool {
        signoffSource(result: result, context: context) != "none" && context.approveSignoff
    }

    private static func firstActionRecordID(from result: DesignFlowCommandResult) -> String? {
        result.actionRecordIDs?.first
    }

    private static func lastActionRecordID(from result: DesignFlowCommandResult) -> String? {
        result.actionRecordIDs?.last
    }

    private static func actionRecordID(from result: DesignFlowCommandResult, at index: Int) -> String? {
        guard let actionRecordIDs = result.actionRecordIDs,
              actionRecordIDs.indices.contains(index) else {
            return nil
        }
        return actionRecordIDs[index]
    }
}
