import CircuiteFoundation
import Foundation

public struct TapeoutEvidenceArtifact: Sendable, Hashable, Codable {
    public let publication: ArtifactPublicationRecord

    public init(publicationRecord: ArtifactPublicationRecord) {
        publication = publicationRecord
    }

    public init(timingRecord: TimingArtifactRecord) {
        publication = timingRecord.publication
    }

    public init(
        id: String,
        kind: String,
        url: URL,
        runDirectory: URL,
        sourcePath: String? = nil
    ) throws {
        let relativePath = try RoundTripArtifactResolver(runDirectory: runDirectory).relativePath(for: url)
        let reference = try ArtifactReference.circuitStudioReference(
            id: id,
            kind: kind,
            relativePath: relativePath,
            fileURL: url
        )
        publication = ArtifactPublicationRecord(
            reference: reference,
            sourcePath: sourcePath
        )
    }

    public var id: String { publication.id }
    public var kind: String { publication.kind }
    public var path: String { publication.path }
    public var status: ArtifactPublicationStatus { publication.status }
    public var reference: ArtifactReference? { publication.reference }
    public var locator: ArtifactLocator { publication.locator }
    public var sha256: String? { reference?.digest.hexadecimalValue }
    public var byteCount: Int64? { reference.map { Int64($0.byteCount) } }
    public var createdAt: Date { publication.createdAt }
    public var sourcePath: String? { publication.sourcePath }
}

extension TapeoutEvidenceArtifact: ArtifactIntegrityRecord {
    public var artifactLocator: ArtifactLocator { locator }
    public var artifactReference: ArtifactReference? { reference }
    public var artifactIsAvailable: Bool { status == .available }
}
