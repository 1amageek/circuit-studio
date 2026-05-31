import Foundation

public struct TimingArtifactManifest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

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
        schemaVersion: Int = Self.currentSchemaVersion,
        kind: String = "timing-artifact-manifest",
        runID: String,
        createdAt: Date = Date(),
        technology: TimingTechnologyContext,
        artifacts: [TimingArtifactRecord],
        claims: [Claim] = [],
        warnings: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.runID = runID
        self.createdAt = createdAt
        self.technology = technology
        self.artifacts = artifacts
        self.claims = claims
        self.warnings = warnings
    }
}
