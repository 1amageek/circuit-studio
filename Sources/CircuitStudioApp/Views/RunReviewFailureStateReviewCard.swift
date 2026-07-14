import DesignFlowKernel
import SwiftUI

struct RunReviewFailureStateReviewCard: View {
    let summary: RunReviewFailureStateSummary

    var body: some View {
        GroupBox("Failure States") {
            VStack(alignment: .leading, spacing: 10) {
                kindCountsGrid
                stateList
            }
        }
    }

    private var kindCountsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 108), spacing: 8)],
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(summary.kindCounts, id: \.kind) { count in
                VStack(alignment: .leading, spacing: 1) {
                    Text(count.kind.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(count.count)")
                        .font(.caption.monospaced())
                }
            }
        }
    }

    private var stateList: some View {
        ForEach(summary.states, id: \.stateID) { state in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: failureStateIcon(state.kind))
                        .foregroundStyle(failureStateColor(state.severity))
                    Text(state.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(state.severity.rawValue)
                        .font(.caption2)
                        .foregroundStyle(failureStateColor(state.severity))
                }
                Text(state.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                metadataRow(state)
                artifactReferences(state.artifactReferences)
                if !state.diagnosticCodes.isEmpty {
                    Text(state.diagnosticCodes.joined(separator: ", "))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !state.suggestedActions.isEmpty {
                    Text(state.suggestedActions.joined(separator: ", "))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func metadataRow(_ state: RunReviewFailureStateSummary.State) -> some View {
        HStack(spacing: 8) {
            Text(state.kind.rawValue)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            if let stageID = state.stageID {
                Text(stageID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let gateID = state.gateID {
                Text(gateID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let nextActionID = state.nextActionID {
                Text("Next: \(nextActionID)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func artifactReferences(_ refs: [RunReviewFailureStateSummary.ArtifactReference]) -> some View {
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
                    Text("+\(refs.count - 4) artifact ref(s)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func failureStateIcon(_ kind: RunReviewFailureStateSummary.Kind) -> String {
        switch kind {
        case .missingArtifact:
            return "doc.badge.questionmark"
        case .integrityMismatch:
            return "checkmark.shield"
        case .staleEvidence:
            return "clock.badge.exclamationmark"
        case .blockedGate:
            return "pause.circle"
        case .decodeFailure:
            return "curlybraces"
        case .unsupportedAction:
            return "nosign"
        }
    }

    private func failureStateColor(_ severity: RunReviewFailureStateSummary.Severity) -> Color {
        switch severity {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
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
