import DesignFlowKernel
import Foundation

public actor RunReviewArtifactResourceLoader: RunReviewArtifactResourceLoading {
    private let service: RunReviewService

    public init(service: RunReviewService = RunReviewService()) {
        self.service = service
    }

    public func load(
        runID: String,
        artifact: FlowRunReviewArtifact,
        projectRoot: URL
    ) async throws -> RunReviewArtifactResource {
        try Task.checkCancellation()
        let resource = try await service.verifiedArtifactResource(
            runID: runID,
            artifact: artifact,
            projectRoot: projectRoot
        )
        try Task.checkCancellation()
        return resource
    }
}
