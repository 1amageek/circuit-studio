import DesignFlowKernel
import Foundation
import Xcircuite

/// Project reader for Activity reconciliation.
///
/// Workspaces are read exclusively through Xcircuite's canonical persistence.
public struct XcircuiteActivityProjectStore: ActivityProjectReading {
    public init() {}

    public func projectManifest(for projectRoot: URL) async throws -> XcircuiteProjectManifest {
        try await XcircuiteWorkspaceStore(projectRoot: projectRoot).loadManifest()
    }

    public func runIDs(for projectRoot: URL) async throws -> [String] {
        let manifest = try await projectManifest(for: projectRoot)
        return manifest.runs.map(\.runID)
    }

    public func loadRunLedger(runID: String, projectRoot: URL) async throws -> FlowRunLedger {
        try await XcircuiteWorkspaceStore(projectRoot: projectRoot).loadRunLedger(runID: runID)
    }
}
