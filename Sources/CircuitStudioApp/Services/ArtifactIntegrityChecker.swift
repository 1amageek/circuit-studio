import Foundation

public enum ArtifactIntegrityError: Error, LocalizedError, Equatable {
    case unavailableArtifact(kind: String, path: String)
    case missingSHA256(kind: String, path: String)
    case invalidSHA256(kind: String, path: String, value: String)
    case missingByteCount(kind: String, path: String)
    case negativeByteCount(kind: String, path: String, value: Int64)
    case missingArtifact(kind: String, path: String)
    case unreadableArtifact(kind: String, path: String, reason: String)
    case byteCountMismatch(kind: String, path: String, expected: Int64, actual: Int64)
    case sha256Mismatch(kind: String, path: String, expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .unavailableArtifact(let kind, let path):
            return "Artifact is not available: \(kind) at \(path)"
        case .missingSHA256(let kind, let path):
            return "Artifact is missing sha256: \(kind) at \(path)"
        case .invalidSHA256(let kind, let path, let value):
            return "Artifact has invalid sha256 '\(value)': \(kind) at \(path)"
        case .missingByteCount(let kind, let path):
            return "Artifact is missing byteCount: \(kind) at \(path)"
        case .negativeByteCount(let kind, let path, let value):
            return "Artifact has negative byteCount \(value): \(kind) at \(path)"
        case .missingArtifact(let kind, let path):
            return "Artifact is missing: \(kind) at \(path)"
        case .unreadableArtifact(let kind, let path, let reason):
            return "Artifact is unreadable: \(kind) at \(path): \(reason)"
        case .byteCountMismatch(let kind, let path, let expected, let actual):
            return "Artifact byte count mismatch: \(kind) at \(path) expected \(expected), got \(actual)"
        case .sha256Mismatch(let kind, let path, let expected, let actual):
            return "Artifact SHA-256 mismatch: \(kind) at \(path) expected \(expected), got \(actual)"
        }
    }
}

public struct VerifiedArtifact: Sendable, Hashable {
    public let kind: String
    public let path: String
    public let url: URL
    public let digest: RoundTripArtifactDigest
    public let data: Data

    public init(kind: String, path: String, url: URL, digest: RoundTripArtifactDigest, data: Data) {
        self.kind = kind
        self.path = path
        self.url = url
        self.digest = digest
        self.data = data
    }
}

public struct ArtifactIntegrityChecker: ArtifactIntegrityChecking {
    public init() {}

    public func verifiedData(
        for record: any ArtifactIntegrityRecord,
        in runDirectory: URL
    ) throws -> Data {
        try verifiedArtifact(for: record, in: runDirectory).data
    }

    public func verifiedArtifact(
        for record: any ArtifactIntegrityRecord,
        in runDirectory: URL
    ) throws -> VerifiedArtifact {
        guard record.artifactIsAvailable else {
            throw ArtifactIntegrityError.unavailableArtifact(kind: record.artifactKind, path: record.artifactPath)
        }
        guard let expectedSHA256 = record.artifactSHA256 else {
            throw ArtifactIntegrityError.missingSHA256(kind: record.artifactKind, path: record.artifactPath)
        }
        guard RoundTripArtifactDigest.isValidSHA256(expectedSHA256) else {
            throw ArtifactIntegrityError.invalidSHA256(
                kind: record.artifactKind,
                path: record.artifactPath,
                value: expectedSHA256
            )
        }
        guard let expectedByteCount = record.artifactByteCount else {
            throw ArtifactIntegrityError.missingByteCount(kind: record.artifactKind, path: record.artifactPath)
        }
        guard expectedByteCount >= 0 else {
            throw ArtifactIntegrityError.negativeByteCount(
                kind: record.artifactKind,
                path: record.artifactPath,
                value: expectedByteCount
            )
        }

        let url = try RoundTripArtifactResolver(runDirectory: runDirectory)
            .resolve(path: record.artifactPath, kind: record.artifactKind)
            .url
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            throw ArtifactIntegrityError.missingArtifact(kind: record.artifactKind, path: path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ArtifactIntegrityError.unreadableArtifact(
                kind: record.artifactKind,
                path: path,
                reason: error.localizedDescription
            )
        }

        let actualDigest = RoundTripArtifactDigest.compute(data: data)
        guard actualDigest.byteCount == expectedByteCount else {
            throw ArtifactIntegrityError.byteCountMismatch(
                kind: record.artifactKind,
                path: record.artifactPath,
                expected: expectedByteCount,
                actual: actualDigest.byteCount
            )
        }
        guard actualDigest.sha256 == expectedSHA256 else {
            throw ArtifactIntegrityError.sha256Mismatch(
                kind: record.artifactKind,
                path: record.artifactPath,
                expected: expectedSHA256,
                actual: actualDigest.sha256
            )
        }

        return VerifiedArtifact(
            kind: record.artifactKind,
            path: record.artifactPath,
            url: url,
            digest: actualDigest,
            data: data
        )
    }

    public func decodeVerifiedJSON<T: Decodable>(
        _ type: T.Type,
        for record: any ArtifactIntegrityRecord,
        in runDirectory: URL
    ) throws -> T {
        let data = try verifiedData(for: record, in: runDirectory)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(type, from: data)
        if let validating = decoded as? any ArtifactPayloadValidating {
            try validating.validateForPersistence()
        }
        return decoded
    }
}
