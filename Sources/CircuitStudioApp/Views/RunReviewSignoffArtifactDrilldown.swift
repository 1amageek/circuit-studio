import DesignFlowKernel
import SwiftUI

struct RunReviewSignoffArtifactDrilldown: View {
    let card: RunReviewSignoffCard
    let runID: String
    let artifactPreviews: [String: RunReviewArtifactPreview]
    let artifactPreviewErrors: [String: String]
    @Binding var waveformSignalSelections: [String: Set<String>]
    let loadArtifactPreview: (FlowRunReviewArtifact) -> Void

    private var artifacts: [FlowRunReviewArtifact] {
        [card.artifact] + card.relatedArtifacts
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                RunReviewSignoffArtifactRows(
                    artifacts: artifacts,
                    runID: runID,
                    artifactPreviews: artifactPreviews,
                    artifactPreviewErrors: artifactPreviewErrors,
                    waveformSignalSelections: $waveformSignalSelections,
                    loadArtifactPreview: loadArtifactPreview
                )
            }
            .padding(.top, 3)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .foregroundStyle(integrityColor(card.artifact.integrity?.status))
                Text("Artifacts")
                    .font(.caption.weight(.semibold))
                Text("\(artifacts.count)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(card.artifact.integrity?.status.rawValue ?? "unverified")
                    .font(.caption2)
                    .foregroundStyle(integrityColor(card.artifact.integrity?.status))
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
