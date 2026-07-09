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
                            Image(systemName: item.reviewSystemImage)
                                .foregroundStyle(item.reviewForegroundColor)
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

}
