import DesignFlowKernel
import SwiftUI

struct RunReviewSignoffRepairPlanningPanel: View {
    let signoff: RunReviewSignoffSummary
    let runID: String
    let planningInFlight: Bool
    let candidateCycleInFlight: Bool
    let planningResult: RunReviewSignoffRepairPlanningResult?
    let candidateCycleResult: RunReviewSignoffRepairCandidateCycleResult?
    let planningError: String?
    let candidateCycleError: String?
    let formulateRepairPlanning: () -> Void
    let runCandidateCycle: () -> Void

    var body: some View {
        let repairHintCount = signoffRepairHintArtifacts(signoff).count
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    formulateRepairPlanning()
                } label: {
                    Label("Generate Repair Plan", systemImage: "wand.and.stars")
                }
                .font(.caption)
                .disabled(repairHintCount == 0 || planningInFlight)

                Button {
                    runCandidateCycle()
                } label: {
                    Label("Run Candidate Cycle", systemImage: "play.circle")
                }
                .font(.caption)
                .disabled(repairHintCount == 0 || candidateCycleInFlight)

                if planningInFlight {
                    ProgressView()
                        .controlSize(.small)
                }

                if candidateCycleInFlight {
                    ProgressView()
                        .controlSize(.small)
                }

                Text("\(repairHintCount) hint reports")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            planningResultRow(planningResult)
            candidateCycleResultRow(candidateCycleResult)
            candidateCycleHistory(signoff.repairCandidateCycles)
            errorRow(planningError)
            errorRow(candidateCycleError)
        }
    }

    @ViewBuilder
    private func planningResultRow(
        _ result: RunReviewSignoffRepairPlanningResult?
    ) -> some View {
        if let result {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(result.problemID)
                    .font(.caption2.monospaced())
                Text(result.planningProblemArtifact.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func candidateCycleResultRow(
        _ result: RunReviewSignoffRepairCandidateCycleResult?
    ) -> some View {
        if let result {
            HStack(spacing: 6) {
                Image(systemName: result.candidateVerification.accepted ? "checkmark.seal.fill" : "pause.circle.fill")
                    .foregroundStyle(result.candidateVerification.accepted ? .green : .orange)
                Text(result.candidateVerification.status)
                    .font(.caption2.monospaced())
                Text(result.candidateVerification.planVerificationArtifact.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func candidateCycleHistory(
        _ cycles: [RunReviewSignoffRepairCandidateCycleHistoryItem]
    ) -> some View {
        if !cycles.isEmpty {
            let historySummary = RunReviewSignoffRepairCandidateCycleHistorySummary(cycles: cycles)
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 5) {
                    candidateCycleSummary(historySummary)
                    Divider()
                    ForEach(Array(cycles.suffix(5).reversed())) { cycle in
                        candidateCycleRow(cycle)
                    }
                }
                .padding(.top, 3)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                    Text("Candidate Cycles")
                        .font(.caption2.weight(.semibold))
                    Text("\(cycles.count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    if historySummary.hasFeedbackImpact {
                        Text("feedback-impact")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
    }

    private func candidateCycleSummary(
        _ summary: RunReviewSignoffRepairCandidateCycleHistorySummary
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120), spacing: 6)],
            alignment: .leading,
            spacing: 3
        ) {
            repairCycleMetric("Accepted", "\(summary.acceptedCount)/\(summary.cycleCount)")
            repairCycleMetric("Not accepted", "\(summary.notAcceptedCount)")
            if let latestCycleIndex = summary.latestCycleIndex {
                repairCycleMetric("Latest", "#\(latestCycleIndex)")
            }
            repairCycleMetric(
                "Feedback",
                "\(summary.consumedRejectedPlanFeedbackRecordCount)/\(summary.maximumGlobalRejectedPlanFeedbackCount)"
            )
            repairCycleMetric("Rank changes", "\(summary.feedbackRankChangeCount)")
            repairCycleMetric("Score deltas", "\(summary.feedbackScoreDeltaCount)")
            repairCycleMetric("Rank actions", joinedOrNil(summary.feedbackRankChangedActionIDs))
            repairCycleMetric("Penalized", joinedOrNil(summary.feedbackPenalizedActionIDs))
        }
    }

    private func candidateCycleRow(
        _ cycle: RunReviewSignoffRepairCandidateCycleHistoryItem
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: planningStatusIcon(cycle.status.rawValue))
                    .foregroundStyle(planningStatusColor(cycle.status.rawValue))
                Text("#\(cycle.cycleIndex)")
                    .font(.caption2.monospaced())
                if let verificationStatus = cycle.verificationStatus {
                    planningStatusBadge(verificationStatus)
                }
                Text(cycle.accepted ? "accepted" : "not-accepted")
                    .font(.caption2)
                    .foregroundStyle(cycle.accepted ? .green : .orange)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: 6)],
                alignment: .leading,
                spacing: 3
            ) {
                repairCycleMetric("Plan", cycle.planID)
                repairCycleMetric(
                    "Feedback",
                    "\(cycle.rejectedPlanFeedbackRecordCount)/\(cycle.globalRejectedPlanFeedbackCount)"
                )
                repairCycleMetric("Selected", joinedOrNil(cycle.selectedActionIDs))
                repairCycleMetric("Penalized", joinedOrNil(cycle.feedbackPenalizedActionIDs))
                repairCycleMetric("Rank change", joinedOrNil(cycle.feedbackRankChanges))
                repairCycleMetric("Score delta", joinedOrNil(cycle.feedbackScoreDeltas))
                repairCycleMetric("Verification", cycle.planVerificationArtifact?.path)
                repairCycleMetric("Rejected", cycle.rejectedPlansPath)
            }
        }
    }

    @ViewBuilder
    private func repairCycleMetric(
        _ label: String,
        _ value: String?
    ) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption2.monospaced())
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func errorRow(_ error: String?) -> some View {
        if let error {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private func signoffRepairHintArtifacts(
        _ signoff: RunReviewSignoffSummary
    ) -> [FlowRunReviewArtifact] {
        var seenPaths = Set<String>()
        var artifacts: [FlowRunReviewArtifact] = []
        for card in signoff.cards {
            for artifact in [card.artifact] + card.relatedArtifacts where isSignoffRepairHintArtifact(artifact) {
                guard seenPaths.insert(artifact.path).inserted else {
                    continue
                }
                artifacts.append(artifact)
            }
        }
        return artifacts.sorted { left, right in
            if (left.artifactID ?? "") != (right.artifactID ?? "") {
                return (left.artifactID ?? "") < (right.artifactID ?? "")
            }
            return left.path < right.path
        }
    }

    private func isSignoffRepairHintArtifact(_ artifact: FlowRunReviewArtifact) -> Bool {
        let artifactID = artifact.artifactID ?? ""
        if artifactID == "drc-repair-hints" || artifactID == "lvs-repair-hints" {
            return true
        }
        let searchable = [
            artifactID,
            artifact.role,
            artifact.path,
        ]
        .map { $0.lowercased() }
        .joined(separator: " ")
        return (searchable.contains("drc") || searchable.contains("lvs"))
            && searchable.contains("repair-hints")
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
        case "failed", "rejected", "blocked", "error", "missing", "unsupported", "critical", "high", "not-accepted", "removed":
            return .red
        case "pending", "needs-review", "approval-required", "incomplete", "medium", "warning", "modified", "truncated":
            return .orange
        default:
            return .secondary
        }
    }

    private func joinedOrNil(_ values: [String]) -> String? {
        guard !values.isEmpty else {
            return nil
        }
        return values.joined(separator: ", ")
    }
}
