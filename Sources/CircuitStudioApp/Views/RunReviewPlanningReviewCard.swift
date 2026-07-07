import SwiftUI
import DesignFlowKernel
import Xcircuite
import XcircuitePackage

struct RunReviewPlanningReviewCard: View {
    let planning: RunReviewService.PlanningReview
    let runID: String
    @Binding var planningApprovalNotes: [String: String]
    let decideRiskApproval: (XcircuiteApprovalRecord.Verdict, String, String) -> Void

    var body: some View {
        GroupBox("Plan Review") {
            VStack(alignment: .leading, spacing: 10) {
                if let candidatePlan = planning.candidatePlanArtifact {
                    planningArtifactRow(
                        title: "Candidate plan",
                        systemImage: "list.clipboard",
                        artifact: candidatePlan
                    )
                }
                if let planVerification = planning.planVerificationArtifact {
                    planningArtifactRow(
                        title: "Plan verification",
                        systemImage: "checklist",
                        artifact: planVerification
                    )
                }
                if let candidatePlan = planning.candidatePlan {
                    candidatePlanDrilldown(candidatePlan)
                }
                if let planVerification = planning.planVerification {
                    planVerificationDrilldown(planVerification, runID: runID)
                }
                if let diffSummary = planning.designDiffSummary {
                    RunReviewDesignDiffSummaryView(summary: diffSummary)
                }
                if !planning.decodeIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Artifact Decode Issues")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(planning.decodeIssues, id: \.artifactPath) { issue in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.artifactRole)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                    Text(issue.message)
                                        .font(.caption)
                                        .lineLimit(3)
                                }
                            }
                        }
                    }
                }
                if !planning.correctnessItems.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Correctness Gates")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(planning.correctnessItems, id: \.itemID) { item in
                            HStack(spacing: 6) {
                                Image(systemName: reviewItemIcon(item))
                                    .foregroundStyle(reviewItemColor(item))
                                Text(item.title)
                                    .font(.caption)
                                Spacer()
                                Text(item.status.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !planning.selectedCommands.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Selected Commands")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(planning.selectedCommands, id: \.actionRecordID) { selection in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(selection.readiness)
                                        .font(.caption2)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                        .foregroundStyle(Color.accentColor)
                                    Text(selection.commandID)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(selection.actor.identifier)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(([selection.executable] + selection.arguments).joined(separator: " "))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func candidatePlanDrilldown(_ plan: XcircuiteCandidatePlan) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    planningStatusBadge(plan.executionReadiness)
                    Text(plan.strategy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(plan.steps.count) steps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ForEach(plan.steps.sorted { $0.order < $1.order }, id: \.stepID) { step in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("#\(step.order)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .leading)
                            planningStatusBadge(step.readiness)
                            Text(step.operationID)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(step.domainID)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if !step.reason.isEmpty {
                            Text(step.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if !step.verificationGates.isEmpty {
                            Text(step.verificationGates.joined(separator: ", "))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                }
                if !plan.riskClassifications.isEmpty {
                    riskClassificationList(plan.riskClassifications)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .foregroundStyle(planningStatusColor(plan.executionReadiness))
                Text("Candidate Plan")
                    .font(.caption.weight(.semibold))
                Text(plan.planID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func planVerificationDrilldown(
        _ verification: XcircuitePlanVerification,
        runID: String
    ) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    planningStatusBadge(verification.accepted ? "accepted" : "not-accepted")
                    Text(verification.verificationMode)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(verification.goalCoverageStatus)
                        .font(.caption2)
                        .foregroundStyle(planningStatusColor(verification.goalCoverageStatus))
                }
                if !verification.gateResults.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Verification Gates")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(verification.gateResults, id: \.gateID) { gate in
                            HStack(spacing: 6) {
                                Image(systemName: planningStatusIcon(gate.status))
                                    .foregroundStyle(planningStatusColor(gate.status))
                                Text(gate.gateID)
                                    .font(.caption)
                                Spacer()
                                planningStatusBadge(gate.status)
                            }
                        }
                    }
                }
                if !verification.riskReviews.isEmpty {
                    riskReviewList(verification.riskReviews, runID: runID)
                }
                if !verification.stepResults.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Step Results")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(verification.stepResults.sorted { $0.order < $1.order }, id: \.stepID) { step in
                            HStack(spacing: 6) {
                                Text("#\(step.order)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34, alignment: .leading)
                                Image(systemName: planningStatusIcon(step.status))
                                    .foregroundStyle(planningStatusColor(step.status))
                                Text(step.operationID)
                                    .font(.caption)
                                Spacer()
                                planningStatusBadge(step.status)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: verification.accepted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(verification.accepted ? .green : .orange)
                Text("Plan Verification")
                    .font(.caption.weight(.semibold))
                Text(verification.planID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func riskClassificationList(_ risks: [XcircuitePlanningRiskClassification]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Plan Risks")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(risks, id: \.riskID) { risk in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        planningStatusBadge(risk.severity)
                        Text(risk.category)
                            .font(.caption)
                        Spacer()
                        Text(risk.scope)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(risk.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if !risk.requiredApprovals.isEmpty {
                        Text("Approvals: \(risk.requiredApprovals.joined(separator: ", "))")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func riskReviewList(
        _ risks: [XcircuitePlanRiskReview],
        runID: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Risk Reviews")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(risks, id: \.riskID) { risk in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        planningStatusBadge(risk.status)
                        Text(risk.riskID)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(risk.severity)
                            .font(.caption2)
                            .foregroundStyle(planningStatusColor(risk.severity))
                    }
                    Text(risk.description)
                        .font(.caption)
                        .lineLimit(2)
                    ForEach(risk.approvalReviews, id: \.approvalID) { approval in
                        approvalReviewRow(approval, runID: runID)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func approvalReviewRow(
        _ approval: XcircuitePlanApprovalReview,
        runID: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(approval.approvalID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                planningStatusBadge(approval.status)
            }
            if approval.status != "approved" {
                HStack(spacing: 6) {
                    TextField(
                        "Approval note",
                        text: Binding(
                            get: { planningApprovalNotes[approval.approvalID, default: ""] },
                            set: { planningApprovalNotes[approval.approvalID] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    Button("Approve") {
                        decidePlanningRiskApproval(
                            .approved,
                            approvalID: approval.approvalID,
                            runID: runID
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Reject") {
                        decidePlanningRiskApproval(
                            .rejected,
                            approvalID: approval.approvalID,
                            runID: runID
                        )
                    }
                }
            } else if let reviewer = approval.reviewer {
                Text("Approved by \(reviewer)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func planningArtifactRow(
        title: String,
        systemImage: String,
        artifact: FlowRunReviewArtifact
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(integrityColor(artifact.integrity?.status))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(artifact.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(artifact.integrity?.status.rawValue ?? "untracked")
                .font(.caption2)
                .foregroundStyle(integrityColor(artifact.integrity?.status))
        }
    }

    private func decidePlanningRiskApproval(
        _ verdict: XcircuiteApprovalRecord.Verdict,
        approvalID: String,
        runID: String
    ) {
        decideRiskApproval(verdict, approvalID, runID)
    }

    private func reviewItemIcon(_ item: FlowRunReviewItem) -> String {
        switch item.kind {
        case .designDiff:
            return "doc.text.magnifyingglass"
        case .approvalGate:
            return "checkmark.seal"
        case .toolTrust:
            return "wrench.and.screwdriver"
        case .stageFailure:
            return "xmark.octagon"
        case .stageBlocker:
            return "pause.circle"
        case .diagnosticReview:
            return "exclamationmark.triangle"
        case .artifactIntegrity:
            return "checkmark.shield"
        case .artifactCoverage:
            return "rectangle.stack.badge.exclamationmark"
        case .planningCorrectness:
            return "checklist"
        case .retainedHistory:
            return "chart.line.uptrend.xyaxis"
        case .archiveOrContinue:
            return "archivebox"
        case .cancellation:
            return "stop.circle"
        }
    }

    private func reviewItemColor(_ item: FlowRunReviewItem) -> Color {
        switch item.severity {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private func planningStatusBadge(_ status: String) -> some View {
        Text(status)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(planningStatusColor(status).opacity(0.14), in: Capsule())
            .foregroundStyle(planningStatusColor(status))
    }

    private func planningStatusIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "passed", "accepted", "approved", "satisfied", "succeeded", "ready", "info", "added":
            return "checkmark.circle.fill"
        case "failed", "rejected", "blocked", "error", "missing", "unsupported", "not-accepted", "removed":
            return "xmark.circle.fill"
        case "pending", "needs-review", "approval-required", "incomplete", "warning", "modified", "truncated":
            return "clock.fill"
        default:
            return "circle"
        }
    }

    private func planningStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "passed", "accepted", "approved", "satisfied", "succeeded", "ready", "low", "info", "added":
            return .green
        case "failed", "rejected", "blocked", "error", "missing", "unsupported", "critical", "high",
             "not-accepted", "removed":
            return .red
        case "pending", "needs-review", "approval-required", "incomplete", "medium", "warning", "modified",
             "truncated":
            return .orange
        default:
            return .secondary
        }
    }

    private func integrityColor(_ status: FlowRunReviewArtifactIntegrityStatus?) -> Color {
        switch status {
        case .verified:
            return .green
        case .missingDigest, .missingByteCount:
            return .orange
        case .missingArtifact, .invalidDigest, .invalidByteCount, .byteCountMismatch, .sha256Mismatch,
             .invalidIdentifier, .noRecordedReference, .invalidPath, .unreadableArtifact:
            return .red
        case nil:
            return .secondary
        }
    }
}
