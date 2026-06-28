import DesignFlowKernel
import Foundation

public struct RunReviewWaiverSummary: Sendable, Hashable {
    public let items: [RunReviewWaiverItem]
    public let decodeIssues: [RunReviewArtifactDecodeIssue]

    public init(
        items: [RunReviewWaiverItem],
        decodeIssues: [RunReviewArtifactDecodeIssue] = []
    ) {
        self.items = items
        self.decodeIssues = decodeIssues
    }

    public var hasContent: Bool {
        !items.isEmpty || !decodeIssues.isEmpty
    }
}

public struct RunReviewWaiverItem: Sendable, Hashable {
    public let waiverReviewID: String
    public let domain: String
    public let stageID: String?
    public let artifact: FlowRunReviewArtifact
    public let status: String
    public let waivedCount: Int
    public let unusedWaiverIDs: [String]
    public let waivedBuckets: [RunReviewWaivedBucket]
    public let sourceReferences: [RunReviewWaiverSourceReference]
    public let editProposals: [RunReviewWaiverEditProposal]
    public let editProposalSelections: [RunReviewWaiverEditProposalSelection]
    public let editApplications: [RunReviewWaiverEditApplication]
    public let editVerifications: [RunReviewWaiverEditVerification]
    public let latestDecision: RunReviewWaiverDecision?

    public init(
        waiverReviewID: String,
        domain: String,
        stageID: String?,
        artifact: FlowRunReviewArtifact,
        status: String,
        waivedCount: Int,
        unusedWaiverIDs: [String],
        waivedBuckets: [RunReviewWaivedBucket],
        sourceReferences: [RunReviewWaiverSourceReference] = [],
        editProposals: [RunReviewWaiverEditProposal] = [],
        editProposalSelections: [RunReviewWaiverEditProposalSelection] = [],
        editApplications: [RunReviewWaiverEditApplication] = [],
        editVerifications: [RunReviewWaiverEditVerification] = [],
        latestDecision: RunReviewWaiverDecision? = nil
    ) {
        self.waiverReviewID = waiverReviewID
        self.domain = domain
        self.stageID = stageID
        self.artifact = artifact
        self.status = status
        self.waivedCount = waivedCount
        self.unusedWaiverIDs = unusedWaiverIDs
        self.waivedBuckets = waivedBuckets
        self.sourceReferences = sourceReferences
        self.editProposals = editProposals
        self.editProposalSelections = editProposalSelections
        self.editApplications = editApplications
        self.editVerifications = editVerifications
        self.latestDecision = latestDecision
    }
}

public struct RunReviewWaivedBucket: Sendable, Hashable {
    public let label: String
    public let count: Int
    public let message: String

    public init(label: String, count: Int, message: String) {
        self.label = label
        self.count = count
        self.message = message
    }
}

public struct RunReviewWaiverSourceReference: Sendable, Hashable {
    public let waiverID: String
    public let path: String
    public let lineStart: Int?
    public let lineEnd: Int?
    public let ruleID: String?
    public let diagnosticID: String?
    public let reason: String

    public init(
        waiverID: String,
        path: String,
        lineStart: Int? = nil,
        lineEnd: Int? = nil,
        ruleID: String? = nil,
        diagnosticID: String? = nil,
        reason: String = ""
    ) {
        self.waiverID = waiverID
        self.path = path
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.ruleID = ruleID
        self.diagnosticID = diagnosticID
        self.reason = reason
    }

    public var locationLabel: String {
        guard let lineStart else {
            return path
        }
        if let lineEnd, lineEnd != lineStart {
            return "\(path):\(lineStart)-\(lineEnd)"
        }
        return "\(path):\(lineStart)"
    }
}

public struct RunReviewWaiverEditProposal: Sendable, Hashable {
    public let proposalID: String
    public let waiverID: String?
    public let kind: String
    public let status: String
    public let targetPath: String
    public let operation: String
    public let summary: String
    public let replacementText: String?
    public let risk: String

