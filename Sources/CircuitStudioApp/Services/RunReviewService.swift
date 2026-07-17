import Foundation
import CircuiteFoundation
import DesignFlowKernel
import Xcircuite

/// The review cockpit's data layer: everything it shows is read from
/// the `.xcircuite` run ledger — the same record the flow kernel and
/// the agents write — and the only thing it writes back is the human
/// decision (an approval record the kernel's approval gate consumes).
public struct RunReviewService: Sendable {

    /// One run as the reviewer sees it: the manifest verdict, each
    /// stage's gates and artifacts, and any decisions already taken.
    public struct RunReview: Sendable {
        public let runID: String
        public let status: FlowRunStatus
        public let actor: FlowRunActor
        public let intent: String?
        public let createdAt: Date
        public let updatedAt: Date
        public let startedAt: Date?
        public let finishedAt: Date?
        /// Canonical Foundation artifact references projected from the run
        /// manifest at the storage boundary.
        public let artifacts: [ArtifactReference]
        public let stages: [StageReview]
        public let approvals: [FlowApprovalRecord]
        public let suggestedActionSelections: [FlowRunSuggestedActionSelection]
        public let planning: PlanningReview
        public let signoff: RunReviewSignoffSummary
        public let waivers: RunReviewWaiverSummary
        public let failureStates: RunReviewFailureStateSummary
        public let toolchain: RunReviewToolchainProjection
        public let flowReview: RunReviewFlowReviewProjection
        public let retainedDashboard: RunReviewRetainedDashboardProjection
        public let bundle: FlowRunReviewBundle
    }

    public struct PlanningReview: Sendable, Hashable {
        public let candidatePlanArtifact: FlowRunReviewArtifact?
        public let planVerificationArtifact: FlowRunReviewArtifact?
        public let candidatePlan: XcircuiteCandidatePlan?
        public let planVerification: XcircuitePlanVerification?
        public let designDiff: DesignDiff?
        public let designDiffSummary: RunReviewDesignDiffSummary?
        public let correctnessItems: [FlowRunReviewItem]
        public let selectedActions: [FlowRunSuggestedActionSelection]
        public let decodeIssues: [PlanningArtifactDecodeIssue]

        public var hasContent: Bool {
            candidatePlanArtifact != nil
                || planVerificationArtifact != nil
                || candidatePlan != nil
                || planVerification != nil
                || designDiff != nil
                || designDiffSummary != nil
                || !correctnessItems.isEmpty
                || !selectedActions.isEmpty
                || !decodeIssues.isEmpty
        }
    }

    public struct PlanningArtifactDecodeIssue: Sendable, Hashable {
        public let artifactRole: String
        public let artifactPath: String
        public let message: String
    }

    public struct StageReview: Sendable {
        public let result: FlowStageResult
        /// The stage's recorded human decision, when one exists.
        public let approval: FlowApprovalRecord?
        /// True when the stage carries an approval gate that is still
        /// incomplete — the run is waiting on this reviewer.
        public var awaitingApproval: Bool {
            result.gates.contains { $0.gateID == "approval" && $0.status == .incomplete }
        }
    }

    let ledgerLoader: (any FlowRunLedgerLoading)?
    let reviewLedgerLoader: (any FlowRunReviewLedgerLoading)?
    let reviewBundler: (any FlowRunReviewBundling)?

    public init(
        ledgerLoader: (any FlowRunLedgerLoading)? = nil,
        reviewLedgerLoader: (any FlowRunReviewLedgerLoading)? = nil,
        reviewBundler: (any FlowRunReviewBundling)? = nil
    ) {
        self.ledgerLoader = ledgerLoader
        self.reviewLedgerLoader = reviewLedgerLoader
        self.reviewBundler = reviewBundler
    }

    func workspaceStore(projectRoot: URL) throws -> XcircuiteWorkspaceStore {
        try XcircuiteWorkspaceStore(projectRoot: projectRoot)
    }

    func configuredLedgerLoader(
        store: XcircuiteWorkspaceStore
    ) -> any FlowRunLedgerLoading {
        ledgerLoader ?? store
    }

