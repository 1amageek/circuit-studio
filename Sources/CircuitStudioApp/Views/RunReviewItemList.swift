import SwiftUI
import DesignFlowKernel

struct RunReviewItemList: View {
    let items: [FlowRunReviewItem]

    var body: some View {
        GroupBox("Review Items") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.itemID) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: reviewItemIcon(item))
                                .foregroundStyle(reviewItemColor(item))
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(item.status.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(item.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !item.diagnosticCodes.isEmpty {
                            Text(item.diagnosticCodes.joined(separator: ", "))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        if !item.artifactPaths.isEmpty {
                            ForEach(item.artifactPaths, id: \.self) { path in
                                Text(path)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let nextActionID = item.nextActionID {
                            Text("Next: \(nextActionID)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
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
}
