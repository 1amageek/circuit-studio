import Xcircuite

public struct RunReviewSuggestedActionExecutionResult: Sendable {
    public let resolvedAction: XcircuiteResolvedSuggestedAction
    public let commandOutput: String

    public init(
        resolvedAction: XcircuiteResolvedSuggestedAction,
        commandOutput: String
    ) {
        self.resolvedAction = resolvedAction
        self.commandOutput = commandOutput
    }
}
