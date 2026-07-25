import SwiftUI
import DesignFlowKernel

struct RunReviewNextActionList: View {
    let actions: [FlowRunNextAction]
    let selections: [FlowRunSuggestedActionSelection]
    let recordSelection: (FlowRunNextAction, FlowRunSuggestedAction) -> Void
    let runAction: (FlowRunNextAction, FlowRunSuggestedAction) -> Void
    let runningActionIDs: Set<String>
    let executionErrors: [String: String]

    var body: some View {
        GroupBox("Next Actions") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(actions, id: \.actionID) { action in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: nextActionIcon(action))
                                .foregroundStyle(nextActionColor(action))
                            Text(action.kind)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(action.severity.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(action.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !action.diagnosticCodes.isEmpty {
                            Text(action.diagnosticCodes.joined(separator: ", "))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        if !action.suggestedActions.isEmpty {
                            ForEach(action.suggestedActions, id: \.id) { suggestedAction in
                                let selection = selectedAction(
                                    action: action,
                                    suggestedAction: suggestedAction
                                )
                                let executionID = executionID(
                                    action: action,
                                    suggestedAction: suggestedAction
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(suggestedAction.readiness.rawValue)
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(
                                                actionReadinessColor(suggestedAction.readiness).opacity(0.16),
                                                in: Capsule()
                                            )
                                            .foregroundStyle(actionReadinessColor(suggestedAction.readiness))
                                        Text(suggestedAction.id)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                        if let selection {
                                            Text("Selected by \(selection.actor.identifier)")
                                                .font(.caption2)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                                                .foregroundStyle(Color.accentColor)
                                        }
                                        if suggestedAction.readiness == .ready {
                                            Button {
                                                runAction(action, suggestedAction)
                                            } label: {
                                                if runningActionIDs.contains(executionID) {
                                                    ProgressView()
                                                        .controlSize(.small)
                                                } else {
                                                    Label("Run", systemImage: "play.fill")
                                                }
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .disabled(runningActionIDs.contains(executionID))
                                        } else {
                                            Button {
                                                recordSelection(action, suggestedAction)
                                            } label: {
                                                Label("Record", systemImage: "bookmark")
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                    Text(String(describing: suggestedAction.operation))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
                                    if let executionError = executionErrors[executionID] {
                                        Text(executionError)
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                            .lineLimit(4)
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func executionID(
        action: FlowRunNextAction,
        suggestedAction: FlowRunSuggestedAction
    ) -> String {
        "\(action.actionID)::\(suggestedAction.id)"
    }

    private func selectedAction(
        action: FlowRunNextAction,
        suggestedAction: FlowRunSuggestedAction
    ) -> FlowRunSuggestedActionSelection? {
        selections.last {
            $0.status == .succeeded
                && $0.nextActionID == action.actionID
                && $0.action.id == suggestedAction.id
        }
    }

    private func actionReadinessColor(_ readiness: FlowRunSuggestedActionReadiness) -> Color {
        switch readiness {
        case .ready:
            return .green
        case .requiresInput:
            return .orange
        }
    }

    private func nextActionIcon(_ action: FlowRunNextAction) -> String {
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

    private func nextActionColor(_ action: FlowRunNextAction) -> Color {
        switch action.severity {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
