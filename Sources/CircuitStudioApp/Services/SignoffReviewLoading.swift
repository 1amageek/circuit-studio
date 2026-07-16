import CircuitSignoff

public protocol SignoffReviewLoading: Sendable {
    func load(logs: [ExternalSignoffLogArtifact]) throws -> ExternalSignoffReview
}
