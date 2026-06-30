import DesignFlowKernel
import Foundation
import XcircuitePackage

public struct RunReviewFlowReviewProjection: Sendable, Hashable {
    public struct CoverageDomain: Sendable, Hashable {
        public let domain: String
        public let refCount: Int
        public let roles: [String]
        public let artifactPaths: [String]

        public init(
            domain: String,
            refCount: Int,
            roles: [String],
            artifactPaths: [String]
        ) {
            self.domain = domain
            self.refCount = refCount
            self.roles = roles
            self.artifactPaths = artifactPaths
        }
    }

    public let coverageRefs: [FlowRunReviewBundle.CoverageRef]
    public let coverageDomains: [CoverageDomain]
    public let signoffLadderArtifacts: [FlowRunReviewArtifact]
    public let planningArtifacts: [FlowRunReviewArtifact]
    public let retainedHistoryArtifacts: [FlowRunReviewArtifact]
    public let approvalActions: [XcircuiteRunReviewDecisionAction]
    public let waiverActions: [XcircuiteRunReviewDecisionAction]
    public let resumeActions: [XcircuiteRunReviewDecisionAction]
    public let blockedItems: [FlowRunReviewItem]
    public let resumeItems: [FlowRunReviewItem]

    public init(bundle: FlowRunReviewBundle) {
        let refs = bundle.coverageRefs ?? []
        let actions = bundle.decisionActions ?? []
        self.coverageRefs = refs
        self.coverageDomains = Self.coverageDomains(from: refs)
        self.signoffLadderArtifacts = Self.artifacts(
            from: bundle.artifacts,
            matchingRoles: ["stage-artifact-ladder"]
        )
        self.planningArtifacts = bundle.artifacts
            .filter { $0.role.hasPrefix("planning-") }
            .sorted(by: Self.artifactSort)
        self.retainedHistoryArtifacts = bundle.artifacts
            .filter { artifact in
                artifact.role.hasPrefix("retained-")
                    || artifact.role.hasPrefix("retention-")
                    || artifact.role.hasPrefix("release-")
            }
            .sorted(by: Self.artifactSort)
        self.approvalActions = Self.actions(actions, kind: .approval)
        self.waiverActions = Self.actions(actions, kind: .waiver)
        self.resumeActions = Self.actions(actions, kind: .resume)
        self.blockedItems = bundle.reviewItems
            .filter { $0.status == .needsReview || $0.status == .needsRepair }
            .sorted(by: Self.itemSort)
        self.resumeItems = bundle.reviewItems
            .filter { item in
                item.status == .readyToResume
                    || item.nextActionID?.contains("resume") == true
            }
            .sorted(by: Self.itemSort)
    }

    public var hasContent: Bool {
        !coverageRefs.isEmpty
            || !signoffLadderArtifacts.isEmpty
            || !planningArtifacts.isEmpty
            || !retainedHistoryArtifacts.isEmpty
            || !approvalActions.isEmpty
            || !waiverActions.isEmpty
            || !resumeActions.isEmpty
            || !blockedItems.isEmpty
            || !resumeItems.isEmpty
    }

    private static func coverageDomains(
        from refs: [FlowRunReviewBundle.CoverageRef]
    ) -> [CoverageDomain] {
        Dictionary(grouping: refs, by: \.domain)
            .map { domain, refs in
                CoverageDomain(
                    domain: domain,
                    refCount: refs.count,
                    roles: Array(Set(refs.map(\.role))).sorted(),
                    artifactPaths: Array(Set(refs.compactMap(\.path))).sorted()
                )
            }
            .sorted { left, right in
                if left.domain != right.domain {
                    return left.domain < right.domain
                }
                return left.refCount > right.refCount
            }
    }

    private static func artifacts(
        from artifacts: [FlowRunReviewArtifact],
        matchingRoles roles: Set<String>
    ) -> [FlowRunReviewArtifact] {
        artifacts
            .filter { roles.contains($0.role) }
            .sorted(by: artifactSort)
    }

    private static func actions(
        _ actions: [XcircuiteRunReviewDecisionAction],
        kind: XcircuiteRunReviewDecisionActionKind
    ) -> [XcircuiteRunReviewDecisionAction] {
        actions
            .filter { $0.decisionKind == kind }
            .sorted { left, right in
                if left.decidedAt != right.decidedAt {
                    return left.decidedAt < right.decidedAt
                }
                return left.actionRecordID < right.actionRecordID
            }
    }

    private static func artifactSort(
        _ left: FlowRunReviewArtifact,
        _ right: FlowRunReviewArtifact
    ) -> Bool {
        if left.role != right.role {
            return left.role < right.role
        }
        return left.path < right.path
    }

    private static func itemSort(
        _ left: FlowRunReviewItem,
        _ right: FlowRunReviewItem
    ) -> Bool {
        if left.severity != right.severity {
            return severityRank(left.severity) > severityRank(right.severity)
        }
        return left.itemID < right.itemID
    }

    private static func severityRank(_ severity: FlowDiagnosticSeverity) -> Int {
        switch severity {
        case .error:
            3
        case .warning:
            2
        case .info:
            1
        }
    }
}
