import Foundation
import DesignFlowKernel
import Xcircuite
import XcircuitePackage

/// The review cockpit's data layer: everything it shows is read from
/// the `.xcircuite` run ledger — the same record the flow kernel and
/// the agents write — and the only thing it writes back is the human
/// decision (an approval record the kernel's approval gate consumes).
public struct RunReviewService: Sendable {

    /// One run as the reviewer sees it: the manifest verdict, each
    /// stage's gates and artifacts, and any decisions already taken.
    public struct RunReview: Sendable {
        public let runID: String
        public let status: XcircuiteRunStatus
        public let artifacts: [XcircuiteFileReference]
        public let stages: [StageReview]
        public let approvals: [XcircuiteApprovalRecord]
        public let suggestedCommandSelections: [XcircuiteSuggestedCommandSelection]
        public let planning: PlanningReview
        public let signoff: RunReviewSignoffSummary
        public let waivers: RunReviewWaiverSummary
        public let failureStates: RunReviewFailureStateSummary
        public let flowReview: RunReviewFlowReviewProjection
        public let retainedDashboard: RunReviewRetainedDashboardProjection
        public let bundle: FlowRunReviewBundle
    }

    public struct PlanningReview: Sendable, Hashable {
        public let candidatePlanArtifact: FlowRunReviewArtifact?
        public let planVerificationArtifact: FlowRunReviewArtifact?
        public let candidatePlan: XcircuiteCandidatePlan?
        public let planVerification: XcircuitePlanVerification?
        public let designDiff: XcircuiteDesignDiff?
        public let designDiffSummary: RunReviewDesignDiffSummary?
        public let correctnessItems: [FlowRunReviewItem]
        public let selectedCommands: [XcircuiteSuggestedCommandSelection]
        public let decodeIssues: [PlanningArtifactDecodeIssue]

        public var hasContent: Bool {
            candidatePlanArtifact != nil
                || planVerificationArtifact != nil
                || candidatePlan != nil
                || planVerification != nil
                || designDiff != nil
                || designDiffSummary != nil
                || !correctnessItems.isEmpty
                || !selectedCommands.isEmpty
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
        public let approval: XcircuiteApprovalRecord?
        /// True when the stage carries an approval gate that is still
        /// incomplete — the run is waiting on this reviewer.
        public var awaitingApproval: Bool {
            result.gates.contains { $0.gateID == "approval" && $0.status == .incomplete }
        }
    }

    let store: XcircuitePackageStore
    let ledgerLoader: any FlowRunLedgerLoading
    let reviewBundler: any FlowRunReviewBundling

    public init(
        store: XcircuitePackageStore = XcircuitePackageStore(),
        ledgerLoader: any FlowRunLedgerLoading = FlowRunLedgerLoader(),
        reviewBundler: any FlowRunReviewBundling = DefaultFlowRunReviewBundler()
    ) {
        self.store = store
        self.ledgerLoader = ledgerLoader
        self.reviewBundler = reviewBundler
    }

    /// Every run the project manifest lists, newest last.
    public func listRuns(projectRoot: URL) throws -> [XcircuiteRunReference] {
        try store.loadManifest(forProjectAt: projectRoot).runs
    }

    /// The full review picture of one run, straight from the ledger.
    public func loadRun(runID: String, projectRoot: URL) throws -> RunReview {
        let ledger = try ledgerLoader.loadRunLedger(runID: runID, projectRoot: projectRoot)
        let bundle = try reviewBundler.makeReviewBundle(runID: runID, projectRoot: projectRoot)
        let approvals = bundle.approvals
        let suggestedCommandSelections = try store.loadSuggestedCommandSelections(
            runID: runID,
            inProjectAt: projectRoot
        )
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
            suggestedCommandSelections: suggestedCommandSelections
        )
        let signoff = signoffReview(
            bundle: bundle,
            actions: ledger.actions,
            projectRoot: projectRoot
        )
        let waivers = waiverReview(
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
        let flowReview = RunReviewFlowReviewProjection(bundle: bundle)
        let retainedDashboard = retainedDashboardProjection(bundle: bundle)

        return RunReview(
            runID: runID,
            status: Self.xcircuiteStatus(from: bundle.status),
            artifacts: ledger.runManifest.artifacts,
            stages: stages,
            approvals: approvals,
            suggestedCommandSelections: suggestedCommandSelections,
            planning: planning,
            signoff: signoff,
            waivers: waivers,
            failureStates: failureStates,
            flowReview: flowReview,
            retainedDashboard: retainedDashboard,
            bundle: bundle
        )
    }

