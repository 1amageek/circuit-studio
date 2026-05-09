import Foundation
import CircuitStudioCore

public struct RoundTripReviewSummary: Sendable, Hashable, Codable {
    public enum Status: String, Sendable, Hashable, Codable {
        case passed
        case failed
        case incomplete
    }

    public let runID: String
    public let title: String
    public let createdAt: Date
    public let manifestPath: String
    public let status: Status
    public let isRoundTripComplete: Bool
    public let isReadyForPEX: Bool
    public let stages: [RoundTripReviewStageSummary]
    public let artifacts: [RoundTripReviewArtifactSummary]
    public let externalSignoff: RoundTripReviewSignoffSummary?
    public let postLayoutComparison: RoundTripReviewComparisonSummary?
    public let bottleneckSummary: HeadlessRoundTripService.BottleneckSummary?
    public let diagnostics: [String]
    public let recommendations: [String]

    public init(
        runID: String,
        title: String,
        createdAt: Date,
        manifestPath: String,
        status: Status,
        isRoundTripComplete: Bool,
        isReadyForPEX: Bool,
        stages: [RoundTripReviewStageSummary],
        artifacts: [RoundTripReviewArtifactSummary],
        externalSignoff: RoundTripReviewSignoffSummary?,
        postLayoutComparison: RoundTripReviewComparisonSummary?,
        bottleneckSummary: HeadlessRoundTripService.BottleneckSummary?,
        diagnostics: [String],
        recommendations: [String]
    ) {
        self.runID = runID
        self.title = title
        self.createdAt = createdAt
        self.manifestPath = manifestPath
        self.status = status
        self.isRoundTripComplete = isRoundTripComplete
        self.isReadyForPEX = isReadyForPEX
        self.stages = stages
        self.artifacts = artifacts
        self.externalSignoff = externalSignoff
        self.postLayoutComparison = postLayoutComparison
        self.bottleneckSummary = bottleneckSummary
        self.diagnostics = diagnostics
        self.recommendations = recommendations
    }
}

public struct RoundTripReviewStageSummary: Sendable, Hashable, Codable {
    public let name: String
    public let status: HeadlessRoundTripService.Stage.Status
    public let message: String?
    public let durationSeconds: Double?

    public init(
        name: String,
        status: HeadlessRoundTripService.Stage.Status,
        message: String?,
        durationSeconds: Double?
    ) {
        self.name = name
        self.status = status
        self.message = message
        self.durationSeconds = durationSeconds
    }
}

public struct RoundTripReviewArtifactSummary: Sendable, Hashable, Codable {
    public let kind: String
    public let path: String
    public let sourcePath: String?
    public let exists: Bool
    public let isCapturedCopy: Bool

    public init(
        kind: String,
        path: String,
        sourcePath: String?,
        exists: Bool,
        isCapturedCopy: Bool
    ) {
        self.kind = kind
        self.path = path
        self.sourcePath = sourcePath
        self.exists = exists
        self.isCapturedCopy = isCapturedCopy
    }
}

public struct RoundTripReviewSignoffSummary: Sendable, Hashable, Codable {
    public let passed: Bool
    public let approved: Bool
    public let readyForPEX: Bool
    public let approvedBy: String?
    public let approvedAt: Date?
    public let waiverIDs: [String]
    public let reports: [RoundTripReviewSignoffReportSummary]

    public init(
        passed: Bool,
        approved: Bool,
        readyForPEX: Bool,
        approvedBy: String?,
        approvedAt: Date?,
        waiverIDs: [String],
        reports: [RoundTripReviewSignoffReportSummary]
    ) {
        self.passed = passed
        self.approved = approved
        self.readyForPEX = readyForPEX
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.waiverIDs = waiverIDs
        self.reports = reports
    }
}

public struct RoundTripReviewSignoffReportSummary: Sendable, Hashable, Codable {
    public let kind: ExternalSignoffToolReport.Kind
    public let toolName: String
    public let passed: Bool
    public let logPath: String
    public let diagnosticCount: Int
    public let errorCount: Int
    public let warningCount: Int

    public init(
        kind: ExternalSignoffToolReport.Kind,
        toolName: String,
        passed: Bool,
        logPath: String,
        diagnosticCount: Int,
        errorCount: Int,
        warningCount: Int
    ) {
        self.kind = kind
        self.toolName = toolName
        self.passed = passed
        self.logPath = logPath
        self.diagnosticCount = diagnosticCount
        self.errorCount = errorCount
        self.warningCount = warningCount
    }
}

public struct RoundTripReviewComparisonSummary: Sendable, Hashable, Codable {
    public let status: String
    public let gateStatus: String
    public let comparedPointCount: Int
    public let maxAbsoluteDelta: Double
    public let maxRelativeDelta: Double
    public let comparisonLimits: PostLayoutComparisonLimits?
    public let variableSummaries: [RoundTripReviewVariableComparisonSummary]
    public let missingInPostLayout: [String]
    public let addedInPostLayout: [String]
    public let diagnostics: [String]
    public let gateViolations: [String]

    public init(
        status: String,
        gateStatus: String,
        comparedPointCount: Int,
        maxAbsoluteDelta: Double,
        maxRelativeDelta: Double,
        comparisonLimits: PostLayoutComparisonLimits?,
        variableSummaries: [RoundTripReviewVariableComparisonSummary],
        missingInPostLayout: [String],
        addedInPostLayout: [String],
        diagnostics: [String],
        gateViolations: [String]
    ) {
        self.status = status
        self.gateStatus = gateStatus
        self.comparedPointCount = comparedPointCount
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
        self.comparisonLimits = comparisonLimits
        self.variableSummaries = variableSummaries
        self.missingInPostLayout = missingInPostLayout
        self.addedInPostLayout = addedInPostLayout
        self.diagnostics = diagnostics
        self.gateViolations = gateViolations
    }
}

public struct RoundTripReviewVariableComparisonSummary: Sendable, Hashable, Codable {
    public let variableName: String
    public let maxAbsoluteDelta: Double
    public let maxRelativeDelta: Double

    public init(variableName: String, maxAbsoluteDelta: Double, maxRelativeDelta: Double) {
        self.variableName = variableName
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
    }
}
