import DesignFlowKernel
import Foundation

public struct RunReviewFlowReviewProjection: Sendable, Hashable {
    public struct CoverageDomain: Sendable, Hashable {
        public let domain: String
        public let refCount: Int
        public let roles: [String]
        public let artifactPaths: [String]
        public let unverifiedArtifactPaths: [String]

        public init(
            domain: String,
            refCount: Int,
            roles: [String],
            artifactPaths: [String],
            unverifiedArtifactPaths: [String] = []
        ) {
            self.domain = domain
            self.refCount = refCount
            self.roles = roles
            self.artifactPaths = artifactPaths
            self.unverifiedArtifactPaths = unverifiedArtifactPaths
        }
    }

    public let coverageRefs: [FlowRunReviewBundle.CoverageRef]
    public let coverageDomains: [CoverageDomain]
    public let signoffLadderArtifacts: [FlowRunReviewArtifact]
    public let planningArtifacts: [FlowRunReviewArtifact]
    public let retainedHistoryArtifacts: [FlowRunReviewArtifact]
    public let integrityIssueArtifacts: [FlowRunReviewArtifact]
    public let approvalActions: [FlowRunReviewDecision]
    public let waiverActions: [FlowRunReviewDecision]
    public let resumeActions: [FlowRunReviewDecision]
    public let blockedItems: [FlowRunReviewItem]
    public let resumeItems: [FlowRunReviewItem]

    public init(bundle: FlowRunReviewBundle) {
        let refs = bundle.coverageRefs ?? []
        let actions = bundle.decisionActions ?? []
        let signoffLadderCandidates = Self.artifacts(
            from: bundle.artifacts,
            matchingRoles: ["stage-artifact-ladder"]
        )
        let planningCandidates = bundle.artifacts
            .filter { $0.purpose.rawValue.hasPrefix("planning-") }
            .sorted(by: Self.artifactSort)
        let retainedHistoryCandidates = bundle.artifacts
            .filter { artifact in
                artifact.purpose.rawValue.hasPrefix("retained-")
                    || artifact.purpose.rawValue.hasPrefix("retention-")
                    || artifact.purpose.rawValue.hasPrefix("release-")
            }
            .sorted(by: Self.artifactSort)
        self.coverageRefs = refs
        self.coverageDomains = Self.coverageDomains(from: refs)
        self.signoffLadderArtifacts = Self.verifiedArtifacts(from: signoffLadderCandidates)
        self.planningArtifacts = Self.verifiedArtifacts(from: planningCandidates)
        self.retainedHistoryArtifacts = Self.verifiedArtifacts(from: retainedHistoryCandidates)
        self.integrityIssueArtifacts = Self.integrityIssueArtifacts(
            from: signoffLadderCandidates + planningCandidates + retainedHistoryCandidates
        )
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
            || !integrityIssueArtifacts.isEmpty
            || !approvalActions.isEmpty
            || !waiverActions.isEmpty
            || !resumeActions.isEmpty
            || !blockedItems.isEmpty
            || !resumeItems.isEmpty
    }

    private static func coverageDomains(
        from refs: [FlowRunReviewBundle.CoverageRef]
    ) -> [CoverageDomain] {
        let groupedRefs = Dictionary(grouping: refs, by: \.domain)
        let domains: [CoverageDomain] = groupedRefs.map { domain, domainRefs in
            let artifactPaths = domainRefs.compactMap { ref in
                coverageRefIsVerifiedOrDecision(ref) ? ref.path : nil
            }
            let unverifiedArtifactPaths = domainRefs.compactMap { ref in
                coverageRefIsUnverifiedArtifact(ref) ? ref.path : nil
            }
            return CoverageDomain(
                domain: domain,
                refCount: domainRefs.count,
                roles: Array(Set(domainRefs.map(\.role))).sorted(),
                artifactPaths: Array(Set(artifactPaths)).sorted(),
                unverifiedArtifactPaths: Array(Set(unverifiedArtifactPaths)).sorted()
            )
        }
        return domains.sorted { left, right in
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
            .filter { roles.contains($0.purpose.rawValue) }
            .sorted(by: artifactSort)
    }

    private static func verifiedArtifacts(
        from artifacts: [FlowRunReviewArtifact]
    ) -> [FlowRunReviewArtifact] {
        artifacts.filter { $0.integrity?.status == .verified }
    }

    private static func integrityIssueArtifacts(
        from artifacts: [FlowRunReviewArtifact]
    ) -> [FlowRunReviewArtifact] {
        var seen: Set<String> = []
        return artifacts
            .filter { $0.integrity?.status != .verified }
            .filter { artifact in
                let key = "\(artifact.purpose.rawValue)\u{0}\(artifact.reference.locator.location.value)"
                guard !seen.contains(key) else {
                    return false
                }
                seen.insert(key)
                return true
            }
            .sorted(by: artifactSort)
    }

    private static func coverageRefIsVerifiedOrDecision(
        _ ref: FlowRunReviewBundle.CoverageRef
    ) -> Bool {
        if let integrityStatus = ref.integrityStatus {
            return integrityStatus == .verified
        }
        return ref.artifactID == nil
    }

    private static func coverageRefIsUnverifiedArtifact(
        _ ref: FlowRunReviewBundle.CoverageRef
    ) -> Bool {
        guard ref.path != nil else {
            return false
        }
        if let integrityStatus = ref.integrityStatus {
            return integrityStatus != .verified
        }
        return ref.artifactID != nil
    }

    private static func actions(
        _ actions: [FlowRunReviewDecision],
        kind: FlowRunReviewDecisionKind
    ) -> [FlowRunReviewDecision] {
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
        if left.purpose != right.purpose {
            return left.purpose.rawValue < right.purpose.rawValue
        }
        return left.reference.locator.location.value < right.reference.locator.location.value
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
