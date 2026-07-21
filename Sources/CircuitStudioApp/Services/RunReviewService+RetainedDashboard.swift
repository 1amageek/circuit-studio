import Foundation
import CircuiteFoundation
import DesignFlowKernel

extension RunReviewService {
    static let retainedDashboardArtifactID = "retained-dashboard-projection"
    static let retainedDashboardRelativePath = "review/retained-dashboard"

    func retainedDashboardProjection(
        bundle: FlowRunReviewBundle
    ) -> RunReviewRetainedDashboardProjection {
        let retainedArtifacts = bundle.artifacts
            .filter(Self.isRetainedDashboardArtifact)
            .sorted { left, right in
                if left.purpose != right.purpose {
                    return left.purpose.rawValue < right.purpose.rawValue
                }
                return left.reference.locator.location.value < right.reference.locator.location.value
            }
        let retainedItems = bundle.reviewItems
            .filter { $0.kind == .retainedHistory }
            .sorted { left, right in left.itemID < right.itemID }
        let diagnosticsByPath = Self.diagnosticsByArtifactPath(from: retainedItems)
        let artifactStates = retainedArtifacts.map { artifact in
            Self.artifactState(
                artifact,
                diagnosticCodes: diagnosticsByPath[artifact.reference.locator.location.value, default: []]
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
    ) async throws -> ArtifactReference {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        let store = try workspaceStore(projectRoot: projectRoot)
        let loader = configuredReviewLedgerLoader(store: store)
        let bundle = try await configuredReviewBundler(store: store, loader: loader)
            .makeReviewBundle(
                runID: runID,
                workspaceID: try await workspaceID(store: store)
            )
        let projection = retainedDashboardProjection(bundle: bundle)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(projection)
        let digest = try SHA256ContentDigester().digest(data: data, using: .sha256)
        let relativePath = ".xcircuite/runs/\(runID)/\(Self.retainedDashboardRelativePath)/\(digest.hexadecimalValue).json"
        let reference = ArtifactReference(
            id: try ArtifactID(rawValue: "\(Self.retainedDashboardArtifactID)-\(digest.hexadecimalValue)"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: relativePath),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: digest,
            byteCount: UInt64(data.count)
        )
        let inputs = bundle.artifacts
            .filter { !Self.isRetainedDashboardProjectionArtifact($0) }
            .map(\.reference)
            .sorted { lhs, rhs in
                if lhs.path != rhs.path { return lhs.path < rhs.path }
                return lhs.artifactID < rhs.artifactID
            }
        let actionID = "retained-dashboard-\(digest.hexadecimalValue)"
        let ledger = try await store.loadRunLedger(runID: runID)
        let createdAt = ledger.actions.first { $0.actionID == actionID }?.createdAt ?? Date()
        let action = FlowRunActionRecord(
            actionID: actionID,
            runID: runID,
            actor: FlowRunActor(kind: .system, identifier: "circuit-studio"),
            actionKind: "review.persist-retained-dashboard",
            status: .succeeded,
            inputs: inputs,
            outputs: [reference],
            diagnostics: [
                FlowRunDiagnostic(
                    severity: .info,
                    code: "retained-dashboard-snapshot-persisted",
                    message: "Persisted a content-addressed retained-dashboard review snapshot."
                ),
            ],
            createdAt: createdAt
        )
        _ = try await store.appendActionArtifact(
            content: data,
            reference: reference,
            action: action
        )
        return reference
    }

    private static func isRetainedDashboardArtifact(_ artifact: FlowRunReviewArtifact) -> Bool {
        switch artifact.purpose.rawValue {
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

    private static func isRetainedDashboardProjectionArtifact(
        _ artifact: FlowRunReviewArtifact
    ) -> Bool {
        artifact.reference.artifactID.hasPrefix("\(retainedDashboardArtifactID)-")
            || artifact.reference.path.contains("/\(retainedDashboardRelativePath)/")
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
            role: artifact.purpose.rawValue,
            artifactID: artifact.reference.id.rawValue,
            path: artifact.reference.locator.location.value,
            integrityStatus: artifact.integrity?.status,
            sha256: artifact.reference.digest.hexadecimalValue,
            byteCount: artifact.reference.byteCount,
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
