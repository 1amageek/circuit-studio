import DesignFlowKernel
import CircuiteFoundation
import Foundation

public struct RunReviewArtifactResource: Sendable, Hashable {
    public let runID: String
    public let artifact: FlowRunReviewArtifact
    public let url: URL
    public let reference: ArtifactReference

    public init(
        runID: String,
        artifact: FlowRunReviewArtifact,
        url: URL,
        reference: ArtifactReference
    ) {
        self.runID = runID
        self.artifact = artifact
        self.url = url
        self.reference = reference
    }

    public var digest: ContentDigest { reference.digest }
}
