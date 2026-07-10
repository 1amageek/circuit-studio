import Foundation

/// Service for scanning project directories and reading files.
public struct FileSystemService: Sendable {

    public init() {}

    /// Recursively scan a directory and return a file tree.
    public func scanDirectory(at url: URL) throws -> FileNode {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: resourceKeys,
                options: options
            )
        } catch {
            throw StudioError.projectLoadFailed(error.localizedDescription)
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
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw StudioError.fileReadError(error.localizedDescription)
        }
    }

    /// Read a file without assuming a text encoding.
    public func readData(at url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw StudioError.fileReadError(error.localizedDescription)
        }
    }

    /// Atomically write UTF-8 text to a project file.
    public func writeFile(_ text: String, to url: URL) throws {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw StudioError.projectSaveFailed(error.localizedDescription)
        }
    }
}
