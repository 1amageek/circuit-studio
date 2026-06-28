import DesignFlowKernel

struct RunReviewWaveformComparisonSource: Hashable {
    let artifact: FlowRunReviewArtifact
    let label: String
    let preview: RunReviewWaveformPreview
}
