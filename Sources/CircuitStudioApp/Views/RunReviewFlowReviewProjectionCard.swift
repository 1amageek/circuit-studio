import DesignFlowKernel
import SwiftUI

struct RunReviewFlowReviewProjectionCard: View {
    let projection: RunReviewFlowReviewProjection

    var body: some View {
        GroupBox("Review Ledger") {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    metric("Coverage", "\(projection.coverageRefs.count)")
                    metric("Blocked", "\(projection.blockedItems.count)")
                    metric("Resume", "\(projection.resumeItems.count)")
                    metric("Integrity", "\(projection.integrityIssueArtifacts.count)")
                    metric("Decisions", "\(decisionCount)")
                }
                coverageSection
                artifactSection("Signoff Ladder", artifacts: projection.signoffLadderArtifacts)
                artifactSection("Planning Refs", artifacts: projection.planningArtifacts)
                artifactSection("Retained Refs", artifacts: projection.retainedHistoryArtifacts)
                artifactSection("Integrity Issues", artifacts: projection.integrityIssueArtifacts)
                itemSection("Blocked Items", items: projection.blockedItems)
                itemSection("Resume Items", items: projection.resumeItems)
                decisionSection("Approval Decisions", actions: projection.approvalActions)
                decisionSection("Waiver Decisions", actions: projection.waiverActions)
                decisionSection("Resume Decisions", actions: projection.resumeActions)
            }
        }
    }

    private var decisionCount: Int {
        projection.approvalActions.count
            + projection.waiverActions.count
            + projection.resumeActions.count
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
        }
    }

    @ViewBuilder
    private var coverageSection: some View {
        if !projection.coverageDomains.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(projection.coverageDomains, id: \.domain) { domain in
                        HStack(spacing: 6) {
                            Text(domain.domain)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Text("\(domain.refCount)")
                                .font(.caption2.monospaced())
                            Text(domain.roles.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if !domain.unverifiedArtifactPaths.isEmpty {
                                Text("\(domain.unverifiedArtifactPaths.count) unverified")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.red)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.top, 3)
            } label: {
                sectionLabel("Coverage Domains", count: projection.coverageDomains.count)
            }
        }
    }

    @ViewBuilder
    private func artifactSection(
        _ title: String,
        artifacts: [FlowRunReviewArtifact]
    ) -> some View {
        if !artifacts.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(artifacts, id: \.path) { artifact in
                        HStack(spacing: 6) {
                            Text(artifact.role)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Text(artifact.path)
                                .font(.caption2)
                                .lineLimit(1)
                            Text(artifact.integrity?.status.rawValue ?? "untracked")
                                .font(.caption2.monospaced())
                                .foregroundStyle(integrityColor(artifact.integrity?.status))
                            Spacer()
                        }
                    }
                }
                .padding(.top, 3)
            } label: {
                sectionLabel(title, count: artifacts.count)
            }
        }
    }

    @ViewBuilder
    private func itemSection(
        _ title: String,
        items: [FlowRunReviewItem]
    ) -> some View {
        if !items.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(items, id: \.itemID) { item in
                        HStack(spacing: 6) {
                            Image(systemName: icon(for: item.severity))
                                .foregroundStyle(color(for: item.severity))
                            Text(item.itemID)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Text(item.status.rawValue)
                                .font(.caption2)
                            if let nextActionID = item.nextActionID {
                                Text(nextActionID)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.top, 3)
            } label: {
                sectionLabel(title, count: items.count)
            }
        }
    }

    @ViewBuilder
    private func decisionSection(
        _ title: String,
        actions: [FlowRunReviewDecision]
    ) -> some View {
        if !actions.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(actions, id: \.actionRecordID) { action in
                        HStack(spacing: 6) {
                            Text(action.decisionKind.rawValue)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Text(action.decision)
                                .font(.caption2)
                            Text(action.targetID)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
                .padding(.top, 3)
            } label: {
                sectionLabel(title, count: actions.count)
            }
        }
    }

    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle")
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
            Text("\(count)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private func icon(for severity: FlowDiagnosticSeverity) -> String {
        switch severity {
        case .error:
            "xmark.octagon.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .info:
            "info.circle.fill"
        }
    }

    private func color(for severity: FlowDiagnosticSeverity) -> Color {
        switch severity {
        case .error:
            .red
        case .warning:
            .orange
        case .info:
            .secondary
        }
    }

    private func integrityColor(_ status: FlowRunReviewArtifactIntegrityStatus?) -> Color {
        switch status {
        case .verified:
            .green
        case .missingDigest, .missingByteCount:
            .orange
        case .missingArtifact, .invalidDigest, .invalidByteCount, .byteCountMismatch, .sha256Mismatch,
             .invalidIdentifier, .noRecordedReference, .invalidPath, .unreadableArtifact:
            .red
        case nil:
            .secondary
        }
    }
}
