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
        schemaVersion: Int = Self.currentSchemaVersion,
        kind: String = "timing-validation-report",
        scope: TimingValidationScope,
        runID: String? = nil,
        createdAt: Date = Date(),
        designName: String? = nil,
        sourceArtifacts: [String],
        comparisons: [TimingValidationComparison],
        status: TimingRunStatus,
        warnings: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
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
