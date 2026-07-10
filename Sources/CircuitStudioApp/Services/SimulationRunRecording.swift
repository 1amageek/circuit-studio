import Foundation
import CircuitStudioCore

public protocol SimulationRunRecording: Sendable {
    func begin(
        projectRoot: URL,
        intent: String,
        source: String?,
        fileName: String?,
        startedAt: Date
    ) throws -> SimulationRunContext

    func complete(
        context: SimulationRunContext,
        source: String?,
        records: [AnalysisRunRecord]
    ) async throws

    func fail(
        context: SimulationRunContext,
        reason: String
    ) throws
}
