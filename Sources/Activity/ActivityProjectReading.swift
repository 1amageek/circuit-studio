import DesignFlowKernel
import Foundation

/// Reads the canonical project manifest and run ledgers used by Activity.
///
/// Activity indexing depends on this protocol rather than a concrete package
/// store so the UI can use the same workspace/run-ledger boundary as the
/// headless runtime.
public protocol ActivityProjectReading: Sendable {
    func projectManifest(for projectRoot: URL) async throws -> XcircuiteProjectManifest
    func runIDs(for projectRoot: URL) async throws -> [String]
    func loadRunLedger(runID: String, projectRoot: URL) async throws -> FlowRunLedger
}
