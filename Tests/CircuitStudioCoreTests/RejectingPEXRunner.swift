import Foundation
import PEXEngine

struct RejectingPEXRunner: PEXRunning {
    enum UnexpectedExecution: Error {
        case runCalled
    }

    func run(_ request: PEXRunRequest) async throws -> PEXRunResult {
        throw UnexpectedExecution.runCalled
    }
}
