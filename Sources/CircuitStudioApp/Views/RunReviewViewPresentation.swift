import SwiftUI
import DesignFlowKernel
import Xcircuite

extension RunReviewView {
    func waveformValue(_ value: Double?) -> String {
        guard let value else {
            return "n/a"
        }
        return String(format: "%.4g", value)
    }

    func waveformChartColor(_ index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        return colors[index % colors.count]
    }

    func statusBadge(_ status: FlowRunStatus) -> some View {
        Text(status.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor(status).opacity(0.2), in: Capsule())
            .foregroundStyle(badgeColor(status))
    }

    func badgeColor(_ status: FlowRunStatus) -> Color {
        switch status {
        case .succeeded: return .green
        case .failed: return .red
        case .blocked: return .orange
        default: return .secondary
        }
    }

    func gateIcon(_ status: FlowGateStatus) -> String {
        switch status {
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .blocked: return "exclamationmark.octagon.fill"
        case .waived: return "minus.circle"
        case .incomplete: return "clock.fill"
        }
    }

    func gateColor(_ status: FlowGateStatus) -> Color {
        switch status {
        case .passed: return .green
        case .failed: return .red
        case .blocked: return .orange
        case .waived: return .secondary
        case .incomplete: return .orange
        }
    }

    func reviewItemIcon(_ item: FlowRunReviewItem) -> String {
        item.reviewSystemImage
    }

    func reviewItemColor(_ item: FlowRunReviewItem) -> Color {
        item.reviewForegroundColor
    }

    func failureStateIcon(_ kind: RunReviewFailureStateSummary.Kind) -> String {
        switch kind {
        case .missingArtifact:
            return "doc.badge.questionmark"
        case .integrityMismatch:
            return "checkmark.shield"
        case .staleEvidence:
            return "clock.badge.exclamationmark"
        case .blockedGate:
            return "pause.circle"
        case .decodeFailure:
            return "curlybraces"
        case .unsupportedAction:
            return "nosign"
        }
    }

    func failureStateColor(_ severity: RunReviewFailureStateSummary.Severity) -> Color {
        switch severity {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    func nextActionIcon(_ action: FlowRunNextAction) -> String {
        switch action.kind {
        case "decideApproval":
            return "checkmark.seal"
        case "resumeRun":
            return "play.circle"
        case "repairToolchain":
            return "wrench.and.screwdriver"
        case "repairArtifactCoverage":
            return "rectangle.stack.badge.exclamationmark"
        case "verifyPlanningCorrectness":
            return "checklist"
        case "repairPlanningCorrectness":
            return "arrow.triangle.2.circlepath"
        case "archiveOrContinue":
            return "archivebox"
        default:
            return "arrow.right.circle"
        }
    }

    func nextActionColor(_ action: FlowRunNextAction) -> Color {
        switch action.severity {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    func signoffIcon(_ card: RunReviewSignoffCard) -> String {
        if card.passed == true {
            return "checkmark.seal.fill"
        }
        if card.passed == false {
            return "xmark.octagon.fill"
        }
        return "waveform.path.ecg"
    }

    func signoffColor(_ card: RunReviewSignoffCard) -> Color {
        if card.passed == true {
            return .green
        }
        if card.passed == false {
            return .red
        }
        return planningStatusColor(card.status)
    }

    func interactiveSignoffDrilldownIcon(
        _ domain: RunReviewInteractiveSignoffDrilldown.Domain
    ) -> String {
        switch domain {
        case .designDiff:
            return "rectangle.2.swap"
        case .drc:
            return "ruler"
        case .lvs:
            return "point.3.connected.trianglepath.dotted"
        case .pex:
            return "bolt.horizontal"
        case .oracle:
            return "checkmark.seal"
        case .simulation:
            return "waveform.path.ecg"
        case .postLayout:
            return "rectangle.connected.to.line.below"
        case .waveform:
            return "waveform.path"
        }
    }

    func waiverIcon(_ item: RunReviewWaiverItem) -> String {
        switch item.status {
        case "approved":
            return "checkmark.seal.fill"
        case "rejected":
            return "xmark.octagon.fill"
        default:
            return "exclamationmark.shield"
        }
    }

    func planningStatusBadge(_ status: String) -> some View {
        Text(status)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(planningStatusColor(status).opacity(0.14), in: Capsule())
            .foregroundStyle(planningStatusColor(status))
    }

    func planningStatusIcon(_ status: String) -> String {
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

    func planningStatusColor(_ status: String) -> Color {
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

    func joinedOrNil(_ values: [String]) -> String? {
        guard !values.isEmpty else {
            return nil
        }
        return values.joined(separator: ", ")
    }

    func commandReadinessColor(_ readiness: FlowRunSuggestedCommandReadiness) -> Color {
        switch readiness {
        case .ready:
            return .green
        case .requiresInput:
            return .orange
        }
    }

    func selectedCommand(
        action: FlowRunNextAction,
        command: FlowRunSuggestedCommand,
        selections: [FlowSuggestedCommandSelection]
    ) -> FlowSuggestedCommandSelection? {
        selections.last {
            $0.status == .succeeded
                && $0.nextActionID == action.actionID
                && $0.commandID == command.commandID
        }
    }

    func commandLine(_ command: FlowRunSuggestedCommand) -> String {
        ([command.executable] + command.arguments).joined(separator: " ")
    }

    func integrityColor(_ status: FlowRunReviewArtifactIntegrityStatus?) -> Color {
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
