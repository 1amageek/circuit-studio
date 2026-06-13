import Foundation

/// Persisted Circuit Studio session state stored in
/// `.xcircuite/studio-session.json`.
///
/// `.xcircuite/project.json` belongs to `XcircuiteProjectManifest`, the
/// canonical package ledger for artifact and run references. This manifest
/// only records UI/session cell pointers that are needed to reopen the
/// human editing workspace.
public struct StudioSessionManifest: Sendable, Codable {
    public var version: Int
    public var topCell: String
    public var activeCell: String

    public init(version: Int = 1, topCell: String, activeCell: String) {
        self.version = version
        self.topCell = topCell
        self.activeCell = activeCell
    }
}
