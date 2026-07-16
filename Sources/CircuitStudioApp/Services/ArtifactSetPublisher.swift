import CircuiteFoundation
import Foundation

public enum ArtifactSetPublisherError: Error, LocalizedError, Equatable {
    case duplicateArtifactID(String)
    case duplicateArtifactPath(path: String, artifactID: String, existingArtifactID: String)
    case finalArtifactAlreadyExists(path: String)
    case missingPublishedRecord(String)
    case preparedRecordMismatch(artifactID: String, reason: String)
    case directoryCreationFailed(path: String, reason: String)
    case writeFailed(path: String, reason: String)
    case moveFailed(source: String, destination: String, reason: String)
    case cleanupFailed(path: String, reason: String)
    case rollbackFailed(primaryReason: String, cleanupFailures: [String])

    public var errorDescription: String? {
        switch self {
        case .duplicateArtifactID(let id):
            return "Artifact id '\(id)' is declared more than once in the artifact set."
        case .duplicateArtifactPath(let path, let artifactID, let existingArtifactID):
            return "Artifact '\(artifactID)' writes to '\(path)', already used by artifact '\(existingArtifactID)'."
        case .finalArtifactAlreadyExists(let path):
            return "Artifact already exists at \(path)."
        case .missingPublishedRecord(let id):
            return "Artifact set did not publish required record '\(id)'."
        case .preparedRecordMismatch(let artifactID, let reason):
            return "Prepared artifact record '\(artifactID)' does not match its staged payload: \(reason)"
        case .directoryCreationFailed(let path, let reason):
            return "Failed to create artifact set directory at \(path): \(reason)"
        case .writeFailed(let path, let reason):
            return "Failed to write staged artifact at \(path): \(reason)"
        case .moveFailed(let source, let destination, let reason):
            return "Failed to publish staged artifact from \(source) to \(destination): \(reason)"
        case .cleanupFailed(let path, let reason):
            return "Failed to clean artifact set staging directory at \(path): \(reason)"
        case .rollbackFailed(let primaryReason, let cleanupFailures):
            return "Failed to roll back artifact set after \(primaryReason): \(cleanupFailures.joined(separator: "; "))"
        }
    }
}

public struct ArtifactSetPublisher: Sendable {
    public struct Item: Sendable, Hashable {
        public let id: String
        public let kind: String
        public let relativePath: String
        public let data: Data
        public let sourcePath: String?

        public init(
            id: String,
            kind: String,
            relativePath: String,
            data: Data,
            sourcePath: String? = nil
        ) {
            self.id = id
            self.kind = kind
            self.relativePath = relativePath
            self.data = data
            self.sourcePath = sourcePath
        }
    }

    public struct PreparedItem: Sendable, Hashable {
        public let item: Item
        public let record: ArtifactPublicationRecord

        init(item: Item, record: ArtifactPublicationRecord) {
            self.item = item
            self.record = record
        }
    }

    private struct PlannedMove: Sendable {
        let stagingURL: URL
        let finalURL: URL
        let record: ArtifactPublicationRecord
    }

    public let runDirectory: URL

    public init(runDirectory: URL) {
        self.runDirectory = runDirectory
    }

    public static func jsonItem<T: Encodable & ArtifactPayloadValidating>(
        _ payload: T,
        id: String,
        kind: String,
        relativePath: String,
        sourcePath: String? = nil
    ) throws -> Item {
        try payload.validateForPersistence()
        return try encodedJSONItem(payload, id: id, kind: kind, relativePath: relativePath, sourcePath: sourcePath)
    }

    public static func jsonItem<T: Encodable>(
        _ payload: T,
        id: String,
        kind: String,
        relativePath: String,
        sourcePath: String? = nil
    ) throws -> Item {
        try encodedJSONItem(payload, id: id, kind: kind, relativePath: relativePath, sourcePath: sourcePath)
    }

    public func prepare(_ items: [Item], createdAt: Date = Date()) throws -> [PreparedItem] {
        try validateUniqueItems(items)
        return try items.map { item in
            let artifactPath = try RoundTripArtifactPath(item.relativePath)
            let reference = try ArtifactReference.circuitStudioReference(
                id: item.id,
                kind: item.kind,
                relativePath: artifactPath.value,
                data: item.data
            )
            return PreparedItem(
                item: Item(
                    id: item.id,
                    kind: item.kind,
                    relativePath: artifactPath.value,
                    data: item.data,
                    sourcePath: item.sourcePath
                ),
                record: ArtifactPublicationRecord(
                    reference: reference,
                    createdAt: createdAt,
                    sourcePath: item.sourcePath
                )
            )
        }
    }

    public func publish(_ items: [Item]) throws -> [ArtifactPublicationRecord] {
        try publish(prepare(items))
    }

