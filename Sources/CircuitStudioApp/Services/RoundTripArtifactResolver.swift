import Foundation

public enum RoundTripArtifactResolverError: Error, LocalizedError, Equatable {
    case invalidRelativePath(String, String)
    case pathEscapesRunDirectory(path: String, runDirectory: String)

    public var errorDescription: String? {
        switch self {
        case .invalidRelativePath(let path, let reason):
            return "Invalid round-trip artifact path '\(path)': \(reason)"
        case .pathEscapesRunDirectory(let path, let runDirectory):
            return "Round-trip artifact path escapes run directory: \(path) is outside \(runDirectory)"
        }
    }
}

public struct RoundTripArtifactResolver: Sendable {
    public let runDirectory: URL

    public init(runDirectory: URL) {
        self.runDirectory = runDirectory
    }

    public init(manifestURL: URL) {
        self.init(runDirectory: manifestURL.deletingLastPathComponent())
    }

    public func resolve(_ artifact: HeadlessRoundTripService.Artifact) throws -> RoundTripArtifactResolution {
        try resolve(path: artifact.path, kind: artifact.kind)
    }

    public func resolve(path rawPath: String, kind: String) throws -> RoundTripArtifactResolution {
        let artifactPath = try RoundTripArtifactPath(rawPath)
        let url = runDirectory.appending(path: artifactPath.value)
        try validateInsideRunDirectory(url)
        return RoundTripArtifactResolution(url: url)
    }

    public func relativePath(for url: URL) throws -> String {
        try validateInsideRunDirectory(url)

        let directoryPath = standardizedPath(runDirectory)
        let path = standardizedPath(url)
        if let relative = relativePath(path: path, directoryPath: directoryPath) {
            _ = try RoundTripArtifactPath(relative)
            return relative
        }

        let resolvedDirectoryPath = resolvedPath(runDirectory)
        let resolvedURLPath = resolvedPath(url)
        if let relative = relativePath(path: resolvedURLPath, directoryPath: resolvedDirectoryPath) {
            _ = try RoundTripArtifactPath(relative)
            return relative
        }

        throw RoundTripArtifactResolverError.pathEscapesRunDirectory(
            path: url.path(percentEncoded: false),
            runDirectory: runDirectory.path(percentEncoded: false)
        )
    }

    private func validateInsideRunDirectory(_ url: URL) throws {
        let directoryPath = standardizedPath(runDirectory)
        let path = standardizedPath(url)
        guard isInside(path: path, directoryPath: directoryPath) else {
            throw RoundTripArtifactResolverError.pathEscapesRunDirectory(
                path: url.path(percentEncoded: false),
                runDirectory: runDirectory.path(percentEncoded: false)
            )
        }

        let resolvedDirectoryPath = resolvedPath(runDirectory)
        let resolvedURLPath = resolvedPath(url)
        guard isInside(path: resolvedURLPath, directoryPath: resolvedDirectoryPath) else {
            throw RoundTripArtifactResolverError.pathEscapesRunDirectory(
                path: url.path(percentEncoded: false),
                runDirectory: runDirectory.path(percentEncoded: false)
            )
        }
    }

    private func relativePath(path: String, directoryPath: String) -> String? {
        guard path != directoryPath, path.hasPrefix(directoryPath + "/") else {
            return nil
        }
        return String(path.dropFirst(directoryPath.count + 1))
    }

    private func isInside(path: String, directoryPath: String) -> Bool {
        path == directoryPath || path.hasPrefix(directoryPath + "/")
    }

    private func standardizedPath(_ url: URL) -> String {
        normalizedPath(url.standardizedFileURL.path(percentEncoded: false))
    }

    private func resolvedPath(_ url: URL) -> String {
        normalizedPath(url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false))
    }

    private func normalizedPath(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else {
            return path
        }
        return String(path.dropLast())
    }
}
