import DesignFlowKernel
import SwiftUI

struct RunReviewToolchainCard: View {
    let projection: RunReviewToolchainProjection

    var body: some View {
        GroupBox("Toolchain Trust") {
            VStack(alignment: .leading, spacing: 10) {
                if let summary = projection.summary {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 120), spacing: 8)],
                        alignment: .leading,
                        spacing: 6
                    ) {
                        metric("Stages", "\(summary.stageCount)")
                        metric("Selected tools", "\(summary.selectedToolIDs.count)")
                        metric("Rejected", "\(summary.rejectedEvaluationCount)")
                        metric("Missing selections", "\(summary.missingSelectionStageIDs.count)")
                    }

                    valueRow("Profile", value: summary.profileID)
                    valueRow("PDK", value: summary.pdkID)
                    valueRow("Technology catalog", value: summary.technologyCatalogID)
                    valueRow("Catalog path", value: summary.technologyCatalogPath)
                    valueRow("Profile artifact", value: summary.profileArtifactPath)

                    if !summary.selectedToolIDs.isEmpty {
                        valueRow("Selected tool IDs", value: summary.selectedToolIDs.joined(separator: ", "))
                    }
                    if !summary.missingSelectionStageIDs.isEmpty {
                        valueRow(
                            "Missing stage selections",
                            value: summary.missingSelectionStageIDs.joined(separator: ", "),
                            color: .red
                        )
                    }
                }

                if !projection.artifacts.isEmpty {
                    Divider()
                    ForEach(projection.artifacts, id: \.reference.id) { artifact in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(artifact.purpose.rawValue)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Text(artifact.reference.locator.location.value)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                            Text(artifact.integrity?.status.rawValue ?? "untracked")
                                .font(.caption2.monospaced())
                                .foregroundStyle(integrityColor(artifact.integrity?.status))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
        }
    }

    @ViewBuilder
    private func valueRow(_ label: String, value: String?, color: Color = .primary) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption2.monospaced())
                    .foregroundStyle(color)
                    .textSelection(.enabled)
                Spacer()
            }
        }
    }

    private func integrityColor(_ status: FlowRunReviewArtifactIntegrityStatus?) -> Color {
        switch status {
        case .verified:
            return .green
        case nil:
            return .secondary
        default:
            return .red
        }
    }
}
