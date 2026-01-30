import Foundation

/// Service for scanning project directories and reading files.
public struct FileSystemService: Sendable {

    public init() {}

    /// Recursively scan a directory and return a file tree.
    public func scanDirectory(at url: URL) throws -> FileNode {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: options
        ) else {
            return FileNode(id: url, name: url.lastPathComponent, isDirectory: true, children: [])
        }

        var children: [FileNode] = []
        for item in contents.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let resourceValues = try item.resourceValues(forKeys: Set(resourceKeys))
            let isDirectory = resourceValues.isDirectory ?? false

            if isDirectory {
                let child = try scanDirectory(at: item)
                children.append(child)
            } else {
                children.append(FileNode(
                    id: item,
                    name: item.lastPathComponent,
                    isDirectory: false
                ))
            }
        }

        return FileNode(
            id: url,
            name: url.lastPathComponent,
            isDirectory: true,
            children: children
        )
    }

    /// Read the contents of a file as a UTF-8 string.
    public func readFile(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