    public init(
        proposalID: String,
        waiverID: String? = nil,
        kind: String,
        status: String,
        targetPath: String,
        operation: String,
        summary: String,
        replacementText: String? = nil,
        risk: String = "medium"
    ) {
        self.proposalID = proposalID
        self.waiverID = waiverID
        self.kind = kind
        self.status = status
        self.targetPath = targetPath
        self.operation = operation
        self.summary = summary
        self.replacementText = replacementText
        self.risk = risk
    }
}

public enum RunReviewWaiverDecisionValue: String, Sendable, Hashable, Codable {
    case approved
    case rejected
}

public struct RunReviewWaiverDecision: Sendable, Hashable {
    public static let actionKind = "review.decideWaiver"

    public let actionRecordID: String
    public let runID: String
    public let actor: String
    public let decision: RunReviewWaiverDecisionValue
    public let decidedAt: Date
    public let note: String

    public init(
        actionRecordID: String,
        runID: String,
        actor: String,
        decision: RunReviewWaiverDecisionValue,
        decidedAt: Date,
        note: String
    ) {
        self.actionRecordID = actionRecordID
        self.runID = runID
        self.actor = actor
        self.decision = decision
        self.decidedAt = decidedAt
        self.note = note
    }
}

public struct RunReviewWaiverEditProposalSelection: Sendable, Hashable {
    public static let actionKind = "review.selectWaiverEditProposal"

    public let actionRecordID: String
    public let runID: String
    public let actor: String
    public let waiverReviewID: String
    public let proposalID: String
    public let selectedAt: Date
    public let note: String

    public init(
        actionRecordID: String,
        runID: String,
        actor: String,
        waiverReviewID: String,
        proposalID: String,
        selectedAt: Date,
        note: String
    ) {
        self.actionRecordID = actionRecordID
        self.runID = runID
        self.actor = actor
        self.waiverReviewID = waiverReviewID
        self.proposalID = proposalID
        self.selectedAt = selectedAt
        self.note = note
    }
}

public struct RunReviewWaiverEditApplication: Sendable, Hashable {
    public static let actionKind = "review.applyWaiverEditProposal"

    public let actionRecordID: String
    public let runID: String
    public let actor: String
    public let waiverReviewID: String
    public let proposalID: String
    public let targetPath: String
    public let operation: String
    public let beforeSHA256: String
    public let afterSHA256: String
    public let appliedAt: Date
    public let note: String

    public init(
        actionRecordID: String,
        runID: String,
        actor: String,
        waiverReviewID: String,
        proposalID: String,
        targetPath: String,
        operation: String,
        beforeSHA256: String,
        afterSHA256: String,
        appliedAt: Date,
        note: String
    ) {
        self.actionRecordID = actionRecordID
        self.runID = runID
        self.actor = actor
        self.waiverReviewID = waiverReviewID
        self.proposalID = proposalID
        self.targetPath = targetPath
        self.operation = operation
        self.beforeSHA256 = beforeSHA256
        self.afterSHA256 = afterSHA256
        self.appliedAt = appliedAt
        self.note = note
    }
}

public struct RunReviewWaiverEditVerification: Sendable, Hashable {
    public static let actionKind = "review.verifyWaiverEditProposal"

    public let actionRecordID: String
    public let runID: String
    public let actor: String
    public let waiverReviewID: String
    public let proposalID: String
    public let applicationActionID: String
    public let verificationReportPath: String
    public let layoutTrustReportPath: String?
    public let status: String
    public let readyForPEX: Bool
    public let drcPassed: Bool
    public let drcViolationCount: Int
    public let lvsPassed: Bool
    public let planningFeedbackStatus: String
    public let rejectedPlansPath: String?
    public let reportSummary: RunReviewWaiverEditVerificationReportSummary?
    public let verifiedAt: Date
    public let note: String

