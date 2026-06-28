import DesignFlowKernel
import Foundation

public struct RunReviewWaiverEditVerificationContext: Sendable, Hashable {
    public let designSpecArtifact: FlowRunReviewArtifact
    public let layoutDocumentArtifact: FlowRunReviewArtifact
    public let designUnitArtifact: FlowRunReviewArtifact?
    public let designSpecURL: URL
    public let layoutDocumentURL: URL
    public let designUnitURL: URL?

    public init(
        designSpecArtifact: FlowRunReviewArtifact,
        layoutDocumentArtifact: FlowRunReviewArtifact,
        designUnitArtifact: FlowRunReviewArtifact?,
        designSpecURL: URL,
        layoutDocumentURL: URL,
        designUnitURL: URL?
    ) {
        self.designSpecArtifact = designSpecArtifact
        self.layoutDocumentArtifact = layoutDocumentArtifact
        self.designUnitArtifact = designUnitArtifact
        self.designSpecURL = designSpecURL
        self.layoutDocumentURL = layoutDocumentURL
        self.designUnitURL = designUnitURL
    }
}
