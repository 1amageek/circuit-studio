import SwiftUI
import DesignFlowKernel
import XcircuitePackage

/// The review cockpit: runs, stage gates and artifacts straight from
/// the `.xcircuite` ledger, with approve/reject actions that persist
/// the decision the flow kernel's approval gate consumes. Humans and
/// agents read the same record; this view adds nothing to it.
public struct RunReviewView: View {
    public let projectRoot: URL
    public let reviewer: String

    @State private var runs: [XcircuiteRunReference] = []
    @State private var selectedRunID: String?
    @State private var review: RunReviewService.RunReview?
    @State private var note: String = ""
    @State private var loadError: String?

    private let service = RunReviewService()

    public init(projectRoot: URL, reviewer: String) {
        self.projectRoot = projectRoot
        self.reviewer = reviewer
    }

    public var body: some View {
        NavigationSplitView {
            List(runs, id: \.runID, selection: $selectedRunID) { run in
                HStack {
                    Text(run.runID)
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
                    systemImage: "list.bullet.rectangle",
                    description: Text("Every verdict shown here is read from .xcircuite/runs.")
                )
            }
        }
        .task { reloadRuns() }
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
                ForEach(review.stages, id: \.result.stageID) { stage in
                    stageCard(stage, runID: review.runID)
                }
                if !review.artifacts.isEmpty {
                    artifactList(review.artifacts)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func stageCard(_ stage: RunReviewService.StageReview, runID: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(stage.result.gates, id: \.gateID) { gate in
                    HStack {
                        Image(systemName: gateIcon(gate.status))
                            .foregroundStyle(gateColor(gate.status))
                        Text(gate.gateID)
                        Spacer()
                        Text(String(describing: gate.status)).foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(stage.result.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                    Text("\(diagnostic.code): \(diagnostic.message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let approval = stage.approval {
                    Text("\(approval.verdict == .approved ? "Approved" : "Rejected") by \(approval.reviewer)\(approval.note.isEmpty ? "" : " — \(approval.note)")")
                        .font(.caption)
                }
                if stage.awaitingApproval {
                    HStack {
                        TextField("Review note", text: $note)
                            .textFieldStyle(.roundedBorder)
                        Button("Approve") {
                            decide(.approved, stageID: stage.result.stageID, runID: runID)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Reject") {
                            decide(.rejected, stageID: stage.result.stageID, runID: runID)
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(stage.result.stageID).font(.headline)
                Spacer()
                Text(String(describing: stage.result.status)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func artifactList(_ artifacts: [XcircuiteFileReference]) -> some View {
        GroupBox("Artifacts") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(artifacts, id: \.path) { artifact in
                    HStack {
                        Text(artifact.path).font(.caption.monospaced())
                        Spacer()
                        Text(artifact.format.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func reloadRuns() {
        do {
            runs = try service.listRuns(projectRoot: projectRoot)
            loadError = nil
        } catch {
            runs = []
            loadError = error.localizedDescription
        }
    }

    private func reloadReview() {
        guard let selectedRunID else {
            review = nil
            return
        }
        do {
            review = try service.loadRun(runID: selectedRunID, projectRoot: projectRoot)
            loadError = nil
        } catch {
            review = nil
            loadError = error.localizedDescription
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

    // MARK: - Presentation helpers

    private func statusBadge(_ status: XcircuiteRunStatus) -> some View {
        Text(status.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor(status).opacity(0.2), in: Capsule())
            .foregroundStyle(badgeColor(status))
    }

    private func badgeColor(_ status: XcircuiteRunStatus) -> Color {
        switch status {
        case .succeeded: return .green
        case .failed: return .red
        case .blocked: return .orange
        default: return .secondary
        }
    }

    private func gateIcon(_ status: FlowGateStatus) -> String {
        switch status {
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .waived: return "minus.circle"
        case .incomplete: return "clock.fill"
        }
    }

    private func gateColor(_ status: FlowGateStatus) -> Color {
        switch status {
        case .passed: return .green
        case .failed: return .red
        case .waived: return .secondary
        case .incomplete: return .orange
        }
    }
}
