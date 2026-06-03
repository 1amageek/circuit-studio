import Foundation

public struct TimingArtifactManifest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1
    private static let expectedKind = "timing-artifact-manifest"

    public struct Claim: Sendable, Hashable, Codable {
        public let statement: String
        public let passed: Bool
        public let artifactIDs: [String]

        public init(statement: String, passed: Bool, artifactIDs: [String]) {
            self.statement = statement
            self.passed = passed
            self.artifactIDs = artifactIDs
        }
    }

    public let schemaVersion: Int
    public let kind: String
    public let runID: String
    public let createdAt: Date
    public let technology: TimingTechnologyContext
    public let artifacts: [TimingArtifactRecord]
    public let claims: [Claim]
    public let warnings: [String]

    public init(
        runID: String,
        createdAt: Date = Date(),
        technology: TimingTechnologyContext,
        artifacts: [TimingArtifactRecord],
        claims: [Claim] = [],
        warnings: [String] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.kind = Self.expectedKind
        self.runID = runID
        self.createdAt = createdAt
        self.technology = technology
        self.artifacts = artifacts
        self.claims = claims
        self.warnings = warnings
    }
}

extension TimingArtifactManifest {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case kind
        case runID
        case createdAt
        case technology
        case artifacts
        case claims
        case warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard decodedSchemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported timing artifact manifest schema version \(decodedSchemaVersion)."
            )
        }
        let decodedKind = try container.decode(String.self, forKey: .kind)
        guard decodedKind == Self.expectedKind else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unsupported timing artifact manifest kind \(decodedKind)."
            )
        }
        schemaVersion = decodedSchemaVersion
        kind = decodedKind
        runID = try container.decode(String.self, forKey: .runID)
        createdAt = try TimingArtifactDateCoding.decode(from: container, forKey: .createdAt)
        technology = try container.decode(TimingTechnologyContext.self, forKey: .technology)
        artifacts = try container.decode([TimingArtifactRecord].self, forKey: .artifacts)
        claims = try container.decodeIfPresent([Claim].self, forKey: .claims) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(kind, forKey: .kind)
        try container.encode(runID, forKey: .runID)
        try TimingArtifactDateCoding.encode(createdAt, to: &container, forKey: .createdAt)
        try container.encode(technology, forKey: .technology)
        try container.encode(artifacts, forKey: .artifacts)
        try container.encode(claims, forKey: .claims)
        try container.encode(warnings, forKey: .warnings)
    }
}
