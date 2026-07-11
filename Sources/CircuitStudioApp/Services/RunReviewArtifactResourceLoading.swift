import DesignFlowKernel
import Foundation

public protocol RunReviewArtifactResourceLoading: Sendable {
    func load(
        runID: String,
        artifact: FlowRunReviewArtifact,
        projectRoot: URL
    ) async throws -> RunReviewArtifactResource
}
