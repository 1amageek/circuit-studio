import Foundation

public protocol RunReviewSuggestedActionExecuting: Sendable {
    func execute(
        runID: String,
        actionID: String,
        projectRoot: URL
    ) async throws -> RunReviewSuggestedActionExecutionResult
}
