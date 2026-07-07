import SwiftUI
import DesignFlowKernel

struct RunReviewArtifactList: View {
    let artifacts: [FlowRunReviewArtifact]

    var body: some View {
        GroupBox("Artifacts") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(artifacts, id: \.path) { artifact in
                    HStack {
                        Text(artifact.role)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 92, alignment: .leading)
                        if let artifactID = artifact.artifactID {
                            Text(artifactID)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .leading)
                        }
                        Text(artifact.path)
                            .font(.caption.monospaced())
                        Spacer()
                        if let byteCount = artifact.byteCount {
                            Text("\(byteCount) B")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text(artifact.integrity?.status.rawValue ?? "untracked")
                            .font(.caption2)
                            .foregroundStyle(integrityColor(artifact.integrity?.status))
                        Text(artifact.format.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
