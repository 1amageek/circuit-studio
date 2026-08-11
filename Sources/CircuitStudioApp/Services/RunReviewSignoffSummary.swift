import DesignFlowKernel
import Foundation
import Xcircuite

public struct RunReviewSignoffSummary: Sendable, Hashable {
    public let cards: [RunReviewSignoffCard]
    public let repairCandidateCycles: [RunReviewSignoffRepairCandidateCycleHistoryItem]
    public let decodeIssues: [RunReviewArtifactDecodeIssue]

    public init(
        cards: [RunReviewSignoffCard],
        repairCandidateCycles: [RunReviewSignoffRepairCandidateCycleHistoryItem] = [],
        decodeIssues: [RunReviewArtifactDecodeIssue] = []
    ) {
        self.cards = cards
        self.repairCandidateCycles = repairCandidateCycles
        self.decodeIssues = decodeIssues
    }

    public var hasContent: Bool {
        !cards.isEmpty || !repairCandidateCycles.isEmpty || !decodeIssues.isEmpty
    }

    public var repairCandidateCycleHistorySummary: RunReviewSignoffRepairCandidateCycleHistorySummary {
        RunReviewSignoffRepairCandidateCycleHistorySummary(cycles: repairCandidateCycles)
    }
}

public struct RunReviewSignoffCard: Sendable, Hashable, Identifiable {
    public let domain: String
    public let title: String
    public let status: String
    public let passed: Bool?
    public let stageID: String?
    public let artifact: FlowRunReviewArtifact
    public let relatedArtifacts: [FlowRunReviewArtifact]
    public let primaryMetrics: [RunReviewSignoffMetric]
    public let detailSections: [RunReviewSignoffDetailSection]
    public let evaluationEvidence: [RunReviewArtifactEvaluationEvidence]
    public let issues: [RunReviewSignoffIssue]

    public var id: String {
        [
            artifact.binding.logicalID,
            domain,
            title,
        ].joined(separator: "::")
    }

    public init(
        domain: String,
        title: String,
        status: String,
        passed: Bool?,
        stageID: String?,
        artifact: FlowRunReviewArtifact,
        relatedArtifacts: [FlowRunReviewArtifact] = [],
        primaryMetrics: [RunReviewSignoffMetric],
        detailSections: [RunReviewSignoffDetailSection] = [],
        evaluationEvidence: [RunReviewArtifactEvaluationEvidence] = [],
        issues: [RunReviewSignoffIssue] = []
    ) {
        self.domain = domain
        self.title = title
        self.status = status
        self.passed = passed
        self.stageID = stageID
        self.artifact = artifact
        self.relatedArtifacts = relatedArtifacts
        self.primaryMetrics = primaryMetrics
        self.detailSections = detailSections
        self.evaluationEvidence = evaluationEvidence
        self.issues = issues
    }
}

public struct RunReviewArtifactEvaluationEvidence: Sendable, Hashable {
    public let envelopeArtifact: FlowRunReviewArtifact
    public let artifactID: String
    public let role: String
    public let evaluationStatus: String?
    public let evaluationSummary: String?
    public let observedChannelCount: Int
    public let missingChannelIDs: [String]
    public let uncalibratedChannelIDs: [String]
    public let failedChannelIDs: [String]
    public let feedbackSignals: [RunReviewArtifactEvaluationFeedbackSignal]

    public init(
        envelopeArtifact: FlowRunReviewArtifact,
        artifactID: String,
        role: String,
        evaluationStatus: String?,
        evaluationSummary: String?,
        observedChannelCount: Int,
        missingChannelIDs: [String],
        uncalibratedChannelIDs: [String],
        failedChannelIDs: [String],
        feedbackSignals: [RunReviewArtifactEvaluationFeedbackSignal]
    ) {
        self.envelopeArtifact = envelopeArtifact
        self.artifactID = artifactID
        self.role = role
        self.evaluationStatus = evaluationStatus
        self.evaluationSummary = evaluationSummary
        self.observedChannelCount = observedChannelCount
        self.missingChannelIDs = missingChannelIDs
        self.uncalibratedChannelIDs = uncalibratedChannelIDs
        self.failedChannelIDs = failedChannelIDs
        self.feedbackSignals = feedbackSignals
    }
}

