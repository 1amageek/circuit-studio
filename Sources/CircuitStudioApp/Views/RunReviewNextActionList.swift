import SwiftUI
import DesignFlowKernel
import DesignFlowKernel

struct RunReviewNextActionList: View {
    let actions: [FlowRunNextAction]
    let selections: [XcircuiteSuggestedCommandSelection]
    let recordSelection: (FlowRunNextAction, FlowRunSuggestedCommand) -> Void

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
                        if !action.suggestedCommands.isEmpty {
                            ForEach(action.suggestedCommands, id: \.commandID) { command in
                                let selection = selectedCommand(
                                    action: action,
                                    command: command
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(command.readiness.rawValue)
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(
                                                commandReadinessColor(command.readiness).opacity(0.16),
                                                in: Capsule()
                                            )
                                            .foregroundStyle(commandReadinessColor(command.readiness))
                                        Text(command.commandID)
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
                                        Button {
                                            recordSelection(action, command)
                                        } label: {
                                            Label("Record", systemImage: "bookmark")
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    Text(commandLine(command))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
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

    private func selectedCommand(
        action: FlowRunNextAction,
        command: FlowRunSuggestedCommand
    ) -> XcircuiteSuggestedCommandSelection? {
        selections.last {
            $0.status == .succeeded
                && $0.nextActionID == action.actionID
                && $0.commandID == command.commandID
        }
    }

    private func commandLine(_ command: FlowRunSuggestedCommand) -> String {
        ([command.executable] + command.arguments).joined(separator: " ")
    }

    private func commandReadinessColor(_ readiness: FlowRunSuggestedCommandReadiness) -> Color {
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
