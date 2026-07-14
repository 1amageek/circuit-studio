import Foundation
import CircuiteFoundation
import DesignFlowKernel

extension RunReviewService {
    static let retainedDashboardArtifactID = "retained-dashboard-projection"
    static let retainedDashboardRelativePath = "review/retained-dashboard-projection.json"

    func retainedDashboardProjection(
        bundle: FlowRunReviewBundle
    ) -> RunReviewRetainedDashboardProjection {
        let retainedArtifacts = bundle.artifacts
            .filter(Self.isRetainedDashboardArtifact)
            .sorted { left, right in
                if left.role != right.role {
                    return left.role < right.role
                }
                return left.path < right.path
            }
        let retainedItems = bundle.reviewItems
            .filter { $0.kind == .retainedHistory }
            .sorted { left, right in left.itemID < right.itemID }
        let diagnosticsByPath = Self.diagnosticsByArtifactPath(from: retainedItems)
        let artifactStates = retainedArtifacts.map { artifact in
            Self.artifactState(
                artifact,
                diagnosticCodes: diagnosticsByPath[artifact.path, default: []]
            )
        }
        let blockers = retainedItems.map(RunReviewRetainedDashboardProjection.BlockerSummary.init)
        let decisions = (bundle.decisionActions ?? [])
            .map(RunReviewRetainedDashboardProjection.DecisionSummary.init)
            .sorted { left, right in
                if left.decidedAt != right.decidedAt {
                    return left.decidedAt < right.decidedAt
                }
                return left.id < right.id
            }
        let actions = Self.retainedDashboardNextActions(bundle: bundle)
            .map(RunReviewRetainedDashboardProjection.NextActionSummary.init)
        let diagnosticCodes = Array(Set(
            retainedItems.flatMap(\.diagnosticCodes)
                + actions.flatMap(\.diagnosticCodes)
                + artifactStates.flatMap(\.diagnosticCodes)
        )).sorted()
        return RunReviewRetainedDashboardProjection(
            runID: bundle.runID,
            status: Self.retainedDashboardStatus(
                artifacts: artifactStates,
                blockers: blockers,
                diagnostics: diagnosticCodes
            ),
            artifactStates: artifactStates,
            blockerSummaries: blockers,
            decisionSummaries: decisions,
            resumeActions: actions,
            diagnosticCodes: diagnosticCodes
        )
    }

    public func persistRetainedDashboardProjection(
        runID: String,
        projectRoot: URL
    ) throws -> ArtifactReference {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        let bundle = try reviewBundler.makeReviewBundle(runID: runID, projectRoot: projectRoot)
        let projection = retainedDashboardProjection(bundle: bundle)
        let relativePath = ".xcircuite/runs/\(runID)/\(Self.retainedDashboardRelativePath)"
        let url = try XcircuiteWorkspace(projectRoot: projectRoot).url(forProjectRelativePath: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(projection)
        try data.write(to: url, options: .atomic)
        let legacyReference = try store.fileReference(
            forProjectRelativePath: relativePath,
            artifactID: Self.retainedDashboardArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try store.upsertRunArtifact(legacyReference, runID: runID, inProjectAt: projectRoot)
        guard let reference = FoundationArtifactTypeProjection.reference(legacyReference) else {
            throw RunReviewServiceError.artifactReferenceProjectionFailed(
                path: legacyReference.path,
                message: "Persisted retained dashboard artifact has invalid integrity, kind, or format metadata."
            )
        }
        return reference
    }

    private static func isRetainedDashboardArtifact(_ artifact: FlowRunReviewArtifact) -> Bool {
        switch artifact.role {
        case "retained-history",
             "retained-history-dashboard",
             "retention-index",
             "retention-index-review",
             "retained-ci-regression-budget",
             "retained-workflow-report",
             "release-envelope",
             "release-retention-index":
            return true
        default:
            return false
        }
    }

    private static func diagnosticsByArtifactPath(
        from items: [FlowRunReviewItem]
    ) -> [String: [String]] {
        var result: [String: Set<String>] = [:]
        for item in items {
            for path in item.artifactPaths {
                result[path, default: []].formUnion(item.diagnosticCodes)
            }
        }
        return result.mapValues { $0.sorted() }
    }

    private static func artifactState(
        _ artifact: FlowRunReviewArtifact,
        diagnosticCodes: [String]
    ) -> RunReviewRetainedDashboardProjection.ArtifactState {
        RunReviewRetainedDashboardProjection.ArtifactState(
            role: artifact.role,
            artifactID: artifact.artifactID,
            path: artifact.path,
            integrityStatus: artifact.integrity?.status,
            sha256: artifact.sha256,
            byteCount: artifact.byteCount,
            diagnosticCodes: diagnosticCodes,
            evidenceStatus: evidenceStatus(for: artifact, diagnosticCodes: diagnosticCodes)
        )
    }

    private static func evidenceStatus(
        for artifact: FlowRunReviewArtifact,
        diagnosticCodes: [String]
    ) -> String {
        if diagnosticCodes.contains(where: { $0.contains("stale") }) {
            return "stale"
        }
        if diagnosticCodes.contains(where: { $0.contains("missing") }) {
            return "missing"
        }
        if diagnosticCodes.contains(where: { $0.contains("mismatch") || $0.contains("failed") }) {
            return "broken"
        }
        guard let integrityStatus = artifact.integrity?.status else {
            return "untracked"
        }
        return integrityStatus.rawValue
    }

    private static func retainedDashboardNextActions(
        bundle: FlowRunReviewBundle
    ) -> [FlowRunNextAction] {
        let retainedActionIDs = Set(
            bundle.reviewItems
                .filter { $0.kind == .retainedHistory }
                .compactMap(\.nextActionID)
        )
        return bundle.summary.nextActions
            .filter { action in
                retainedActionIDs.contains(action.actionID)
                    || action.kind.contains("retained")
                    || action.kind.contains("history")
                    || action.actionID.contains("retained")
                    || action.actionID.contains("history")
            }
            .sorted { left, right in left.actionID < right.actionID }
    }

    private static func retainedDashboardStatus(
        artifacts: [RunReviewRetainedDashboardProjection.ArtifactState],
        blockers: [RunReviewRetainedDashboardProjection.BlockerSummary],
        diagnostics: [String]
    ) -> RunReviewRetainedDashboardProjection.Status {
        guard !artifacts.isEmpty || !blockers.isEmpty || !diagnostics.isEmpty else {
            return .empty
        }
        if blockers.contains(where: { $0.status == .needsRepair })
            || artifacts.contains(where: { $0.evidenceStatus == "broken" || $0.evidenceStatus == "missing" })
        {
            return .needsRepair
        }
        if blockers.contains(where: { $0.status == .needsReview })
            || artifacts.contains(where: { $0.evidenceStatus == "stale" || $0.evidenceStatus == "untracked" })
        {
            return .needsReview
        }
        return .ready
    }
}
