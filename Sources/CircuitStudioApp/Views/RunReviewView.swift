import Foundation
import SwiftUI
import DesignFlowKernel
import Xcircuite
import XcircuitePackage

/// The review cockpit: runs, stage gates and artifacts straight from
/// the `.xcircuite` ledger, with approve/reject actions that persist
/// the decision the flow kernel's approval gate consumes. Humans and
/// agents read the same record; this view adds nothing to it.
public struct RunReviewView: View {
    private enum ReviewSection: String, CaseIterable, Identifiable {
        case design = "Design"
        case verification = "Verification"
        case artifacts = "Artifacts"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .design: "cpu"
            case .verification: "checkmark.shield"
            case .artifacts: "archivebox"
            }
        }
    }

    public let projectRoot: URL
    public let reviewer: String

    @State private var runs: [XcircuiteRunSnapshot] = []
    @State private var selectedRunID: String?
    @State private var review: RunReviewService.RunReview?
    @State private var designEvidence: RunReviewDesignEvidence?
    @State private var loadingDesignEvidenceSignature: String?
    @State private var selectedReviewSection: ReviewSection = .design
    @State private var note: String = ""
    @State private var planningApprovalNotes: [String: String] = [:]
    @State private var waiverReviewNotes: [String: String] = [:]
    @State private var waiverEditProposalNotes: [String: String] = [:]
    @State private var waiverEditApplicationNotes: [String: String] = [:]
    @State private var waiverEditVerificationContext: RunReviewWaiverEditVerificationContext?
    @State private var waiverEditVerificationContextError: String?
    @State private var artifactPreviews: [String: RunReviewArtifactPreview] = [:]
    @State private var artifactPreviewErrors: [String: String] = [:]
    @State private var waveformSignalSelections: [String: Set<String>] = [:]
    @State private var waveformComparisonSelections: [String: String] = [:]
    @State private var signoffRepairPlanningInFlight: Set<String> = []
    @State private var signoffRepairPlanningErrors: [String: String] = [:]
    @State private var signoffRepairPlanningResults: [String: RunReviewSignoffRepairPlanningResult] = [:]
    @State private var signoffRepairCandidateCycleInFlight: Set<String> = []
    @State private var signoffRepairCandidateCycleErrors: [String: String] = [:]
    @State private var signoffRepairCandidateCycleResults: [String: RunReviewSignoffRepairCandidateCycleResult] = [:]
    @State private var loadError: String?

    private let service = RunReviewService()
    private let observer = XcircuiteRunLedgerObserver()

    public init(projectRoot: URL, reviewer: String) {
        self.projectRoot = projectRoot
        self.reviewer = reviewer
    }

    public var body: some View {
        NavigationSplitView {
            List(runs, id: \.runID, selection: $selectedRunID) { run in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(run.runID)
                            .lineLimit(1)
                        Text("\(run.manifest.actor.identifier) (\(run.manifest.actor.kind.rawValue))")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(
                            run.manifest.updatedAt,
                            format: .dateTime.year().month().day().hour().minute()
                        )
                        .lineLimit(1)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusBadge(run.status)
                }
                .tag(run.runID)
            }
            .navigationTitle("Runs")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            if let review {
                reviewDetail(review)
            } else if let loadError {
                ContentUnavailableView(
                    "Run could not be loaded",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ContentUnavailableView(
                    "Select a run",
                    systemImage: "list.bullet.rectangle"
                )
            }
        }
        .task { await observeRuns() }
        .onChange(of: selectedRunID) { _, _ in reloadReview() }
    }

    // MARK: - Detail

    @ViewBuilder
    private func reviewDetail(_ review: RunReviewService.RunReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(review.runID).font(.title2).bold()
                    statusBadge(review.status)
                    Spacer()
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("Actor")
                            .foregroundStyle(.secondary)
                        Text("\(review.actor.identifier) (\(review.actor.kind.rawValue))")
                    }
                    lifecycleRow(label: "Created", date: review.createdAt)
                    lifecycleRow(label: "Updated", date: review.updatedAt)
                    if let startedAt = review.startedAt {
                        lifecycleRow(label: "Started", date: startedAt)
                    }
                    if let finishedAt = review.finishedAt {
                        lifecycleRow(label: "Finished", date: finishedAt)
                    }
                }
                .font(.caption)
                if let intent = review.intent, !intent.isEmpty {
                    Text(intent)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }

                Picker("Review section", selection: $selectedReviewSection) {
                    ForEach(ReviewSection.allCases) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 480)

                switch selectedReviewSection {
                case .design:
                    designReviewContent(review)
                case .verification:
                    verificationReviewContent(review)
                case .artifacts:
                    artifactReviewContent(review)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func designReviewContent(_ review: RunReviewService.RunReview) -> some View {
        if let designEvidence,
           designEvidence.runID == review.runID,
           designEvidence.hasContent {
            RunReviewDesignEvidenceView(evidence: designEvidence)
                .id("\(review.runID)#\(designEvidence.sourceSignature)")
        } else if loadingDesignEvidenceSignature != nil {
            GroupBox("Design") {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        } else {
            ContentUnavailableView(
                "No displayable design artifacts",
                systemImage: "square.stack.3d.up.slash",
                description: Text("This run does not contain verified circuit, layout, or waveform artifacts.")
            )
            .frame(maxWidth: .infinity, minHeight: 240)
        }
    }

    @ViewBuilder
    private func verificationReviewContent(_ review: RunReviewService.RunReview) -> some View {
        if !review.bundle.reviewItems.isEmpty {
            RunReviewItemList(items: review.bundle.reviewItems)
        }
        if review.failureStates.hasContent {
            RunReviewFailureStateReviewCard(summary: review.failureStates)
        }
        if review.retainedDashboard.hasContent {
            RunReviewRetainedDashboardCard(projection: review.retainedDashboard)
        }
        if review.flowReview.hasContent {
            RunReviewFlowReviewProjectionCard(projection: review.flowReview)
        }
        if !review.bundle.summary.nextActions.isEmpty {
            RunReviewNextActionList(
                actions: review.bundle.summary.nextActions,
                selections: review.suggestedCommandSelections,
                recordSelection: { action, command in
                    recordSuggestedCommandSelection(
                        action,
                        command: command,
                        runID: review.runID
                    )
                }
            )
        }
        if review.planning.hasContent {
            RunReviewPlanningReviewCard(
                planning: review.planning,
                runID: review.runID,
                planningApprovalNotes: $planningApprovalNotes,
                decideRiskApproval: { verdict, approvalID, runID in
                    decidePlanningRiskApproval(
                        verdict,
                        approvalID: approvalID,
                        runID: runID
                    )
                }
            )
        }
        if review.signoff.hasContent {
            signoffReviewCard(review.signoff, runID: review.runID)
        }
        let drilldown = service.interactiveSignoffDrilldown(from: review)
        if drilldown.hasContent {
            RunReviewInteractiveSignoffDrilldownCard(drilldown: drilldown)
        }
        if review.waivers.hasContent {
            waiverReviewCard(
                review.waivers,
                runID: review.runID,
                verificationContext: waiverEditVerificationContext,
                verificationContextError: waiverEditVerificationContextError
            )
        }
        ForEach(review.stages, id: \.result.stageID) { stage in
            RunReviewStageCard(
                stage: stage,
                note: $note,
                decide: { verdict, stageID in
                    decide(verdict, stageID: stageID, runID: review.runID)
                }
            )
        }
    }

    @ViewBuilder
    private func artifactReviewContent(_ review: RunReviewService.RunReview) -> some View {
        if review.bundle.artifacts.isEmpty {
            ContentUnavailableView(
                "No run artifacts",
                systemImage: "archivebox"
            )
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            RunReviewArtifactList(artifacts: review.bundle.artifacts)
        }
    }

    private func lifecycleRow(label: String, date: Date) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(date, format: .dateTime.year().month().day().hour().minute().second())
                .textSelection(.enabled)
        }
    }


    @ViewBuilder
    private func signoffReviewCard(
        _ signoff: RunReviewSignoffSummary,
        runID: String
    ) -> some View {
        GroupBox("Verification Results") {
            VStack(alignment: .leading, spacing: 10) {
                RunReviewSignoffRepairPlanningPanel(
                    signoff: signoff,
                    runID: runID,
                    planningInFlight: signoffRepairPlanningInFlight.contains(runID),
                    candidateCycleInFlight: signoffRepairCandidateCycleInFlight.contains(runID),
                    planningResult: signoffRepairPlanningResults[runID],
                    candidateCycleResult: signoffRepairCandidateCycleResults[runID],
                    planningError: signoffRepairPlanningErrors[runID],
                    candidateCycleError: signoffRepairCandidateCycleErrors[runID],
                    formulateRepairPlanning: {
                        formulateSignoffRepairPlanning(runID: runID)
                    },
                    runCandidateCycle: {
                        runSignoffRepairCandidateCycle(runID: runID)
                    }
                )
                ForEach(signoff.cards, id: \.artifact.path) { card in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: signoffIcon(card))
                                .foregroundStyle(signoffColor(card))
                            Text(card.title)
                                .font(.subheadline.weight(.semibold))
                            Text(card.domain)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Spacer()
                            planningStatusBadge(card.status)
                        }
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                            alignment: .leading,
                            spacing: 4
                        ) {
                            ForEach(card.primaryMetrics, id: \.label) { metric in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(metric.label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(metric.value)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                }
                            }
                        }
                        RunReviewSignoffWaveformComparisonDrilldown(
                            card: card,
                            runID: runID,
                            artifactPreviews: artifactPreviews,
                            waveformComparisonSelections: $waveformComparisonSelections,
                            loadArtifactPreviews: { artifacts in
                                loadArtifactPreviews(artifacts, runID: runID)
                            }
                        )
                        RunReviewSignoffDetailSectionList(sections: card.detailSections)
                        if !card.issues.isEmpty {
                            ForEach(Array(card.issues.enumerated()), id: \.offset) { _, issue in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: planningStatusIcon(issue.severity))
                                        .foregroundStyle(planningStatusColor(issue.severity))
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(issue.label)
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.secondary)
                                            if let count = issue.count {
                                                Text("\(count)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        if !issue.message.isEmpty {
                                            Text(issue.message)
                                                .font(.caption)
                                                .lineLimit(2)
                                        }
                                        if !issue.suggestedFixes.isEmpty {
                                            Text(issue.suggestedFixes.joined(separator: ", "))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        signoffIssueRepairActions(issue.repairActionHints)
                                        RunReviewSignoffIssueDetailDisclosure(rows: issue.detailRows)
                                        RunReviewSignoffIssueEvidenceDrilldown(
                                            issue: issue,
                                            runID: runID,
                                            artifactPreviews: artifactPreviews,
                                            artifactPreviewErrors: artifactPreviewErrors,
                                            waveformSignalSelections: $waveformSignalSelections,
                                            loadArtifactPreview: { artifact in
                                                loadArtifactPreview(artifact, runID: runID)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                        RunReviewSignoffArtifactDrilldown(
                            card: card,
                            runID: runID,
                            artifactPreviews: artifactPreviews,
                            artifactPreviewErrors: artifactPreviewErrors,
                            waveformSignalSelections: $waveformSignalSelections,
                            loadArtifactPreview: { artifact in
                                loadArtifactPreview(artifact, runID: runID)
                            }
                        )
                    }
                    .padding(.vertical, 3)
                }
                if !signoff.decodeIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Verification Decode Issues")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(signoff.decodeIssues, id: \.artifactPath) { issue in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.artifactPath)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Text(issue.message)
                                        .font(.caption)
                                        .lineLimit(3)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func signoffIssueRepairActions(
        _ actions: [RunReviewSignoffRepairActionHint]
    ) -> some View {
        if !actions.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(actions, id: \.operationID) { action in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(action.domainID)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(action.operationID)
                                    .font(.caption2.monospaced())
                                Text(action.maturity)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(action.reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 112), spacing: 6)],
                                alignment: .leading,
                                spacing: 3
                            ) {
                                if !action.requiredInputRefs.isEmpty {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Inputs")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(action.requiredInputRefs.joined(separator: ", "))
                                            .font(.caption2.monospaced())
                                            .lineLimit(1)
                                    }
                                }
                                if !action.verificationGates.isEmpty {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Gates")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(action.verificationGates.joined(separator: ", "))
                                            .font(.caption2.monospaced())
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 3)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .foregroundStyle(.secondary)
                    Text("Repair Actions")
                        .font(.caption2.weight(.semibold))
                    Text("\(actions.count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func waiverReviewCard(
        _ waivers: RunReviewWaiverSummary,
        runID: String,
        verificationContext: RunReviewWaiverEditVerificationContext?,
        verificationContextError: String?
    ) -> some View {
        GroupBox("Waiver Reviews") {
            VStack(alignment: .leading, spacing: 10) {
                waiverEditVerificationContextRow(
                    verificationContext,
                    error: verificationContextError
                )
                ForEach(waivers.items, id: \.waiverReviewID) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: waiverIcon(item))
                                .foregroundStyle(planningStatusColor(item.status))
                            Text(item.domain)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            planningStatusBadge(item.status)
                        }
                        HStack(spacing: 10) {
                            Text("waived \(item.waivedCount)")
                                .font(.caption.monospaced())
                            if !item.unusedWaiverIDs.isEmpty {
                                Text("unused \(item.unusedWaiverIDs.count)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.orange)
                            }
                        }
                        if !item.waivedBuckets.isEmpty {
                            ForEach(Array(item.waivedBuckets.enumerated()), id: \.offset) { _, bucket in
                                HStack(spacing: 6) {
                                    Text(bucket.label)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                    Text("\(bucket.count)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if !bucket.message.isEmpty {
                                        Text(bucket.message)
                                            .font(.caption)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                            }
                        }
                        if !item.unusedWaiverIDs.isEmpty {
                            Text(item.unusedWaiverIDs.joined(separator: ", "))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if !item.sourceReferences.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Source Lineage")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(Array(item.sourceReferences.enumerated()), id: \.offset) { _, source in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(source.waiverID)
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.secondary)
                                            Text(source.locationLabel)
                                                .font(.caption2.monospaced())
                                                .lineLimit(1)
                                            Spacer()
                                        }
                                        HStack(spacing: 6) {
                                            if let ruleID = source.ruleID {
                                                Text(ruleID)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if let diagnosticID = source.diagnosticID {
                                                Text(diagnosticID)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if !source.reason.isEmpty {
                                                Text(source.reason)
                                                    .font(.caption2)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if !item.editProposals.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Edit Proposals")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(item.editProposals, id: \.proposalID) { proposal in
                                    let selected = item.editProposalSelections.last {
                                        $0.proposalID == proposal.proposalID
                                    }
                                    let applied = item.editApplications.last {
                                        $0.proposalID == proposal.proposalID
                                    }
                                    let verified = item.editVerifications.last {
                                        $0.proposalID == proposal.proposalID
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(proposal.kind)
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.secondary)
                                            Text(proposal.status)
                                                .font(.caption2)
                                                .foregroundStyle(planningStatusColor(proposal.status))
                                            Text(proposal.risk)
                                                .font(.caption2)
                                                .foregroundStyle(planningStatusColor(proposal.risk))
                                            Spacer()
                                            if let selected {
                                                Text("Selected by \(selected.actor)")
                                                    .font(.caption2)
                                                    .foregroundStyle(Color.accentColor)
                                            }
                                            if let applied {
                                                Text("Applied by \(applied.actor)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.green)
                                            }
                                            if let verified {
                                                Text("Verified \(verified.status)")
                                                    .font(.caption2)
                                                    .foregroundStyle(planningStatusColor(verified.status))
                                            }
                                        }
                                        Text(proposal.summary)
                                            .font(.caption)
                                            .lineLimit(2)
                                        Text("\(proposal.operation) \(proposal.targetPath)")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                        if let verified {
                                            waiverEditVerificationDrilldown(verified)
                                            Text("Feedback \(verified.planningFeedbackStatus)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                            if let rejectedPlansPath = verified.rejectedPlansPath {
                                                Text(rejectedPlansPath)
                                                    .font(.caption2.monospaced())
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Text(verified.verificationReportPath)
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        HStack(spacing: 6) {
                                            TextField(
                                                "Proposal note",
                                                text: Binding(
                                                    get: {
                                                        waiverEditProposalNotes[
                                                            waiverEditProposalNoteKey(
                                                                item: item,
                                                                proposal: proposal
                                                            ),
                                                            default: ""
                                                        ]
                                                    },
                                                    set: {
                                                        waiverEditProposalNotes[
                                                            waiverEditProposalNoteKey(
                                                                item: item,
                                                                proposal: proposal
                                                            )
                                                        ] = $0
                                                    }
                                                )
                                            )
                                            .textFieldStyle(.roundedBorder)
                                            Button {
                                                recordWaiverEditProposalSelection(
                                                    item,
                                                    proposal: proposal,
                                                    runID: runID
                                                )
                                            } label: {
                                                Label("Record", systemImage: "bookmark")
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                        if applied == nil {
                                            HStack(spacing: 6) {
                                                TextField(
                                                    "Apply note",
                                                    text: Binding(
                                                        get: {
                                                            waiverEditApplicationNotes[
                                                                waiverEditProposalNoteKey(
                                                                    item: item,
                                                                    proposal: proposal
                                                                ),
                                                                default: ""
                                                            ]
                                                        },
                                                        set: {
                                                            waiverEditApplicationNotes[
                                                                waiverEditProposalNoteKey(
                                                                    item: item,
                                                                    proposal: proposal
                                                                )
                                                            ] = $0
                                                        }
                                                    )
                                                )
                                                .textFieldStyle(.roundedBorder)
                                                Button {
                                                    applyWaiverEditProposal(
                                                        item,
                                                        proposal: proposal,
                                                        runID: runID
                                                    )
                                                } label: {
                                                    Label("Apply", systemImage: "checkmark.square")
                                                }
                                                .buttonStyle(.borderedProminent)
                                                Button {
                                                    applyAndVerifyWaiverEditProposal(
                                                        item,
                                                        proposal: proposal,
                                                        runID: runID
                                                    )
                                                } label: {
                                                    Label("Apply + Verify", systemImage: "checkmark.seal")
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .disabled(verificationContext == nil)
                                            }
                                        } else if verified == nil {
                                            HStack(spacing: 6) {
                                                TextField(
                                                    "Verification note",
                                                    text: Binding(
                                                        get: {
                                                            waiverEditApplicationNotes[
                                                                waiverEditProposalNoteKey(
                                                                    item: item,
                                                                    proposal: proposal
                                                                ),
                                                                default: ""
                                                            ]
                                                        },
                                                        set: {
                                                            waiverEditApplicationNotes[
                                                                waiverEditProposalNoteKey(
                                                                    item: item,
                                                                    proposal: proposal
                                                                )
                                                            ] = $0
                                                        }
                                                    )
                                                )
                                                .textFieldStyle(.roundedBorder)
                                                Button {
                                                    verifyWaiverEditProposal(
                                                        item,
                                                        proposal: proposal,
                                                        runID: runID
                                                    )
                                                } label: {
                                                    Label("Verify", systemImage: "checkmark.seal")
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .disabled(verificationContext == nil)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        if let decision = item.latestDecision {
                            Text("\(decision.decision.rawValue) by \(decision.actor)\(decision.note.isEmpty ? "" : " — \(decision.note)")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if item.latestDecision?.decision != .approved {
                            HStack(spacing: 6) {
                                TextField(
                                    "Waiver review note",
                                    text: Binding(
                                        get: { waiverReviewNotes[item.waiverReviewID, default: ""] },
                                        set: { waiverReviewNotes[item.waiverReviewID] = $0 }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                Button("Approve") {
                                    decideWaiverReview(
                                        .approved,
                                        waiverReviewID: item.waiverReviewID,
                                        runID: runID
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Reject") {
                                    decideWaiverReview(
                                        .rejected,
                                        waiverReviewID: item.waiverReviewID,
                                        runID: runID
                                    )
                                }
                            }
                        }
                        Text(item.artifact.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(integrityColor(item.artifact.integrity?.status))
                            .lineLimit(2)
                    }
                    .padding(.vertical, 3)
                }
                if !waivers.decodeIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Waiver Decode Issues")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(waivers.decodeIssues, id: \.artifactPath) { issue in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.artifactPath)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Text(issue.message)
                                        .font(.caption)
                                        .lineLimit(3)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func waiverEditVerificationContextRow(
        _ context: RunReviewWaiverEditVerificationContext?,
        error: String?
    ) -> some View {
        if let context {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Post-edit verification context")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(context.designUnitArtifact == nil ? "design-unit inferred" : "design-unit artifact")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(context.designSpecArtifact.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(context.layoutDocumentArtifact.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let designUnitArtifact = context.designUnitArtifact {
                    Text(designUnitArtifact.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else if let error {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    @ViewBuilder
    private func waiverEditVerificationDrilldown(
        _ verification: RunReviewWaiverEditVerification
    ) -> some View {
        if let summary = verification.reportSummary {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    verificationSummaryLine(
                        "DRC",
                        status: summary.drc.passed ? "passed" : "failed",
                        detail: "\(summary.drc.violationCount) violation(s)"
                    )
                    verificationBucketList(summary.drc.violationsByKind)
                    verificationSummaryLine(
                        "LVS",
                        status: summary.lvs.passed ? "passed" : "failed",
                        detail: summary.lvs.schematicHashMatches ? "schematic hash matched" : "schematic hash mismatch"
                    )
                    verificationBucketList(summary.lvs.issueCounts)
                    verificationSummaryLine(
                        "Ready for PEX",
                        status: summary.readyForPEX ? "passed" : "failed",
                        detail: summary.readyForPEX ? "ready" : "blocked"
                    )
                    verificationOptionalGateLine(
                        "Layout trust",
                        passed: summary.layoutTrustPassed
                    )
                    verificationOptionalGateLine(
                        "External signoff",
                        passed: summary.externalSignoffPassed
                    )
                    if let externalReady = summary.externalSignoffReadyForPEX {
                        verificationSummaryLine(
                            "External PEX readiness",
                            status: externalReady ? "passed" : "failed",
                            detail: externalReady ? "ready" : "blocked"
                        )
                    }
                }
                .padding(.top, 3)
            } label: {
                HStack(spacing: 6) {
                    planningStatusBadge(summary.status)
                    Text("Post-edit verification")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(summary.readyForPEX ? "PEX ready" : "PEX blocked")
                        .font(.caption2)
                        .foregroundStyle(planningStatusColor(summary.readyForPEX ? "passed" : "failed"))
                }
            }
        } else {
            Text("DRC \(verification.drcPassed ? "passed" : "failed") (\(verification.drcViolationCount)) / LVS \(verification.lvsPassed ? "passed" : "failed") / ready \(verification.readyForPEX ? "yes" : "no")")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func verificationSummaryLine(
        _ title: String,
        status: String,
        detail: String
    ) -> some View {
        HStack(spacing: 6) {
            planningStatusBadge(status)
            Text(title)
                .font(.caption)
            Spacer()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func verificationOptionalGateLine(
        _ title: String,
        passed: Bool?
    ) -> some View {
        if let passed {
            verificationSummaryLine(
                title,
                status: passed ? "passed" : "failed",
                detail: passed ? "passed" : "failed"
            )
        }
    }

    @ViewBuilder
    private func verificationBucketList(
        _ buckets: [RunReviewWaiverVerificationBucket]
    ) -> some View {
        if !buckets.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(buckets, id: \.label) { bucket in
                    HStack(spacing: 6) {
                        Text(bucket.label)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(bucket.count)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.leading, 10)
        }
    }







    private func recordSuggestedCommandSelection(
        _ action: FlowRunNextAction,
        command: FlowRunSuggestedCommand,
        runID: String
    ) {
        do {
            _ = try service.recordSuggestedCommandSelection(
                runID: runID,
                nextActionID: action.actionID,
                commandID: command.commandID,
                reviewer: reviewer,
                projectRoot: projectRoot
            )
            reloadReview()
        } catch {
            loadError = error.localizedDescription
        }
    }


    // MARK: - Actions

    @MainActor
    private func observeRuns() async {
        do {
            let updates = await observer.snapshots(projectRoot: projectRoot)
            for try await snapshots in updates {
                guard !Task.isCancelled else {
                    break
                }
                runs = snapshots
                if let selectedRunID,
                   !snapshots.contains(where: { $0.runID == selectedRunID }) {
                    self.selectedRunID = nil
                }
                if selectedRunID == nil {
                    selectedRunID = snapshots.last?.runID
                } else {
                    reloadReview()
                }
                loadError = nil
            }
        } catch {
            runs = []
            loadError = error.localizedDescription
        }
        await observer.shutdown()
    }

    private func reloadReview() {
        guard let selectedRunID else {
            review = nil
            designEvidence = nil
            loadingDesignEvidenceSignature = nil
            waiverEditVerificationContext = nil
            waiverEditVerificationContextError = nil
            loadError = nil
            return
        }
        do {
            let loadedReview = try service.loadRun(runID: selectedRunID, projectRoot: projectRoot)
            review = loadedReview
            reloadDesignEvidence(for: loadedReview)
            do {
                waiverEditVerificationContext = try service.waiverEditVerificationContext(
                    review: loadedReview,
                    projectRoot: projectRoot
                )
                waiverEditVerificationContextError = nil
            } catch {
                waiverEditVerificationContext = nil
                waiverEditVerificationContextError = error.localizedDescription
            }
            loadError = nil
        } catch {
            review = nil
            designEvidence = nil
            loadingDesignEvidenceSignature = nil
            waiverEditVerificationContext = nil
            waiverEditVerificationContextError = nil
            loadError = error.localizedDescription
        }
    }

    private func reloadDesignEvidence(for review: RunReviewService.RunReview) {
        let signature = service.designEvidenceSignature(bundle: review.bundle)
        guard !signature.isEmpty else {
            designEvidence = nil
            loadingDesignEvidenceSignature = nil
            return
        }
        if designEvidence?.runID == review.runID,
           designEvidence?.sourceSignature == signature {
            loadingDesignEvidenceSignature = nil
            return
        }
        guard loadingDesignEvidenceSignature != signature else {
            return
        }

        loadingDesignEvidenceSignature = signature
        let runID = review.runID
        let bundle = review.bundle
        Task {
            let loaded = await service.loadDesignEvidence(
                runID: runID,
                bundle: bundle,
                projectRoot: projectRoot
            )
            guard selectedRunID == runID,
                  loadingDesignEvidenceSignature == signature else {
                return
            }
            designEvidence = loaded
            loadingDesignEvidenceSignature = nil
        }
    }

    private func decide(
        _ verdict: XcircuiteApprovalRecord.Verdict,
        stageID: String,
        runID: String
    ) {
        do {
            _ = try service.decide(
                runID: runID,
                stageID: stageID,
                verdict: verdict,
                reviewer: reviewer,
                note: note,
                projectRoot: projectRoot
            )
            note = ""
            reloadReview()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func decidePlanningRiskApproval(
        _ verdict: XcircuiteApprovalRecord.Verdict,
        approvalID: String,
        runID: String
    ) {
        do {
            _ = try service.decidePlanningRiskApproval(
                runID: runID,
                approvalID: approvalID,
                verdict: verdict,
                reviewer: reviewer,
                note: planningApprovalNotes[approvalID, default: ""],
                projectRoot: projectRoot
            )
            planningApprovalNotes[approvalID] = ""
            reloadReview()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func decideWaiverReview(
        _ decision: RunReviewWaiverDecisionValue,
        waiverReviewID: String,
        runID: String
    ) {
        do {
            _ = try service.decideWaiverReview(
                runID: runID,
                waiverReviewID: waiverReviewID,
                decision: decision,
                reviewer: reviewer,
                note: waiverReviewNotes[waiverReviewID, default: ""],
                projectRoot: projectRoot
            )
            waiverReviewNotes[waiverReviewID] = ""
            reloadReview()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func recordWaiverEditProposalSelection(
        _ item: RunReviewWaiverItem,
        proposal: RunReviewWaiverEditProposal,
        runID: String
    ) {
        let noteKey = waiverEditProposalNoteKey(item: item, proposal: proposal)
        do {
            _ = try service.recordWaiverEditProposalSelection(
                runID: runID,
                waiverReviewID: item.waiverReviewID,
                proposalID: proposal.proposalID,
                reviewer: reviewer,
                note: waiverEditProposalNotes[noteKey, default: ""],
                projectRoot: projectRoot
            )
            waiverEditProposalNotes[noteKey] = ""
            reloadReview()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func applyWaiverEditProposal(
        _ item: RunReviewWaiverItem,
        proposal: RunReviewWaiverEditProposal,
        runID: String
    ) {
        let noteKey = waiverEditProposalNoteKey(item: item, proposal: proposal)
        do {
            _ = try service.applyWaiverEditProposal(
                runID: runID,
                waiverReviewID: item.waiverReviewID,
                proposalID: proposal.proposalID,
                reviewer: reviewer,
                note: waiverEditApplicationNotes[noteKey, default: ""],
                projectRoot: projectRoot
            )
            waiverEditApplicationNotes[noteKey] = ""
            reloadReview()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func applyAndVerifyWaiverEditProposal(
        _ item: RunReviewWaiverItem,
        proposal: RunReviewWaiverEditProposal,
        runID: String
    ) {
        let noteKey = waiverEditProposalNoteKey(item: item, proposal: proposal)
        Task {
            do {
                _ = try await service.applyWaiverEditProposalAndRunPostVerification(
                    runID: runID,
                    waiverReviewID: item.waiverReviewID,
                    proposalID: proposal.proposalID,
                    reviewer: reviewer,
                    note: waiverEditApplicationNotes[noteKey, default: ""],
                    projectRoot: projectRoot
                )
                waiverEditApplicationNotes[noteKey] = ""
                reloadReview()
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private func verifyWaiverEditProposal(
        _ item: RunReviewWaiverItem,
        proposal: RunReviewWaiverEditProposal,
        runID: String
    ) {
        let noteKey = waiverEditProposalNoteKey(item: item, proposal: proposal)
        Task {
            do {
                _ = try await service.runPostWaiverEditVerification(
                    runID: runID,
                    waiverReviewID: item.waiverReviewID,
                    proposalID: proposal.proposalID,
                    reviewer: reviewer,
                    note: waiverEditApplicationNotes[noteKey, default: ""],
                    projectRoot: projectRoot
                )
                waiverEditApplicationNotes[noteKey] = ""
                reloadReview()
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private func formulateSignoffRepairPlanning(runID: String) {
        signoffRepairPlanningInFlight.insert(runID)
        Task {
            defer {
                signoffRepairPlanningInFlight.remove(runID)
            }

            do {
                let result = try service.formulateSignoffRepairPlanningProblem(
                    runID: runID,
                    actorKind: .human,
                    actorIdentifier: reviewer,
                    note: "Generated from RunReviewView.",
                    projectRoot: projectRoot
                )
                signoffRepairPlanningResults[runID] = result
                signoffRepairPlanningErrors[runID] = nil
                reloadReview()
            } catch {
                signoffRepairPlanningResults[runID] = nil
                signoffRepairPlanningErrors[runID] = error.localizedDescription
            }
        }
    }

    private func runSignoffRepairCandidateCycle(runID: String) {
        signoffRepairCandidateCycleInFlight.insert(runID)
        Task {
            defer {
                signoffRepairCandidateCycleInFlight.remove(runID)
            }

            do {
                let result = try await DesignFlowService().execute(DesignFlowCommand(
                    kind: .runSignoffRepairCandidateCycle,
                    projectRootPath: projectRoot.path(percentEncoded: false),
                    runID: runID,
                    approvalReviewer: reviewer,
                    approvalNote: "Dispatched from RunReviewView.",
                    actionActorKind: .human
                ))
                signoffRepairCandidateCycleResults[runID] = result.signoffRepairCandidateCycleResult
                signoffRepairCandidateCycleErrors[runID] = nil
                reloadReview()
            } catch {
                signoffRepairCandidateCycleResults[runID] = nil
                signoffRepairCandidateCycleErrors[runID] = error.localizedDescription
            }
        }
    }

    private func waiverEditProposalNoteKey(
        item: RunReviewWaiverItem,
        proposal: RunReviewWaiverEditProposal
    ) -> String {
        "\(item.waiverReviewID)#\(proposal.proposalID)"
    }

    private func loadArtifactPreview(
        _ artifact: FlowRunReviewArtifact,
        runID: String
    ) {
        let key = RunReviewArtifactPreviewKey.make(runID: runID, artifact: artifact)
        do {
            artifactPreviews[key] = try service.loadArtifactPreview(
                runID: runID,
                artifact: artifact,
                projectRoot: projectRoot
            )
            artifactPreviewErrors[key] = nil
        } catch {
            artifactPreviews[key] = nil
            artifactPreviewErrors[key] = error.localizedDescription
        }
    }

    private func loadArtifactPreviews(
        _ artifacts: [FlowRunReviewArtifact],
        runID: String
    ) {
        for artifact in artifacts {
            loadArtifactPreview(artifact, runID: runID)
        }
    }
}
