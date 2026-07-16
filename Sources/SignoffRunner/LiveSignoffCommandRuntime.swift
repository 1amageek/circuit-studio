public struct LiveSignoffCommandRuntime: SignoffCommandRuntime {
    public init() {}

    public func inspectToolchain(
        options: SignoffCommandOptions,
        output: SignoffCommandOutput
    ) throws -> Int32 {
        try SignoffCommand.inspectLiveToolchain(options, output: output)
    }

    public func evaluateDesign(
        options: SignoffCommandOptions,
        output: SignoffCommandOutput
    ) async throws -> Bool {
        try await SignoffCommand.evaluateLiveDesign(options, output: output)
    }

    public func runIteration(
        options: SignoffCommandOptions,
        output: SignoffCommandOutput
    ) async throws -> Int32 {
        try await SignoffCommand.runLiveIteration(options, output: output)
    }
}
