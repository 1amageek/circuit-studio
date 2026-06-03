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
    public let approvals: [GateApprovalRecord]
    public let bottleneckSummary: HeadlessRoundTripService.BottleneckSummary?
    public let diagnostics: [String]
    public let warnings: [String]
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
        approvals: [GateApprovalRecord] = [],
        bottleneckSummary: HeadlessRoundTripService.BottleneckSummary?,
        diagnostics: [String],
        warnings: [String] = [],
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
        self.approvals = approvals
        self.bottleneckSummary = bottleneckSummary
        self.diagnostics = diagnostics
        self.warnings = warnings
        self.recommendations = recommendations
    }
}

extension RoundTripReviewSummary {
    private enum CodingKeys: String, CodingKey {
        case runID
        case title
        case createdAt
        case manifestPath
        case status
        case isRoundTripComplete
        case isReadyForPEX
        case stages
        case artifacts
        case externalSignoff
        case postLayoutComparison
        case approvals
        case bottleneckSummary
        case diagnostics
        case warnings
        case recommendations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            runID: try container.decode(String.self, forKey: .runID),
            title: try container.decode(String.self, forKey: .title),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            manifestPath: try container.decode(String.self, forKey: .manifestPath),
            status: try container.decode(Status.self, forKey: .status),
            isRoundTripComplete: try container.decode(Bool.self, forKey: .isRoundTripComplete),
            isReadyForPEX: try container.decode(Bool.self, forKey: .isReadyForPEX),
            stages: try container.decode([RoundTripReviewStageSummary].self, forKey: .stages),
            artifacts: try container.decode([RoundTripReviewArtifactSummary].self, forKey: .artifacts),
            externalSignoff: try container.decodeIfPresent(
                RoundTripReviewSignoffSummary.self,
                forKey: .externalSignoff
            ),
            postLayoutComparison: try container.decodeIfPresent(
                RoundTripReviewComparisonSummary.self,
                forKey: .postLayoutComparison
            ),
            approvals: try container.decodeIfPresent([GateApprovalRecord].self, forKey: .approvals) ?? [],
            bottleneckSummary: try container.decodeIfPresent(
                HeadlessRoundTripService.BottleneckSummary.self,
                forKey: .bottleneckSummary
            ),
            diagnostics: try container.decode([String].self, forKey: .diagnostics),
            warnings: try container.decodeIfPresent([String].self, forKey: .warnings) ?? [],
            recommendations: try container.decode([String].self, forKey: .recommendations)
        )
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
    public let manifestSHA256: String?
    public let manifestByteCount: Int64?
    public let actualSHA256: String?
    public let actualByteCount: Int64?
    public let integrityStatus: RoundTripArtifactIntegrityStatus

    public init(
        kind: String,
        path: String,
        sourcePath: String?,
        exists: Bool,
        isCapturedCopy: Bool,
        manifestSHA256: String? = nil,
        manifestByteCount: Int64? = nil,
        actualSHA256: String? = nil,
        actualByteCount: Int64? = nil,
        integrityStatus: RoundTripArtifactIntegrityStatus = .unresolved
    ) {
        self.kind = kind
        self.path = path
        self.sourcePath = sourcePath
        self.exists = exists
        self.isCapturedCopy = isCapturedCopy
        self.manifestSHA256 = manifestSHA256
        self.manifestByteCount = manifestByteCount
        self.actualSHA256 = actualSHA256
        self.actualByteCount = actualByteCount
        self.integrityStatus = integrityStatus
    }
}

public enum RoundTripArtifactIntegrityStatus: String, Sendable, Hashable, Codable {
    case verified
    case missingArtifact
    case unreadableArtifact
    case sha256Mismatch
    case byteCountMismatch
    case unresolved
}

