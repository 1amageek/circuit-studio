public protocol SignoffCommandRuntime: Sendable {
    func inspectToolchain(
        options: SignoffCommandOptions,
        output: SignoffCommandOutput
    ) throws -> Int32

    func evaluateDesign(
        options: SignoffCommandOptions,
        output: SignoffCommandOutput
    ) async throws -> Bool

    func runIteration(
        options: SignoffCommandOptions,
        output: SignoffCommandOutput
    ) async throws -> Int32
}
