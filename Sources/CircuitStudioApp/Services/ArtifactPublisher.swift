import CircuiteFoundation
import Foundation

public enum ArtifactPublisherError: Error, LocalizedError, Equatable {
    case directoryCreationFailed(path: String, reason: String)
    case writeFailed(path: String, reason: String)
    case finalArtifactAlreadyExists(path: String)
    case moveFailed(source: String, destination: String, reason: String)
    case cleanupFailed(path: String, primaryReason: String, cleanupReason: String)

    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let path, let reason):
            return "Failed to create artifact directory at \(path): \(reason)"
        case .writeFailed(let path, let reason):
            return "Failed to write artifact at \(path): \(reason)"
        case .finalArtifactAlreadyExists(let path):
            return "Artifact already exists at \(path)."
        case .moveFailed(let source, let destination, let reason):
            return "Failed to publish staged artifact from \(source) to \(destination): \(reason)"
        case .cleanupFailed(let path, let primaryReason, let cleanupReason):
            return "Failed to clean staged artifact at \(path): \(cleanupReason). Original failure: \(primaryReason)"
        }
    }
}

public struct ArtifactPublisher: ArtifactPublishing {
    public let runDirectory: URL

    public init(runDirectory: URL) {
        self.runDirectory = runDirectory
    }

    public func publishJSON<T: Encodable & ArtifactPayloadValidating>(
        _ payload: T,
        id: String,
        kind: String,
        relativePath: String,
        sourcePath: String? = nil
    ) throws -> ArtifactPublicationRecord {
        try payload.validateForPersistence()
        return try publishEncodedJSON(payload, id: id, kind: kind, relativePath: relativePath, sourcePath: sourcePath)
    }

    public func publishJSON<T: Encodable>(
        _ payload: T,
        id: String,
        kind: String,
        relativePath: String,
        sourcePath: String? = nil
    ) throws -> ArtifactPublicationRecord {
        try publishEncodedJSON(payload, id: id, kind: kind, relativePath: relativePath, sourcePath: sourcePath)
    }

    public func publishData(
        _ data: Data,
        id: String,
        kind: String,
        relativePath: String,
        sourcePath: String? = nil
    ) throws -> ArtifactPublicationRecord {
        let artifactPath = try RoundTripArtifactPath(relativePath)
        let finalURL = try RoundTripArtifactResolver(runDirectory: runDirectory)
            .resolve(path: artifactPath.value, kind: kind)
            .url
        let finalPath = finalURL.path(percentEncoded: false)
        guard !FileManager.default.fileExists(atPath: finalPath) else {
            throw ArtifactPublisherError.finalArtifactAlreadyExists(path: finalPath)
        }

        let stagingDirectory = runDirectory.appending(path: ".artifact-staging")
        let stagingURL = stagingDirectory.appending(path: "\(UUID().uuidString).tmp")
        let stagingPath = stagingURL.path(percentEncoded: false)
        let finalDirectory = finalURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: finalDirectory, withIntermediateDirectories: true)
        } catch {
            throw ArtifactPublisherError.directoryCreationFailed(
                path: finalDirectory.path(percentEncoded: false),
                reason: error.localizedDescription
            )
        }

        do {
            try data.write(to: stagingURL, options: .atomic)
        } catch {
            throw ArtifactPublisherError.writeFailed(path: stagingPath, reason: error.localizedDescription)
        }

        let reference: ArtifactReference
        do {
            reference = try ArtifactReference.circuitStudioReference(
                id: id,
                kind: kind,
                relativePath: artifactPath.value,
                fileURL: stagingURL
            )
        } catch {
            try cleanupAndThrow(stagingURL, error: error)
        }

        do {
            try FileManager.default.moveItem(at: stagingURL, to: finalURL)
        } catch {
            try cleanupAndThrow(
                stagingURL,
                error: ArtifactPublisherError.moveFailed(
                    source: stagingPath,
                    destination: finalPath,
                    reason: error.localizedDescription
                )
            )
        }

        return ArtifactPublicationRecord(
            reference: reference,
            sourcePath: sourcePath
        )
    }

    private func publishEncodedJSON<T: Encodable>(
        _ payload: T,
        id: String,
        kind: String,
        relativePath: String,
        sourcePath: String?
    ) throws -> ArtifactPublicationRecord {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return try publishData(data, id: id, kind: kind, relativePath: relativePath, sourcePath: sourcePath)
    }

    private func cleanupAndThrow(_ url: URL, error: Error) throws -> Never {
        let path = url.path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch let cleanupError {
                throw ArtifactPublisherError.cleanupFailed(
                    path: path,
                    primaryReason: error.localizedDescription,
                    cleanupReason: cleanupError.localizedDescription
                )
            }
        }
        throw error
    }
}