    func configuredReviewBundler(
        store: XcircuiteWorkspaceStore,
        loader: any FlowRunReviewLedgerLoading
    ) -> any FlowRunReviewBundling {
        reviewBundler ?? DefaultFlowRunReviewBundler(loader: loader, persistence: store)
    }

    func configuredReviewLedgerLoader(
        store: XcircuiteWorkspaceStore
    ) -> any FlowRunReviewLedgerLoading {
        reviewLedgerLoader ?? store
    }

    func workspaceID(store: XcircuiteWorkspaceStore) async throws -> FlowWorkspaceID {
        let manifest = try await store.loadManifest()
        return try FlowWorkspaceID(rawValue: manifest.identity.projectID)
    }

    /// Every project run resolved from its locator to its canonical manifest, newest last.
    public func listRuns(projectRoot: URL) async throws -> [FlowRunSnapshot] {
        let store = try workspaceStore(projectRoot: projectRoot)
        let manifest = try await store.loadManifest()
        var snapshots: [FlowRunSnapshot] = []
        for reference in manifest.runs {
            snapshots.append(FlowRunSnapshot(
                reference: reference,
                manifest: try await store.loadRunManifest(runID: reference.runID)
            ))
        }
        return snapshots.sorted { $0.manifest.createdAt < $1.manifest.createdAt }
    }

