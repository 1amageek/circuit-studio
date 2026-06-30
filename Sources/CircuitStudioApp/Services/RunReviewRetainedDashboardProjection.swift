import DesignFlowKernel
import Foundation
import XcircuitePackage

public struct RunReviewRetainedDashboardProjection: Sendable, Hashable, Codable {
    public enum Status: String, Sendable, Hashable, Codable {
        case empty
        case ready
        case needsReview
        case needsRepair
    }

    public struct ArtifactState: Sendable, Hashable, Identifiable, Codable {
        public let id: String
        public let role: String
        public let artifactID: String?
        public let path: String
        public let integrityStatus: FlowRunReviewArtifactIntegrityStatus?
        public let sha256: String?
        public let byteCount: Int64?
        public let diagnosticCodes: [String]
        public let evidenceStatus: String

        public init(
            role: String,
            artifactID: String?,
            path: String,
            integrityStatus: FlowRunReviewArtifactIntegrityStatus?,
            sha256: String?,
            byteCount: Int64?,
            diagnosticCodes: [String],
            evidenceStatus: String
        ) {
            self.id = path
            self.role = role
            self.artifactID = artifactID
            self.path = path
            self.integrityStatus = integrityStatus
            self.sha256 = sha256
            self.byteCount = byteCount
            self.diagnosticCodes = diagnosticCodes
            self.evidenceStatus = evidenceStatus
        }
    }

    public struct BlockerSummary: Sendable, Hashable, Identifiable, Codable {
        public let id: String
        public let status: FlowRunReviewItemStatus
        public let severity: FlowDiagnosticSeverity
        public let title: String
        public let reason: String
        public let diagnosticCodes: [String]
        public let artifactPaths: [String]
        public let nextActionID: String?

        public init(item: FlowRunReviewItem) {
            self.id = item.itemID
            self.status = item.status
            self.severity = item.severity
            self.title = item.title
            self.reason = item.reason
            self.diagnosticCodes = item.diagnosticCodes
            self.artifactPaths = item.artifactPaths
            self.nextActionID = item.nextActionID
        }
    }

    public struct DecisionSummary: Sendable, Hashable, Identifiable, Codable {
        public let id: String
        public let kind: XcircuiteRunReviewDecisionActionKind
        public let decision: String
        public let targetID: String
        public let targetPath: String?
        public let decidedAt: Date

        public init(action: XcircuiteRunReviewDecisionAction) {
            self.id = action.actionRecordID
            self.kind = action.decisionKind
            self.decision = action.decision
            self.targetID = action.targetID
            self.targetPath = action.targetPath
            self.decidedAt = action.decidedAt
        }
    }

    public struct NextActionSummary: Sendable, Hashable, Identifiable, Codable {
        public let id: String
        public let kind: String
        public let severity: FlowDiagnosticSeverity
        public let reason: String
        public let diagnosticCodes: [String]
        public let readyCommandIDs: [String]
        public let inputRequiredCommandIDs: [String]

        public init(action: FlowRunNextAction) {
            self.id = action.actionID
            self.kind = action.kind
            self.severity = action.severity
            self.reason = action.reason
            self.diagnosticCodes = action.diagnosticCodes
            self.readyCommandIDs = action.suggestedCommands
                .filter { $0.readiness == .ready }
                .map(\.commandID)
                .sorted()
            self.inputRequiredCommandIDs = action.suggestedCommands
                .filter { $0.readiness == .requiresInput }
                .map(\.commandID)
                .sorted()
        }
    }

    public let runID: String
    public let status: Status
    public let artifactStates: [ArtifactState]
    public let blockerSummaries: [BlockerSummary]
    public let decisionSummaries: [DecisionSummary]
    public let resumeActions: [NextActionSummary]
    public let diagnosticCodes: [String]

    public init(
        runID: String,
        status: Status,
        artifactStates: [ArtifactState],
        blockerSummaries: [BlockerSummary],
        decisionSummaries: [DecisionSummary],
        resumeActions: [NextActionSummary],
        diagnosticCodes: [String]
    ) {
        self.runID = runID
        self.status = status
        self.artifactStates = artifactStates
        self.blockerSummaries = blockerSummaries
        self.decisionSummaries = decisionSummaries
        self.resumeActions = resumeActions
        self.diagnosticCodes = diagnosticCodes
    }

    public var hasContent: Bool {
        !artifactStates.isEmpty
            || !blockerSummaries.isEmpty
            || !decisionSummaries.isEmpty
            || !resumeActions.isEmpty
            || !diagnosticCodes.isEmpty
    }

    public var verifiedArtifactCount: Int {
        artifactStates.filter { $0.integrityStatus == .verified }.count
    }

    public var staleEvidenceCount: Int {
        artifactStates.filter { state in
            state.evidenceStatus == "stale"
                || state.diagnosticCodes.contains { $0.contains("stale") }
        }.count
    }
}
