import Foundation
import Xcircuite
import XcircuiteFlowCLISupport

public struct DefaultRunReviewSuggestedActionExecutor: RunReviewSuggestedActionExecuting {
    public init() {}

    public func execute(
        runID: String,
        actionID: String,
        projectRoot: URL
    ) async throws -> RunReviewSuggestedActionExecutionResult {
        let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let resolvedAction = try await XcircuiteSelectedSuggestedActionResolver(
            workspaceStore: store
        ).resolve(
            request: XcircuiteSelectedSuggestedActionResolutionRequest(
                runID: runID,
                actionID: actionID
            )
        )
        let commandOutput = try await XcircuiteFlowCLICommand
            .dispatchResolvedSuggestedAction(resolvedAction)
        return RunReviewSuggestedActionExecutionResult(
            resolvedAction: resolvedAction,
            commandOutput: commandOutput
        )
    }
}
