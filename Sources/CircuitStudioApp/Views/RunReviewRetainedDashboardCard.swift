import DesignFlowKernel
import SwiftUI

struct RunReviewRetainedDashboardCard: View {
    let projection: RunReviewRetainedDashboardProjection

    var body: some View {
        GroupBox("Retained Dashboard") {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 112), spacing: 8)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    metric("Status", projection.status.rawValue)
                    metric("Artifacts", "\(projection.artifactStates.count)")
                    metric("Verified", "\(projection.verifiedArtifactCount)")
                    metric("Stale", "\(projection.staleEvidenceCount)")
                    metric("Blockers", "\(projection.blockerSummaries.count)")
                    metric("Decisions", "\(projection.decisionSummaries.count)")
                }
                diagnosticSection
                artifactSection
                blockerSection
                decisionSection
                resumeActionSection
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var diagnosticSection: some View {
        if !projection.diagnosticCodes.isEmpty {
            DisclosureGroup {
                wrappedLabels(projection.diagnosticCodes)
                    .padding(.top, 3)
            } label: {
                sectionLabel("Diagnostics", count: projection.diagnosticCodes.count)
            }
        }
    }

    @ViewBuilder
    private var artifactSection: some View {
        if !projection.artifactStates.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(projection.artifactStates) { artifact in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: artifactIcon(artifact.evidenceStatus))
                                    .foregroundStyle(artifactColor(artifact.evidenceStatus))
                                Text(artifact.role)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(artifact.evidenceStatus)
                                    .font(.caption2)
                                Spacer()
                            }
                            Text(artifact.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if !artifact.diagnosticCodes.isEmpty {
                                wrappedLabels(artifact.diagnosticCodes)
                            }
                        }
                    }
                }
                .padding(.top, 3)
            } label: {
                sectionLabel("Artifacts", count: projection.artifactStates.count)
            }
        }
    }

    @ViewBuilder
    private var blockerSection: some View {
        if !projection.blockerSummaries.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(projection.blockerSummaries) { blocker in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: severityIcon(blocker.severity))
                                    .foregroundStyle(severityColor(blocker.severity))
                                Text(blocker.status.rawValue)
                                    .font(.caption2.monospaced())
                                if let nextActionID = blocker.nextActionID {
                                    Text(nextActionID)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            Text(blocker.title)
                                .font(.caption)
                            Text(blocker.reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            wrappedLabels(blocker.diagnosticCodes)
                        }
                    }
                }
                .padding(.top, 3)
            } label: {
                sectionLabel("Blockers", count: projection.blockerSummaries.count)
            }
        }
    }

    @ViewBuilder
    private var decisionSection: some View {
        if !projection.decisionSummaries.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(projection.decisionSummaries) { decision in
                        HStack(spacing: 6) {
                            Text(decision.kind.rawValue)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Text(decision.decision)
                                .font(.caption2)
                            Text(decision.targetID)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
                .padding(.top, 3)
            } label: {
                sectionLabel("Decisions", count: projection.decisionSummaries.count)
            }
        }
    }

    @ViewBuilder
    private var resumeActionSection: some View {
        if !projection.resumeActions.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(projection.resumeActions) { action in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: severityIcon(action.severity))
                                    .foregroundStyle(severityColor(action.severity))
                                Text(action.id)
                                    .font(.caption2.monospaced())
                                Spacer()
                            }
                            Text(action.reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if !action.readyCommandIDs.isEmpty {
                                wrappedLabels(action.readyCommandIDs)
                            }
                        }
                    }
                }
                .padding(.top, 3)
            } label: {
                sectionLabel("Resume Actions", count: projection.resumeActions.count)
            }
        }
    }

    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.stack.badge.person.crop")
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
            Text("\(count)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private func wrappedLabels(_ values: [String]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120), spacing: 5)],
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    private func severityIcon(_ severity: FlowDiagnosticSeverity) -> String {
        switch severity {
        case .error:
            "xmark.octagon.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .info:
            "info.circle.fill"
        }
    }

    private func severityColor(_ severity: FlowDiagnosticSeverity) -> Color {
        switch severity {
        case .error:
            .red
        case .warning:
            .orange
        case .info:
            .secondary
        }
    }

    private func artifactIcon(_ status: String) -> String {
        switch status {
        case "verified":
            "checkmark.seal.fill"
        case "stale":
            "clock.badge.exclamationmark.fill"
        case "missing", "broken":
            "xmark.octagon.fill"
        default:
            "doc.text"
        }
    }

    private func artifactColor(_ status: String) -> Color {
        switch status {
        case "verified":
            .green
        case "stale":
            .orange
        case "missing", "broken":
            .red
        default:
            .secondary
        }
    }
}
