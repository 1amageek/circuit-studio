import Foundation

public struct ArtifactSetManifest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1
    private static let expectedKind = "artifact-set-manifest"

    public let schemaVersion: Int
    public let kind: String
    public let runID: String
    public let artifactSetKind: String
    public let createdAt: Date
    public let records: [ArtifactPublicationRecord]
    public let warnings: [String]

    public init(
        runID: String,
        artifactSetKind: String,
        createdAt: Date = Date(),
        records: [ArtifactPublicationRecord],
        warnings: [String] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.kind = Self.expectedKind
        self.runID = runID
        self.artifactSetKind = artifactSetKind
        self.createdAt = createdAt
        self.records = records
        self.warnings = warnings
    }
}

extension ArtifactSetManifest {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case kind
        case runID
        case artifactSetKind
        case createdAt
        case records
        case warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard decodedSchemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported artifact set manifest schema version \(decodedSchemaVersion)."
            )
        }
        let decodedKind = try container.decode(String.self, forKey: .kind)
        guard decodedKind == Self.expectedKind else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unsupported artifact set manifest kind \(decodedKind)."
            )
        }
        schemaVersion = decodedSchemaVersion
        kind = decodedKind
        runID = try container.decode(String.self, forKey: .runID)
        artifactSetKind = try container.decode(String.self, forKey: .artifactSetKind)
        createdAt = try TimingArtifactDateCoding.decode(from: container, forKey: .createdAt)
        records = try container.decode([ArtifactPublicationRecord].self, forKey: .records)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(kind, forKey: .kind)
        try container.encode(runID, forKey: .runID)
        try container.encode(artifactSetKind, forKey: .artifactSetKind)
        try TimingArtifactDateCoding.encode(createdAt, to: &container, forKey: .createdAt)
        try container.encode(records, forKey: .records)
        try container.encode(warnings, forKey: .warnings)
    }
}