    /// The full review picture of one run, straight from the ledger.
    public func loadRun(runID: String, projectRoot: URL) async throws -> RunReview {
        let store = try workspaceStore(projectRoot: projectRoot)
        let loader = configuredReviewLedgerLoader(store: store)
        let bundler = configuredReviewBundler(store: store, loader: loader)
        let ledger = try await loader.loadRunLedgerForReview(runID: runID)
        let bundle = try await bundler.makeReviewBundle(
            runID: runID,
            workspaceID: try await workspaceID(store: store)
        )
        let approvals = bundle.approvals
        let suggestedActionSelections = try suggestedActionSelections(from: ledger.actions)
        let approvalsByStage = Dictionary(
            approvals.map { ($0.stageID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let stages = ledger.stages.map { result in
            StageReview(
                result: result,
                approval: approvalsByStage[result.stageID]
            )
        }
        let planning = planningReview(
            bundle: bundle,
            projectRoot: projectRoot,
            approvals: approvals,
            designDiff: ledger.designDiff,
            suggestedActionSelections: suggestedActionSelections
        )
        let signoff = try signoffReview(
            bundle: bundle,
            actions: ledger.actions,
            projectRoot: projectRoot
        )
        let waivers = try waiverReview(
            bundle: bundle,
            actions: ledger.actions,
            projectRoot: projectRoot
        )
        let failureStates = failureStateSummary(
            bundle: bundle,
            stages: stages,
            planningDecodeIssues: planning.decodeIssues,
            signoffDecodeIssues: signoff.decodeIssues,
            waiverDecodeIssues: waivers.decodeIssues
        )
        let toolchain = RunReviewToolchainProjection(bundle: bundle)
        let flowReview = RunReviewFlowReviewProjection(bundle: bundle)
        let retainedDashboard = retainedDashboardProjection(bundle: bundle)

        return RunReview(
            runID: runID,
            status: Self.xcircuiteStatus(from: bundle.status),
            actor: ledger.runManifest.actor,
            intent: ledger.runManifest.intent,
            createdAt: ledger.runManifest.createdAt,
            updatedAt: ledger.runManifest.updatedAt,
            startedAt: ledger.runManifest.startedAt,
            finishedAt: ledger.runManifest.finishedAt,
            artifacts: ledger.runManifest.artifacts,
            stages: stages,
            approvals: approvals,
            suggestedActionSelections: suggestedActionSelections,
            planning: planning,
            signoff: signoff,
            waivers: waivers,
            failureStates: failureStates,
            toolchain: toolchain,
            flowReview: flowReview,
            retainedDashboard: retainedDashboard,
            bundle: bundle
        )
    }

    public func loadReviewBundle(runID: String, projectRoot: URL) async throws -> FlowRunReviewBundle {
        let store = try workspaceStore(projectRoot: projectRoot)
        let loader = configuredReviewLedgerLoader(store: store)
        return try await configuredReviewBundler(store: store, loader: loader)
            .makeReviewBundle(
                runID: runID,
                workspaceID: try await workspaceID(store: store)
            )
    }

    public func loadSuggestedActionSelections(
        runID: String,
        projectRoot: URL
    ) async throws -> [FlowRunSuggestedActionSelection] {
        let store = try workspaceStore(projectRoot: projectRoot)
        let ledger = try await configuredReviewLedgerLoader(store: store)
            .loadRunLedgerForReview(runID: runID)
        return try suggestedActionSelections(from: ledger.actions)
    }

    private func suggestedActionSelections(
        from actions: [FlowRunActionRecord]
    ) throws -> [FlowRunSuggestedActionSelection] {
        var selections: [FlowRunSuggestedActionSelection] = []
        for action in actions {
            if let selection = try FlowRunSuggestedActionSelection(record: action) {
                selections.append(selection)
            }
        }
        return selections
    }

    public func recordSuggestedActionSelection(
        runID: String,
        nextActionID: String,
        actionID: String,
        reviewer: String,
        projectRoot: URL
    ) async throws -> FlowRunActionRecord {
        let store = try workspaceStore(projectRoot: projectRoot)
        let loader = configuredReviewLedgerLoader(store: store)
        let bundle = try await configuredReviewBundler(store: store, loader: loader)
            .makeReviewBundle(
                runID: runID,
                workspaceID: try await workspaceID(store: store)
            )
        guard let nextAction = bundle.summary.nextActions.first(where: { $0.actionID == nextActionID }) else {
            throw RunReviewServiceError.nextActionNotFound(actionID: nextActionID)
        }
        guard let action = nextAction.suggestedActions.first(where: { $0.id == actionID }) else {
            throw RunReviewServiceError.suggestedActionNotFound(
                actionID: nextActionID,
                suggestedActionID: actionID
            )
        }

        let record = FlowRunActionRecord(
            actionID: "suggested-action-selection-\(UUID().uuidString)",
            runID: runID,
            actor: FlowRunActor(kind: .human, identifier: reviewer),
            actionKind: FlowRunSuggestedActionSelection.actionKind,
            status: .succeeded,
            context: FlowRunActionContext(
                suggestedAction: FlowRunActionContext.SuggestedAction(
                    nextActionID: nextAction.actionID,
                    nextActionKind: nextAction.kind,
                    action: action
                )
            )
        )
        try await store.appendRunAction(record)
        return record
    }

    public func decidePlanningRiskApproval(
        runID: String,
        approvalID: String,
        verdict: FlowApprovalRecord.Verdict,
        reviewer: String,
        reviewerKind: FlowRunActor.Kind = .human,
        note: String = "",
        projectRoot: URL
    ) async throws -> XcircuiteCandidatePlanRiskApprovalResult {
        let store = try workspaceStore(projectRoot: projectRoot)
        return try await XcircuiteCandidatePlanRiskApprovalRecorder(workspaceStore: store).recordApproval(
            request: XcircuiteCandidatePlanRiskApprovalRequest(
                runID: runID,
                approvalID: approvalID,
                verdict: verdict,
                reviewer: reviewer,
                reviewerKind: reviewerKind,
                note: note
            ),
            projectRoot: projectRoot
        )
    }

    /// Records the reviewer's decision. The flow kernel's approval gate
    /// reads exactly this record on the next run of the same runID.
    /// `reviewerKind` keeps human and automated decisions distinguishable
    /// in the audited ledger; the cockpit records `.human` by default.
    public func decide(
        runID: String,
        stageID: String,
        verdict: FlowApprovalRecord.Verdict,
        reviewer: String,
        reviewerKind: FlowRunActor.Kind = .human,
        note: String = "",
        projectRoot: URL
    ) async throws -> FlowApprovalRecord {
        let store = try workspaceStore(projectRoot: projectRoot)
        let loader = configuredLedgerLoader(store: store)
        let reviewLoader = configuredReviewLedgerLoader(store: store)
        let bundler = configuredReviewBundler(store: store, loader: reviewLoader)
        let recorder = DefaultFlowGateApprovalRecorder(
            loader: loader,
            inspector: DefaultFlowRunLedgerInspector(reviewBundler: bundler),
            ledgerPersistence: store
        )
        let gateVerdict: FlowGateApprovalVerdict = switch verdict {
        case .approved: .approved
        case .waived: .waived
        case .rejected: .rejected
        }
        return try await recorder.recordApproval(FlowGateApprovalRequest(
            workspaceID: try await workspaceID(store: store),
            runID: runID,
            stageID: stageID,
            verdict: gateVerdict,
            reviewer: reviewer,
            reviewerKind: reviewerKind,
            note: note
        )).approval
    }

    private static func xcircuiteStatus(from status: FlowRunStatus) -> FlowRunStatus {
        switch status {
        case .created:
            .created
        case .running:
            .running
        case .succeeded:
            .succeeded
        case .failed:
            .failed
        case .cancelled:
            .cancelled
        case .blocked:
            .blocked
        case .partial:
            .partial
        }
    }

    private func planningReview(
        bundle: FlowRunReviewBundle,
        projectRoot: URL,
        approvals: [FlowApprovalRecord],
        designDiff: DesignDiff?,
        suggestedActionSelections: [FlowRunSuggestedActionSelection]
    ) -> PlanningReview {
        let candidatePlanArtifact = latestArtifact(
            role: "planning-candidate-plan",
            in: bundle.artifacts
        )
        let planVerificationArtifact = latestArtifact(
            role: "planning-plan-verification",
            in: bundle.artifacts
        )
        var decodeIssues: [PlanningArtifactDecodeIssue] = []
        let candidatePlan = decodedPlanningArtifact(
            XcircuiteCandidatePlan.self,
            role: "planning-candidate-plan",
            artifact: candidatePlanArtifact,
            projectRoot: projectRoot,
            decodeIssues: &decodeIssues
        )
        var planVerification = decodedPlanningArtifact(
            XcircuitePlanVerification.self,
            role: "planning-plan-verification",
            artifact: planVerificationArtifact,
            projectRoot: projectRoot,
            decodeIssues: &decodeIssues
        )
        if let candidatePlan {
            planVerification?.riskReviews = riskReviews(for: candidatePlan, approvals: approvals)
        }

        return PlanningReview(
            candidatePlanArtifact: candidatePlanArtifact,
            planVerificationArtifact: planVerificationArtifact,
            candidatePlan: candidatePlan,
            planVerification: planVerification,
            designDiff: designDiff,
            designDiffSummary: designDiff.map(designDiffSummary),
            correctnessItems: bundle.reviewItems.filter { $0.kind == .planningCorrectness },
            selectedActions: suggestedActionSelections,
            decodeIssues: decodeIssues
        )
    }

    private func decodedPlanningArtifact<T: Decodable>(
        _ type: T.Type,
        role: String,
        artifact: FlowRunReviewArtifact?,
        projectRoot: URL,
        decodeIssues: inout [PlanningArtifactDecodeIssue]
    ) -> T? {
        guard let artifact else {
            return nil
        }

        do {
            try validatePlanningArtifactIntegrity(artifact)
            let data = try Data(contentsOf: artifactURL(for: artifact, projectRoot: projectRoot))
            return try JSONDecoder().decode(type, from: data)
        } catch {
            decodeIssues.append(
                PlanningArtifactDecodeIssue(
                    artifactRole: role,
                    artifactPath: artifact.reference.locator.location.value,
                    message: error.localizedDescription
                )
            )
            return nil
        }
    }

    private func validatePlanningArtifactIntegrity(_ artifact: FlowRunReviewArtifact) throws {
        guard let integrity = artifact.integrity else {
            throw RunReviewServiceError.planningArtifactIntegrityUnverified(
                path: artifact.reference.locator.location.value,
                status: "missing",
                message: "Artifact integrity was not recorded."
            )
        }
        guard integrity.status == .verified else {
            throw RunReviewServiceError.planningArtifactIntegrityUnverified(
                path: artifact.reference.locator.location.value,
                status: integrity.status.rawValue,
                message: integrity.message
            )
        }
    }

    private func riskReviews(
        for plan: XcircuiteCandidatePlan,
        approvals: [FlowApprovalRecord]
    ) -> [XcircuitePlanRiskReview] {
        let approvalsByID = Dictionary(uniqueKeysWithValues: approvals.map { ($0.stageID, $0) })
        return plan.riskClassifications.map { risk in
            let approvalReviews = risk.requiredApprovals.map { approvalReview(for: $0, approvalsByID: approvalsByID) }
            return XcircuitePlanRiskReview(
                riskID: risk.riskID,
                category: risk.category,
                severity: risk.severity,
                scope: risk.scope,
                status: riskStatus(for: risk, approvalReviews: approvalReviews),
                description: risk.description,
                affectedObjectiveIDs: risk.affectedObjectiveIDs,
                affectedActionIDs: risk.affectedActionIDs,
                affectedStepIDs: affectedStepIDs(for: risk, plan: plan),
                requiredApprovals: risk.requiredApprovals,
                approvalReviews: approvalReviews,
                mitigationActions: risk.mitigationActions
            )
        }
    }

    private func approvalReview(
        for approvalID: String,
        approvalsByID: [String: FlowApprovalRecord]
    ) -> XcircuitePlanApprovalReview {
        guard let approval = approvalsByID[approvalID] else {
            return XcircuitePlanApprovalReview(approvalID: approvalID, status: "missing")
        }
        return XcircuitePlanApprovalReview(
            approvalID: approvalID,
            status: approval.verdict.rawValue,
            reviewer: approval.reviewer,
            note: approval.note.isEmpty ? nil : approval.note,
            decidedAt: approval.createdAt
        )
    }

    private func riskStatus(
        for risk: XcircuitePlanningRiskClassification,
        approvalReviews: [XcircuitePlanApprovalReview]
    ) -> String {
        if risk.requiredApprovals.isEmpty && ["high", "critical"].contains(risk.severity) {
            return "blocked"
        }
        if approvalReviews.contains(where: { $0.status == "rejected" }) {
            return "approval-rejected"
        }
        if approvalReviews.contains(where: { $0.status == "missing" }) {
            return "approval-required"
        }
        if !approvalReviews.isEmpty {
            return "approved"
        }
        if !risk.mitigationActions.isEmpty {
            return "mitigation-required"
        }
        return "tracked"
    }

    private func affectedStepIDs(
        for risk: XcircuitePlanningRiskClassification,
        plan: XcircuiteCandidatePlan
    ) -> [String] {
        let affectedActionIDs = Set(risk.affectedActionIDs)
        let affectedObjectiveIDs = Set(risk.affectedObjectiveIDs)
        if affectedActionIDs.isEmpty && affectedObjectiveIDs.isEmpty {
            return plan.steps.map(\.stepID)
        }
        return plan.steps.compactMap { step in
            if affectedActionIDs.contains(step.actionID) {
                return step.stepID
            }
            if step.sourceObjectiveIDs.contains(where: { affectedObjectiveIDs.contains($0) }) {
                return step.stepID
            }
            return nil
        }
    }

    private func latestArtifact(
        role: String,
        in artifacts: [FlowRunReviewArtifact]
    ) -> FlowRunReviewArtifact? {
        artifacts.last { $0.purpose.rawValue == role }
    }

    private func artifactURL(for artifact: FlowRunReviewArtifact, projectRoot: URL) -> URL {
        if artifact.reference.locator.location.value.hasPrefix("/") {
            URL(filePath: artifact.reference.locator.location.value)
        } else {
            projectRoot.appending(path: artifact.reference.locator.location.value)
        }
    }
}
