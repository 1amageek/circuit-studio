import Foundation

public enum TimingValidationScope: String, Sendable, Hashable, Codable {
    case combinationalPath = "combinational-path"
    case sequentialCell = "sequential-cell"
    case clockedPath = "clocked-path"
}

public struct TimingValidationComparison: Sendable, Hashable, Codable {
    public let id: String
    public let metric: String
    public let predictedSeconds: Double
    public let measuredSeconds: Double
    public let absoluteErrorSeconds: Double
    public let relativeError: Double
    public let tolerance: Double
    public let passed: Bool
    public let artifactIDs: [String]

    public init(
        id: String,
        metric: String,
        predictedSeconds: Double,
        measuredSeconds: Double,
        absoluteErrorSeconds: Double,
        relativeError: Double,
        tolerance: Double,
        passed: Bool,
        artifactIDs: [String]
    ) {
        self.id = id
        self.metric = metric
        self.predictedSeconds = predictedSeconds
        self.measuredSeconds = measuredSeconds
        self.absoluteErrorSeconds = absoluteErrorSeconds
        self.relativeError = relativeError
        self.tolerance = tolerance
        self.passed = passed
        self.artifactIDs = artifactIDs
    }
}

public struct TimingValidationReport: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1
    private static let expectedKind = "timing-validation-report"

    public let schemaVersion: Int
    public let kind: String
    public let scope: TimingValidationScope
    public let runID: String?
    public let createdAt: Date
    public let designName: String?
    public let sourceArtifacts: [String]
    public let comparisons: [TimingValidationComparison]
    public let status: TimingRunStatus
    public let warnings: [String]

    public init(
        scope: TimingValidationScope,
        runID: String? = nil,
        createdAt: Date = Date(),
        designName: String? = nil,
        sourceArtifacts: [String],
        comparisons: [TimingValidationComparison],
        status: TimingRunStatus,
        warnings: [String] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.kind = Self.expectedKind
        self.scope = scope
        self.runID = runID
        self.createdAt = createdAt
        self.designName = designName
        self.sourceArtifacts = sourceArtifacts
        self.comparisons = comparisons
        self.status = status
        self.warnings = warnings
    }
}

extension TimingValidationReport {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case kind
        case scope
        case runID
        case createdAt
        case designName
        case sourceArtifacts
        case comparisons
        case status
        case warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard decodedSchemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported timing validation report schema version \(decodedSchemaVersion)."
            )
        }
        let decodedKind = try container.decode(String.self, forKey: .kind)
        guard decodedKind == Self.expectedKind else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unsupported timing validation report kind \(decodedKind)."
            )
        }
        schemaVersion = decodedSchemaVersion
        kind = decodedKind
        scope = try container.decode(TimingValidationScope.self, forKey: .scope)
        runID = try container.decodeIfPresent(String.self, forKey: .runID)
        createdAt = try TimingArtifactDateCoding.decode(from: container, forKey: .createdAt)
        designName = try container.decodeIfPresent(String.self, forKey: .designName)
        sourceArtifacts = try container.decode([String].self, forKey: .sourceArtifacts)
        comparisons = try container.decode([TimingValidationComparison].self, forKey: .comparisons)
        status = try container.decode(TimingRunStatus.self, forKey: .status)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(kind, forKey: .kind)
        try container.encode(scope, forKey: .scope)
        try container.encodeIfPresent(runID, forKey: .runID)
        try TimingArtifactDateCoding.encode(createdAt, to: &container, forKey: .createdAt)
        try container.encodeIfPresent(designName, forKey: .designName)
        try container.encode(sourceArtifacts, forKey: .sourceArtifacts)
        try container.encode(comparisons, forKey: .comparisons)
        try container.encode(status, forKey: .status)
        try container.encode(warnings, forKey: .warnings)
    }
}