extension RoundTripReviewArtifactSummary {
    private enum CodingKeys: String, CodingKey {
        case kind
        case path
        case sourcePath
        case exists
        case isCapturedCopy
        case manifestSHA256
        case manifestByteCount
        case actualSHA256
        case actualByteCount
        case integrityStatus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let exists = try container.decode(Bool.self, forKey: .exists)
        self.init(
            kind: try container.decode(String.self, forKey: .kind),
            path: try container.decode(String.self, forKey: .path),
            sourcePath: try container.decodeIfPresent(String.self, forKey: .sourcePath),
            exists: exists,
            isCapturedCopy: try container.decode(Bool.self, forKey: .isCapturedCopy),
            manifestSHA256: try container.decodeIfPresent(String.self, forKey: .manifestSHA256),
            manifestByteCount: try container.decodeIfPresent(Int64.self, forKey: .manifestByteCount),
            actualSHA256: try container.decodeIfPresent(String.self, forKey: .actualSHA256),
            actualByteCount: try container.decodeIfPresent(Int64.self, forKey: .actualByteCount),
            integrityStatus: try container.decodeIfPresent(
                RoundTripArtifactIntegrityStatus.self,
                forKey: .integrityStatus
            ) ?? (exists ? .unresolved : .missingArtifact)
        )
    }
}

public struct RoundTripReviewSignoffSummary: Sendable, Hashable, Codable {
    public let passed: Bool
    public let approved: Bool
    public let readyForPEX: Bool
    public let approvedBy: String?
    public let approvedAt: Date?
    public let approvalKind: ExternalSignoffReview.ApprovalKind?
    public let waiverIDs: [String]
    public let reports: [RoundTripReviewSignoffReportSummary]

    public init(
        passed: Bool,
        approved: Bool,
        readyForPEX: Bool,
        approvedBy: String?,
        approvedAt: Date?,
        approvalKind: ExternalSignoffReview.ApprovalKind? = nil,
        waiverIDs: [String],
        reports: [RoundTripReviewSignoffReportSummary]
    ) {
        self.passed = passed
        self.approved = approved
        self.readyForPEX = readyForPEX
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.approvalKind = approvalKind
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
    public let oscillationMetrics: [RoundTripReviewOscillationMetricSummary]
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
        oscillationMetrics: [RoundTripReviewOscillationMetricSummary] = [],
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
        self.oscillationMetrics = oscillationMetrics
        self.missingInPostLayout = missingInPostLayout
        self.addedInPostLayout = addedInPostLayout
        self.diagnostics = diagnostics
        self.gateViolations = gateViolations
    }
}

public struct RoundTripReviewVariableComparisonSummary: Sendable, Hashable, Codable {
    public let variableName: String
    public let signalDomain: PostLayoutSignalDomain?
    public let unit: String?
    public let maxAbsoluteDelta: Double
    public let maxRelativeDelta: Double

    public init(
        variableName: String,
        signalDomain: PostLayoutSignalDomain? = nil,
        unit: String? = nil,
        maxAbsoluteDelta: Double,
        maxRelativeDelta: Double
    ) {
        self.variableName = variableName
        self.signalDomain = signalDomain
        self.unit = unit
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
    }
}

public struct RoundTripReviewOscillationMetricSummary: Sendable, Hashable, Codable {
    public let variableName: String
    public let preLayoutTransitionCount: Int?
    public let postLayoutTransitionCount: Int?
    public let preLayoutAmplitude: Double?
    public let postLayoutAmplitude: Double?
    public let preLayoutFrequency: Double?
    public let postLayoutFrequency: Double?
    public let frequencyRelativeDelta: Double?
    public let periodRelativeDelta: Double?
    public let dutyCycleDelta: Double?
    public let diagnostics: [String]

    public init(
        variableName: String,
        preLayoutTransitionCount: Int?,
        postLayoutTransitionCount: Int?,
        preLayoutAmplitude: Double?,
        postLayoutAmplitude: Double?,
        preLayoutFrequency: Double?,
        postLayoutFrequency: Double?,
        frequencyRelativeDelta: Double?,
        periodRelativeDelta: Double?,
        dutyCycleDelta: Double?,
        diagnostics: [String]
    ) {
        self.variableName = variableName
        self.preLayoutTransitionCount = preLayoutTransitionCount
        self.postLayoutTransitionCount = postLayoutTransitionCount
        self.preLayoutAmplitude = preLayoutAmplitude
        self.postLayoutAmplitude = postLayoutAmplitude
        self.preLayoutFrequency = preLayoutFrequency
        self.postLayoutFrequency = postLayoutFrequency
        self.frequencyRelativeDelta = frequencyRelativeDelta
        self.periodRelativeDelta = periodRelativeDelta
        self.dutyCycleDelta = dutyCycleDelta
        self.diagnostics = diagnostics
    }
}
