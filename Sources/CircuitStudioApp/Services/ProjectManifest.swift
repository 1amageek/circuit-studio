import Foundation

/// Persisted project structure stored in `.xcircuite/project.json`: which
/// cell is the hierarchy root and which cell was being edited. The cell
/// list itself is not duplicated here — the `cells/` directory on disk is
/// the source of truth for what cells exist.
public struct ProjectManifest: Sendable, Codable {
    public var version: Int
    public var topCell: String
    public var activeCell: String

    public init(version: Int = 1, topCell: String, activeCell: String) {
        self.version = version
        self.topCell = topCell
        self.activeCell = activeCell
    }
}