public struct RunReviewArtifactEvaluationFeedbackSignal: Sendable, Hashable {
    public let signalID: String
    public let severity: String
    public let routingLevel: String
    public let channelID: String?
    public let summary: String
    public let suggestedActions: [String]

    public init(
        signalID: String,
        severity: String,
        routingLevel: String,
        channelID: String?,
        summary: String,
        suggestedActions: [String]
    ) {
        self.signalID = signalID
        self.severity = severity
        self.routingLevel = routingLevel
        self.channelID = channelID
        self.summary = summary
        self.suggestedActions = suggestedActions
    }
}

public struct RunReviewSignoffMetric: Sendable, Hashable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct RunReviewSignoffDetailSection: Sendable, Hashable {
    public let title: String
    public let rows: [RunReviewSignoffDetailRow]

    public init(title: String, rows: [RunReviewSignoffDetailRow]) {
        self.title = title
        self.rows = rows
    }
}

public struct RunReviewSignoffDetailRow: Sendable, Hashable {
    public let label: String
    public let metrics: [RunReviewSignoffMetric]

    public init(label: String, metrics: [RunReviewSignoffMetric]) {
        self.label = label
        self.metrics = metrics
    }
}

public struct RunReviewSignoffIssue: Sendable, Hashable {
    public let severity: String
    public let label: String
    public let count: Int?
    public let message: String
    public let suggestedFixes: [String]
    public let repairActionHints: [RunReviewSignoffRepairActionHint]
    public let detailRows: [RunReviewSignoffDetailRow]
    public let evidenceArtifacts: [FlowRunReviewArtifact]

    public init(
        severity: String,
        label: String,
        count: Int? = nil,
        message: String,
        suggestedFixes: [String] = [],
        repairActionHints: [RunReviewSignoffRepairActionHint] = [],
        detailRows: [RunReviewSignoffDetailRow] = [],
        evidenceArtifacts: [FlowRunReviewArtifact] = []
    ) {
        self.severity = severity
        self.label = label
        self.count = count
        self.message = message
        self.suggestedFixes = suggestedFixes
        self.repairActionHints = repairActionHints
        self.detailRows = detailRows
        self.evidenceArtifacts = evidenceArtifacts
    }

    public func withEvidenceArtifacts(
        _ evidenceArtifacts: [FlowRunReviewArtifact]
    ) -> RunReviewSignoffIssue {
        RunReviewSignoffIssue(
            severity: severity,
            label: label,
            count: count,
            message: message,
            suggestedFixes: suggestedFixes,
            repairActionHints: repairActionHints,
            detailRows: detailRows,
            evidenceArtifacts: evidenceArtifacts
        )
    }
}

public struct RunReviewSignoffRepairActionHint: Sendable, Hashable {
    public let domainID: String
    public let operationID: String
    public let readinessState: XcircuiteOperationReadinessState
    public let reason: String
    public let requiredInputRefs: [String]
    public let verificationGates: [String]

    public init(
        domainID: String,
        operationID: String,
        readinessState: XcircuiteOperationReadinessState,
        reason: String,
        requiredInputRefs: [String],
        verificationGates: [String]
    ) {
        self.domainID = domainID
        self.operationID = operationID
        self.readinessState = readinessState
        self.reason = reason
        self.requiredInputRefs = requiredInputRefs
        self.verificationGates = verificationGates
    }
}

public struct RunReviewArtifactDecodeIssue: Sendable, Hashable {
    public let artifactRole: String
    public let artifactPath: String
    public let message: String

    public init(artifactRole: String, artifactPath: String, message: String) {
        self.artifactRole = artifactRole
        self.artifactPath = artifactPath
        self.message = message
    }
}