    public init(
        actionRecordID: String,
        runID: String,
        actor: String,
        waiverReviewID: String,
        proposalID: String,
        applicationActionID: String,
        verificationReportPath: String,
        layoutTrustReportPath: String?,
        status: String,
        readyForPEX: Bool,
        drcPassed: Bool,
        drcViolationCount: Int,
        lvsPassed: Bool,
        planningFeedbackStatus: String = "not-recorded",
        rejectedPlansPath: String? = nil,
        reportSummary: RunReviewWaiverEditVerificationReportSummary? = nil,
        verifiedAt: Date,
        note: String
    ) {
        self.actionRecordID = actionRecordID
        self.runID = runID
        self.actor = actor
        self.waiverReviewID = waiverReviewID
        self.proposalID = proposalID
        self.applicationActionID = applicationActionID
        self.verificationReportPath = verificationReportPath
        self.layoutTrustReportPath = layoutTrustReportPath
        self.status = status
        self.readyForPEX = readyForPEX
        self.drcPassed = drcPassed
        self.drcViolationCount = drcViolationCount
        self.lvsPassed = lvsPassed
        self.planningFeedbackStatus = planningFeedbackStatus
        self.rejectedPlansPath = rejectedPlansPath
        self.reportSummary = reportSummary
        self.verifiedAt = verifiedAt
        self.note = note
    }
}

public struct RunReviewWaiverEditVerificationReportSummary: Sendable, Hashable {
    public let status: String
    public let readyForPEX: Bool
    public let drc: RunReviewWaiverEditVerificationDRCSummary
    public let lvs: RunReviewWaiverEditVerificationLVSSummary
    public let layoutTrustPassed: Bool?
    public let externalSignoffPassed: Bool?
    public let externalSignoffReadyForPEX: Bool?

    public init(
        status: String,
        readyForPEX: Bool,
        drc: RunReviewWaiverEditVerificationDRCSummary,
        lvs: RunReviewWaiverEditVerificationLVSSummary,
        layoutTrustPassed: Bool? = nil,
        externalSignoffPassed: Bool? = nil,
        externalSignoffReadyForPEX: Bool? = nil
    ) {
        self.status = status
        self.readyForPEX = readyForPEX
        self.drc = drc
        self.lvs = lvs
        self.layoutTrustPassed = layoutTrustPassed
        self.externalSignoffPassed = externalSignoffPassed
        self.externalSignoffReadyForPEX = externalSignoffReadyForPEX
    }
}

public struct RunReviewWaiverEditVerificationDRCSummary: Sendable, Hashable {
    public let passed: Bool
    public let violationCount: Int
    public let violationsByKind: [RunReviewWaiverVerificationBucket]

    public init(
        passed: Bool,
        violationCount: Int,
        violationsByKind: [RunReviewWaiverVerificationBucket] = []
    ) {
        self.passed = passed
        self.violationCount = violationCount
        self.violationsByKind = violationsByKind
    }
}

public struct RunReviewWaiverEditVerificationLVSSummary: Sendable, Hashable {
    public let passed: Bool
    public let schematicHashMatches: Bool
    public let connectivityExtractionSkipped: Bool
    public let issueCounts: [RunReviewWaiverVerificationBucket]

    public init(
        passed: Bool,
        schematicHashMatches: Bool,
        connectivityExtractionSkipped: Bool,
        issueCounts: [RunReviewWaiverVerificationBucket] = []
    ) {
        self.passed = passed
        self.schematicHashMatches = schematicHashMatches
        self.connectivityExtractionSkipped = connectivityExtractionSkipped
        self.issueCounts = issueCounts
    }
}

public struct RunReviewWaiverVerificationBucket: Sendable, Hashable {
    public let label: String
    public let count: Int

    public init(label: String, count: Int) {
        self.label = label
        self.count = count
    }
}
