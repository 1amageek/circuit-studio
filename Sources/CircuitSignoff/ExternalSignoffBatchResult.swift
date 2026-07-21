import Foundation

public struct ExternalSignoffBatchResult: Sendable, Hashable {
    public let results: [ExternalSignoffCommandResult]
    public let review: ExternalSignoffReview
    public let evidenceURL: URL

    public init(
        results: [ExternalSignoffCommandResult],
        review: ExternalSignoffReview,
        evidenceURL: URL
    ) {
        self.results = results
        self.review = review
        self.evidenceURL = evidenceURL
    }
}
