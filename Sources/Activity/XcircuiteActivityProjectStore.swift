import DesignFlowKernel
import Foundation
import Xcircuite

/// Project reader for Activity reconciliation.
///
/// New workspaces are read through `XcircuiteWorkspaceFileStore` and
/// `XcircuiteRunLedgerStore`. The injected kernel loader remains a narrow
/// read-only fallback for pre-migration workspaces that do not yet contain a
/// consolidated `ledger.json`.
public struct XcircuiteActivityProjectStore: ActivityProjectReading {
    private let legacyLedgerLoader: FlowRunLedgerLoader

    public init(legacyLedgerLoader: FlowRunLedgerLoader = FlowRunLedgerLoader()) {
        self.legacyLedgerLoader = legacyLedgerLoader
    }

    public func projectManifest(for projectRoot: URL) async throws -> XcircuiteProjectManifest {
        let workspace = try XcircuiteWorkspaceFileStore(projectRoot: projectRoot)
        return try await workspace.readJSON(
            XcircuiteProjectManifest.self,
            from: "project.json"
        )
    }

    public func runIDs(for projectRoot: URL) async throws -> [String] {
        let workspace = try XcircuiteWorkspaceFileStore(projectRoot: projectRoot)
        let runsURL = try await workspace.url(for: "runs")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: runsURL.path(percentEncoded: false),
            isDirectory: &isDirectory
        ) else {
            return []
        }
        guard isDirectory.boolValue else {
            throw XcircuiteWorkspaceFileStoreError.pathOutsideWorkspace("runs")
        }

        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: runsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw XcircuiteWorkspaceFileStoreError.readFailed(error.localizedDescription)
        }

        var runIDs: [String] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values: URLResourceValues
            do {
                values = try entry.resourceValues(forKeys: [.isDirectoryKey])
            } catch {
                throw XcircuiteWorkspaceFileStoreError.readFailed(error.localizedDescription)
            }
            guard values.isDirectory == true else {
                continue
            }
            let runID = entry.lastPathComponent
            // Resolving the child through the workspace boundary rejects a
            // symlinked run directory before it can be indexed.
            _ = try await workspace.url(for: "runs/\(runID)")
            runIDs.append(runID)
        }
        return runIDs
    }

    public func loadRunLedger(runID: String, projectRoot: URL) async throws -> FlowRunLedger {
        let ledgerStore = try XcircuiteRunLedgerStore(projectRoot: projectRoot)
        do {
            return try await ledgerStore.loadRunLedger(runID: runID, projectRoot: projectRoot)
        } catch FlowRunLedgerPersistenceError.resumeTargetNotFound {
            return try legacyLedgerLoader.loadRunLedger(
                runID: runID,
                projectRoot: projectRoot
            )
        }
    }
}
