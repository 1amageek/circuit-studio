import Foundation

/// A node in the project file tree, used with `OutlineGroup`.
public struct FileNode: Identifiable, Hashable, Sendable {
    public let id: URL
    public let name: String
    public let isDirectory: Bool
    public var children: [FileNode]?

    public init(id: URL, name: String, isDirectory: Bool, children: [FileNode]? = nil) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.children = children
    }

    /// Whether this file has a SPICE-related extension.
    public var isSPICEFile: Bool {
        let ext = id.pathExtension.lowercased()
        return ext == "cir" || ext == "spice" || ext == "sp" || ext == "net"
    }
}
