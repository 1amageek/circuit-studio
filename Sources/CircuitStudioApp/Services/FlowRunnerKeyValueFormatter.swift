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
            lines.append("gate_approval=\(result.approvalRecord?.decision.rawValue ?? "")")
            lines.append("gate=\(result.approvalRecord?.gateID.rawValue ?? "")")
            lines.append("reviewer=\(result.approvalRecord?.reviewer ?? "")")
            lines.append("run_id=\(result.approvalRecord?.runID ?? "")")
            lines.append("approval_record=\(result.approvalRecordPath ?? "")")
            lines.append("target_sha256=\(result.approvalRecord?.targetArtifactSHA256 ?? "")")
            lines.append("approval_warning_count=\(result.approvalRecord?.artifactResolutionWarnings.count ?? 0)")
            for warning in result.approvalRecord?.artifactResolutionWarnings ?? [] {
                lines.append("approval_warning=\(warning)")
            }
        case .reviewRoundTrip:
            appendRoundTripReview(result: result, to: &lines)
        }
        return lines
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
            lines.append("approval_gate=\(approval.gateID.rawValue)")
            lines.append("approval_decision=\(approval.decision.rawValue)")
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
}
