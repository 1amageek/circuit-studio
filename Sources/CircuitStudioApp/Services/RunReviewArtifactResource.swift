import DesignFlowKernel
import Foundation

public struct RunReviewArtifactResource: Sendable, Hashable {
    public let runID: String
    public let artifact: FlowRunReviewArtifact
    public let url: URL
    public let digest: RoundTripArtifactDigest

    public init(
        runID: String,
        artifact: FlowRunReviewArtifact,
        url: URL,
        digest: RoundTripArtifactDigest
    ) {
        self.runID = runID
        self.artifact = artifact
        self.url = url
        self.digest = digest
    }
}
