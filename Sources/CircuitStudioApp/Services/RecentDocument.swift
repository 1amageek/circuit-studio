import Foundation

/// A document the user opened, persisted with a security-scoped bookmark so
/// the sandboxed app can reopen it across launches without an open panel.
public struct RecentDocument: Codable, Identifiable, Hashable, Sendable {

    /// What the bookmark points at, deciding how reopening loads it.
    public enum Kind: String, Codable, Sendable {
        /// A project folder opened via Open Folder or created via New Project.
        case projectFolder
        /// A standalone SPICE netlist opened via Open.
        case netlistFile
    }

    /// Standardized absolute path. Doubles as the stable identity for
    /// deduplication and menu diffing.
    public let path: String

    public let kind: Kind

    /// Security-scoped bookmark resolving to the document across relaunches.
    public let bookmark: Data

    public var id: String { path }

    public var displayName: String {
        URL(filePath: path).lastPathComponent
    }

    public var abbreviatedPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    public init(path: String, kind: Kind, bookmark: Data) {
        self.path = path
        self.kind = kind
        self.bookmark = bookmark
    }
}
