import CircuiteFoundation
import Foundation

public enum ArtifactIntegrityError: Error, LocalizedError, Equatable {
    case unavailableArtifact(kind: String, path: String)
    case missingReference(kind: String, path: String)
    case integrityFailure(kind: String, path: String, issues: [ArtifactIntegrityIssue])
    case unreadableArtifact(kind: String, path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .unavailableArtifact(let kind, let path):
            return "Artifact is not available: \(kind) at \(path)"
        case .missingReference(let kind, let path):
            return "Available artifact is missing its ArtifactReference: \(kind) at \(path)"
        case .integrityFailure(let kind, let path, let issues):
            let codes = issues.map(\.code.rawValue).joined(separator: ", ")
            return "Artifact integrity verification failed: \(kind) at \(path): \(codes)"
        case .unreadableArtifact(let kind, let path, let reason):
            return "Artifact is unreadable: \(kind) at \(path): \(reason)"
        }
    }
}

public struct VerifiedArtifact: Sendable, Hashable {
    public let reference: ArtifactReference
    public let url: URL
    public let data: Data

    public init(reference: ArtifactReference, url: URL, data: Data) {
        self.reference = reference
        self.url = url
        self.data = data
    }
}

public struct ArtifactIntegrityChecker: ArtifactIntegrityChecking {
    private let verifier: any ArtifactVerifying

    public init(verifier: any ArtifactVerifying = LocalArtifactVerifier()) {
        self.verifier = verifier
    }

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
        let locator = record.artifactLocator
        let kind = locator.kind.rawValue
        let path = locator.location.value
        guard record.artifactIsAvailable else {
            throw ArtifactIntegrityError.unavailableArtifact(kind: kind, path: path)
        }
        guard let reference = record.artifactReference else {
            throw ArtifactIntegrityError.missingReference(kind: kind, path: path)
        }

        let integrity = verifier.verify(reference, relativeTo: runDirectory)
        guard integrity.isVerified else {
            throw ArtifactIntegrityError.integrityFailure(
                kind: kind,
                path: path,
                issues: integrity.issues
            )
        }

        let url = try reference.locator.location.resolvedFileURL(relativeTo: runDirectory)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ArtifactIntegrityError.unreadableArtifact(
                kind: kind,
                path: path,
                reason: error.localizedDescription
            )
        }
        return VerifiedArtifact(reference: reference, url: url, data: data)
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