    public func publish(_ preparedItems: [PreparedItem]) throws -> [ArtifactPublicationRecord] {
        try validateUniquePreparedItems(preparedItems)
        guard !preparedItems.isEmpty else { return [] }

        let resolver = RoundTripArtifactResolver(runDirectory: runDirectory)
        let stagingRoot = runDirectory.appending(path: ".artifact-set-staging/\(UUID().uuidString)")
        var plannedMoves: [PlannedMove] = []
        for prepared in preparedItems {
            let finalURL = try resolver.resolve(path: prepared.record.path, kind: prepared.record.kind).url
            let finalPath = finalURL.path(percentEncoded: false)
            guard !FileManager.default.fileExists(atPath: finalPath) else {
                throw ArtifactSetPublisherError.finalArtifactAlreadyExists(path: finalPath)
            }
            plannedMoves.append(PlannedMove(
                stagingURL: stagingRoot.appending(path: prepared.record.path),
                finalURL: finalURL,
                record: prepared.record
            ))
        }

        var movedFinalURLs: [URL] = []
        do {
            try createDirectory(stagingRoot)
            for (prepared, move) in zip(preparedItems, plannedMoves) {
                let stagingDirectory = move.stagingURL.deletingLastPathComponent()
                try createDirectory(stagingDirectory)
                do {
                    try prepared.item.data.write(to: move.stagingURL, options: .atomic)
                } catch {
                    throw ArtifactSetPublisherError.writeFailed(
                        path: move.stagingURL.path(percentEncoded: false),
                        reason: error.localizedDescription
                    )
                }
            }

            for move in plannedMoves {
                let finalDirectory = move.finalURL.deletingLastPathComponent()
                try createDirectory(finalDirectory)
                do {
                    try FileManager.default.moveItem(at: move.stagingURL, to: move.finalURL)
                    movedFinalURLs.append(move.finalURL)
                } catch {
                    throw ArtifactSetPublisherError.moveFailed(
                        source: move.stagingURL.path(percentEncoded: false),
                        destination: move.finalURL.path(percentEncoded: false),
                        reason: error.localizedDescription
                    )
                }
            }

            try removeStagingRoot(stagingRoot)
            return plannedMoves.map(\.record)
        } catch {
            try rollback(movedFinalURLs: movedFinalURLs, stagingRoot: stagingRoot, primaryError: error)
        }
    }

    private static func encodedJSONItem<T: Encodable>(
        _ payload: T,
        id: String,
        kind: String,
        relativePath: String,
        sourcePath: String?
    ) throws -> Item {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return Item(
            id: id,
            kind: kind,
            relativePath: relativePath,
            data: data,
            sourcePath: sourcePath
        )
    }

    private func validateUniqueItems(_ items: [Item]) throws {
        var artifactIDByPath: [String: String] = [:]
        var seenIDs = Set<String>()
        for item in items {
            guard seenIDs.insert(item.id).inserted else {
                throw ArtifactSetPublisherError.duplicateArtifactID(item.id)
            }
            let artifactPath = try RoundTripArtifactPath(item.relativePath)
            let path = artifactPath.value
            if let existingID = artifactIDByPath[path] {
                throw ArtifactSetPublisherError.duplicateArtifactPath(
                    path: path,
                    artifactID: item.id,
                    existingArtifactID: existingID
                )
            }
            artifactIDByPath[path] = item.id
        }
    }

    private func validateUniquePreparedItems(_ items: [PreparedItem]) throws {
        var artifactIDByPath: [String: String] = [:]
        var seenIDs = Set<String>()
        for prepared in items {
            try validatePreparedRecordMatchesItem(prepared)
            guard seenIDs.insert(prepared.record.id).inserted else {
                throw ArtifactSetPublisherError.duplicateArtifactID(prepared.record.id)
            }
            if let existingID = artifactIDByPath[prepared.record.path] {
                throw ArtifactSetPublisherError.duplicateArtifactPath(
                    path: prepared.record.path,
                    artifactID: prepared.record.id,
                    existingArtifactID: existingID
                )
            }
            artifactIDByPath[prepared.record.path] = prepared.record.id
        }
    }

    private func validatePreparedRecordMatchesItem(_ prepared: PreparedItem) throws {
        let item = prepared.item
        let record = prepared.record
        let canonicalPath = try RoundTripArtifactPath(item.relativePath).value
        let expectedReference = try ArtifactReference.circuitStudioReference(
            id: item.id,
            kind: item.kind,
            relativePath: canonicalPath,
            data: item.data
        )
        let checks: [(Bool, String)] = [
            (record.id == item.id, "record id '\(record.id)' differs from item id '\(item.id)'"),
            (record.kind == item.kind, "record kind '\(record.kind)' differs from item kind '\(item.kind)'"),
            (record.path == canonicalPath, "record path '\(record.path)' differs from item path '\(canonicalPath)'"),
            (record.status == .available, "record status must be available"),
            (record.reference == expectedReference, "record ArtifactReference does not match payload bytes"),
            (record.sourcePath == item.sourcePath, "record sourcePath differs from item sourcePath"),
        ]
        if let failed = checks.first(where: { !$0.0 }) {
            throw ArtifactSetPublisherError.preparedRecordMismatch(
                artifactID: record.id,
                reason: failed.1
            )
        }
    }

    private func createDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw ArtifactSetPublisherError.directoryCreationFailed(
                path: url.path(percentEncoded: false),
                reason: error.localizedDescription
            )
        }
    }

    private func removeStagingRoot(_ stagingRoot: URL) throws {
        let path = stagingRoot.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return }
        do {
            try FileManager.default.removeItem(at: stagingRoot)
        } catch {
            throw ArtifactSetPublisherError.cleanupFailed(path: path, reason: error.localizedDescription)
        }
    }

    private func rollback(
        movedFinalURLs: [URL],
        stagingRoot: URL,
        primaryError: Error
    ) throws -> Never {
        var cleanupFailures: [String] = []
        for url in movedFinalURLs.reversed() {
            let path = url.path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                cleanupFailures.append("\(path): \(error.localizedDescription)")
            }
        }

        let stagingPath = stagingRoot.path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: stagingPath) {
            do {
                try FileManager.default.removeItem(at: stagingRoot)
            } catch {
                cleanupFailures.append("\(stagingPath): \(error.localizedDescription)")
            }
        }

        guard cleanupFailures.isEmpty else {
            throw ArtifactSetPublisherError.rollbackFailed(
                primaryReason: primaryError.localizedDescription,
                cleanupFailures: cleanupFailures
            )
        }
        throw primaryError
    }
}
