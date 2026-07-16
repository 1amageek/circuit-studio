import PEXEngine

struct StubPEXRunner: PEXRunning {
    let result: PEXRunResult

    func run(_ request: PEXRunRequest) async throws -> PEXRunResult {
        result
    }
}
