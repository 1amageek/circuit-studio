import DesignFlowKernel
import SwiftUI

struct RunReviewInteractiveSignoffDrilldownCard: View {
    let drilldown: RunReviewInteractiveSignoffDrilldown

    var body: some View {
        GroupBox("Review Drilldown Index") {
            VStack(alignment: .leading, spacing: 8) {
                summaryGrid
                sectionList
                failureList
            }
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(drilldown.sections, id: \.domain) { section in
                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(section.items.count)")
                        .font(.caption.monospaced())
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Artifacts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(drilldown.artifactIndex.count)")
                    .font(.caption.monospaced())
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Failures")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(drilldown.failures.count)")
                    .font(.caption.monospaced())
            }
        }
    }

    private var sectionList: some View {
        ForEach(drilldown.sections, id: \.domain) { section in
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(section.items, id: \.itemID) { item in
                        drilldownItem(item)
                    }
                }
                .padding(.top, 3)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: interactiveSignoffDrilldownIcon(section.domain))
                        .foregroundStyle(.secondary)
                    Text(section.title)
                        .font(.caption.weight(.semibold))
                    Text("\(section.items.count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var failureList: some View {
        if !drilldown.failures.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(drilldown.failures, id: \.failureID) { failure in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: planningStatusIcon(failure.severity))
                                    .foregroundStyle(planningStatusColor(failure.severity))
                                Text(failure.failureID)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Text(failure.message)
                                .font(.caption)
                                .lineLimit(2)
                            if !failure.suggestedActions.isEmpty {
                                Text(failure.suggestedActions.joined(separator: ", "))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.top, 3)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Drilldown Failures")
                        .font(.caption.weight(.semibold))
                    Text("\(drilldown.failures.count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func drilldownItem(
        _ item: RunReviewInteractiveSignoffDrilldown.Item
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                planningStatusBadge(item.status)
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(item.itemID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !item.metrics.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104), spacing: 6)],
                    alignment: .leading,
                    spacing: 3
                ) {
                    ForEach(item.metrics, id: \.label) { metric in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(metric.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(metric.value)
                                .font(.caption2.monospaced())
                                .lineLimit(1)
                        }
                    }
                }
            }
            if !item.interactions.isEmpty {
                Text(item.interactions.map(\.rawValue).joined(separator: ", "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            artifactReferences(item.artifactReferences)
            if !item.issues.isEmpty {
                Text("\(item.issues.count) issue(s)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func artifactReferences(
        _ refs: [RunReviewInteractiveSignoffDrilldown.ArtifactSummary]
    ) -> some View {
        if !refs.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(refs.prefix(4), id: \.path) { ref in
                    HStack(spacing: 6) {
                        Image(systemName: ref.integrityStatus == "verified" ? "checkmark.seal.fill" : "doc.text")
                            .foregroundStyle(integrityColor(
                                ref.integrityStatus.flatMap(FlowRunReviewArtifactIntegrityStatus.init(rawValue:))
                            ))
                        Text(ref.role)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Text(ref.path)
                            .font(.caption2.monospaced())
                            .lineLimit(1)
                    }
                }
                if refs.count > 4 {
                    Text("+\(refs.count - 4) more artifact ref(s)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func interactiveSignoffDrilldownIcon(
        _ domain: RunReviewInteractiveSignoffDrilldown.Domain
    ) -> String {
        switch domain {
        case .designDiff:
            return "rectangle.2.swap"
        case .drc:
            return "ruler"
        case .lvs:
            return "point.3.connected.trianglepath.dotted"
        case .pex:
            return "bolt.horizontal"
        case .oracle:
            return "checkmark.seal"
        case .simulation:
            return "waveform.path.ecg"
        case .postLayout:
            return "rectangle.connected.to.line.below"
        case .release:
            return "shippingbox"
        case .authorization:
            return "person.badge.shield.checkmark"
        case .tapeout:
            return "opticaldisc"
        case .waveform:
            return "waveform.path"
        }
    }

    private func planningStatusBadge(_ status: String) -> some View {
        Text(status)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(planningStatusColor(status).opacity(0.14), in: Capsule())
            .foregroundStyle(planningStatusColor(status))
    }

    private func planningStatusIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "passed", "accepted", "approved", "satisfied", "succeeded", "ready", "info", "added":
            return "checkmark.circle.fill"
        case "failed", "rejected", "blocked", "error", "missing", "unsupported", "not-accepted", "removed":
            return "xmark.circle.fill"
        case "pending", "needs-review", "approval-required", "incomplete", "warning", "modified", "truncated":
            return "clock.fill"
        default:
            return "circle"
        }
    }

    private func planningStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "passed", "accepted", "approved", "satisfied", "succeeded", "ready", "low", "info", "added":
            return .green
        case "failed", "rejected", "blocked", "error", "missing", "unsupported", "critical", "high",
             "not-accepted", "removed":
            return .red
        case "pending", "needs-review", "approval-required", "incomplete", "medium", "warning", "modified",
             "truncated":
            return .orange
        default:
            return .secondary
        }
    }

    private func integrityColor(_ status: FlowRunReviewArtifactIntegrityStatus?) -> Color {
        switch status {
        case .verified:
            return .green
        case .missingDigest, .missingByteCount:
            return .orange
        case .missingArtifact, .invalidDigest, .invalidByteCount, .byteCountMismatch, .sha256Mismatch,
             .invalidIdentifier, .noRecordedReference, .invalidPath, .unreadableArtifact:
            return .red
        case nil:
            return .secondary
        }
    }
}
