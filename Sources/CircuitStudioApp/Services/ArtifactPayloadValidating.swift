import Foundation

public protocol ArtifactPayloadValidating: Sendable {
    func validateForPersistence() throws
}

public protocol ArtifactEnvelopeValidating: Sendable {
    static var currentSchemaVersion: Int { get }
    static var artifactKind: String { get }
}

public protocol ArtifactPublishing: Sendable {
    func publishData(
        _ data: Data,
        id: String,
        kind: String,
        relativePath: String,
        sourcePath: String?
    ) throws -> ArtifactPublicationRecord
}

public protocol ArtifactIntegrityChecking: Sendable {
    func verifiedData(
        for record: any ArtifactIntegrityRecord,
        in runDirectory: URL
    ) throws -> Data
}