    public func loadReviewBundle(runID: String, projectRoot: URL) throws -> FlowRunReviewBundle {
        try reviewBundler.makeReviewBundle(runID: runID, projectRoot: projectRoot)
    }

    public func loadSuggestedCommandSelections(
        runID: String,
        projectRoot: URL
    ) throws -> [XcircuiteSuggestedCommandSelection] {
        try store.loadSuggestedCommandSelections(runID: runID, inProjectAt: projectRoot)
    }

    public func recordSuggestedCommandSelection(
        runID: String,
        nextActionID: String,
        commandID: String,
        reviewer: String,
        projectRoot: URL
    ) throws -> XcircuiteRunActionRecord {
        let bundle = try reviewBundler.makeReviewBundle(runID: runID, projectRoot: projectRoot)
        guard let nextAction = bundle.summary.nextActions.first(where: { $0.actionID == nextActionID }) else {
            throw RunReviewServiceError.nextActionNotFound(actionID: nextActionID)
        }
        guard let command = nextAction.suggestedCommands.first(where: { $0.commandID == commandID }) else {
            throw RunReviewServiceError.suggestedCommandNotFound(
                actionID: nextActionID,
                commandID: commandID
            )
        }

        let record = XcircuiteRunActionRecord(
            actionID: "suggested-command-selection-\(UUID().uuidString)",
            runID: runID,
            actor: XcircuiteRunActionActor(kind: .human, identifier: reviewer),
            actionKind: "review.selectSuggestedCommand",
            status: .succeeded,
            metadata: [
                "nextActionID": .string(nextAction.actionID),
                "nextActionKind": .string(nextAction.kind),
                "commandID": .string(command.commandID),
                "readiness": .string(command.readiness.rawValue),
                "executable": .string(command.executable),
                "arguments": .array(command.arguments.map { .string($0) }),
                "reason": .string(command.reason),
            ]
        )
        try store.appendRunAction(record, inProjectAt: projectRoot)
        return record
    }

    public func decidePlanningRiskApproval(
        runID: String,
        approvalID: String,
        verdict: XcircuiteApprovalRecord.Verdict,
        reviewer: String,
        reviewerKind: XcircuiteRunActionActor.Kind = .human,
        note: String = "",
        projectRoot: URL
    ) throws -> XcircuiteCandidatePlanRiskApprovalResult {
        try XcircuiteCandidatePlanRiskApprovalRecorder(packageStore: store).recordApproval(
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
        verdict: XcircuiteApprovalRecord.Verdict,
        reviewer: String,
        reviewerKind: XcircuiteRunActionActor.Kind = .human,
        note: String = "",
        projectRoot: URL
    ) throws -> XcircuiteApprovalRecord {
        let record = XcircuiteApprovalRecord(
            runID: runID,
            stageID: stageID,
            verdict: verdict,
            reviewer: reviewer,
            reviewerKind: reviewerKind,
            note: note
        )
        try store.recordApprovalAction(
            record,
            metadata: [
                "source": .string("circuit-studio.run-review"),
            ],
            inProjectAt: projectRoot
        )
        return record
    }

    private static func xcircuiteStatus(from status: FlowRunStatus) -> XcircuiteRunStatus {
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
        approvals: [XcircuiteApprovalRecord],
        designDiff: XcircuiteDesignDiff?,
        suggestedCommandSelections: [XcircuiteSuggestedCommandSelection]
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
            selectedCommands: suggestedCommandSelections,
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
                    artifactPath: artifact.path,
                    message: error.localizedDescription
                )
            )
            return nil
        }
    }

    private func validatePlanningArtifactIntegrity(_ artifact: FlowRunReviewArtifact) throws {
        guard let integrity = artifact.integrity else {
            throw RunReviewServiceError.planningArtifactIntegrityUnverified(
                path: artifact.path,
                status: "missing",
                message: "Artifact integrity was not recorded."
            )
        }
        guard integrity.status == .verified else {
            throw RunReviewServiceError.planningArtifactIntegrityUnverified(
                path: artifact.path,
                status: integrity.status.rawValue,
                message: integrity.message
            )
        }
    }

    private func riskReviews(
        for plan: XcircuiteCandidatePlan,
        approvals: [XcircuiteApprovalRecord]
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
        approvalsByID: [String: XcircuiteApprovalRecord]
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
        artifacts.last { $0.role == role }
    }

    private func artifactURL(for artifact: FlowRunReviewArtifact, projectRoot: URL) -> URL {
        if artifact.path.hasPrefix("/") {
            URL(filePath: artifact.path)
        } else {
            projectRoot.appending(path: artifact.path)
        }
    }
}
