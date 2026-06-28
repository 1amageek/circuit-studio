import SwiftUI
import DesignFlowKernel
import XcircuitePackage

struct RunReviewStageCard: View {
    let stage: RunReviewService.StageReview
    @Binding var note: String
    let decide: (XcircuiteApprovalRecord.Verdict, String) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(stage.result.gates, id: \.gateID) { gate in
                    HStack {
                        Image(systemName: gateIcon(gate.status))
                            .foregroundStyle(gateColor(gate.status))
                        Text(gate.gateID)
                        Spacer()
                        Text(String(describing: gate.status))
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(stage.result.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                    Text("\(diagnostic.code): \(diagnostic.message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let approval = stage.approval {
                    Text(
                        "\(approval.verdict == .approved ? "Approved" : "Rejected") by \(approval.reviewer)"
                            + "\(approval.note.isEmpty ? "" : " - \(approval.note)")"
                    )
                    .font(.caption)
                }
                if stage.awaitingApproval {
                    HStack {
                        TextField("Review note", text: $note)
                            .textFieldStyle(.roundedBorder)
                        Button("Approve") {
                            decide(.approved, stage.result.stageID)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Reject") {
                            decide(.rejected, stage.result.stageID)
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(stage.result.stageID)
                    .font(.headline)
                Spacer()
                Text(String(describing: stage.result.status))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func gateIcon(_ status: FlowGateStatus) -> String {
        switch status {
        case .passed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .waived:
            return "minus.circle"
        case .incomplete:
            return "clock.fill"
        }
    }

    private func gateColor(_ status: FlowGateStatus) -> Color {
        switch status {
        case .passed:
            return .green
        case .failed:
            return .red
        case .waived:
            return .secondary
        case .incomplete:
            return .orange
        }
    }
}
