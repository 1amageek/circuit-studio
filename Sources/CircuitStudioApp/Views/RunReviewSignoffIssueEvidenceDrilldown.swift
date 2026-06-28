import DesignFlowKernel
import SwiftUI

struct RunReviewSignoffIssueEvidenceDrilldown: View {
    let issue: RunReviewSignoffIssue
    let runID: String
    let artifactPreviews: [String: RunReviewArtifactPreview]
    let artifactPreviewErrors: [String: String]
    @Binding var waveformSignalSelections: [String: Set<String>]
    let loadArtifactPreview: (FlowRunReviewArtifact) -> Void

    var body: some View {
        if !issue.evidenceArtifacts.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    RunReviewSignoffArtifactRows(
                        artifacts: issue.evidenceArtifacts,
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
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                    Text("Evidence")
                        .font(.caption2.weight(.semibold))
                    Text("\(issue.evidenceArtifacts.count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
