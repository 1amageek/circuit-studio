import ArtifactView
import CircuitArtifactRenderer
import CircuiteFoundation
import DesignFlowKernel
import SwiftUI

struct RunReviewArtifactBrowser: View {
    let runID: String
    let artifacts: [FlowRunReviewArtifact]
    @Binding var selectedArtifact: FlowRunReviewArtifact?
    let resource: RunReviewArtifactResource?
    let isLoading: Bool
    let errorMessage: String?

    private let typeResolver: any CircuitArtifactTypeResolving = XcircuiteArtifactTypeResolver()

    var body: some View {
        HSplitView {
            artifactList
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
            preview
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 520)
        .onAppear(perform: selectDefaultArtifact)
        .onChange(of: artifacts) { _, _ in
            selectDefaultArtifact()
        }
    }

    private var artifactList: some View {
        List(selection: $selectedArtifact) {
            ForEach(artifacts, id: \.self) { artifact in
                artifactRow(artifact)
                    .tag(artifact)
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Run artifacts")
    }

    @ViewBuilder
    private var preview: some View {
        if let selectedArtifact {
            VStack(alignment: .leading, spacing: 10) {
                artifactHeader(selectedArtifact)
                Divider()
                previewContent(for: selectedArtifact)
            }
            .padding(.leading, 12)
        } else {
            ContentUnavailableView(
                "Select an artifact",
                systemImage: "doc.text.magnifyingglass"
            )
        }
    }

    @ViewBuilder
    private func previewContent(for artifact: FlowRunReviewArtifact) -> some View {
        if isLoading {
            ProgressView("Verifying artifact")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Artifact cannot be opened", systemImage: "exclamationmark.shield")
            } description: {
                Text(errorMessage)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let resource,
                  resource.runID == runID,
                  resource.artifact == artifact {
            ArtifactCanvas(
                url: resource.url,
                type: typeResolver.artifactType(kind: artifact.binding.kind, format: artifact.binding.format),
                title: artifactTitle(artifact)
            )
            .artifactContentMaxHeight(nil)
            .id(resource.digest)
        } else {
            ContentUnavailableView(
                "Artifact is not verified",
                systemImage: "shield.slash"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func artifactRow(_ artifact: FlowRunReviewArtifact) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: integrityIcon(artifact.integrity?.status))
                .foregroundStyle(integrityColor(artifact.integrity?.status))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(artifactTitle(artifact))
                    .font(.callout)
                    .lineLimit(1)
                Text(artifact.binding.circuitStudioPresentationPath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(artifact.purpose.rawValue)
                    Text(artifact.binding.format.rawValue)
                    Text(formattedByteCount(artifact.reference.byteCount))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func artifactHeader(_ artifact: FlowRunReviewArtifact) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(artifactTitle(artifact))
                    .font(.headline)
                Text(artifact.binding.circuitStudioPresentationPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Text(artifact.binding.kind.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(artifact.binding.format.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func selectDefaultArtifact() {
        if let selectedArtifact,
           artifacts.contains(selectedArtifact) {
            return
        }
        selectedArtifact = artifacts.first { $0.integrity?.status == .verified } ?? artifacts.first
    }

    private func artifactTitle(_ artifact: FlowRunReviewArtifact) -> String {
        let artifactID = artifact.binding.logicalID
        if !artifactID.isEmpty {
            return artifactID
        }
        return URL(filePath: artifact.binding.circuitStudioPresentationPath).lastPathComponent
    }

    private func formattedByteCount(_ byteCount: UInt64) -> String {
        guard byteCount <= UInt64(Int64.max) else {
            return "\(byteCount) bytes"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    private func integrityIcon(_ status: FlowRunReviewArtifactIntegrityStatus?) -> String {
        switch status {
        case .verified:
            return "checkmark.seal.fill"
        case .missingDigest, .missingByteCount:
            return "exclamationmark.triangle.fill"
        case .missingArtifact, .invalidDigest, .invalidByteCount, .byteCountMismatch, .sha256Mismatch,
             .invalidIdentifier, .noRecordedReference, .invalidPath, .unreadableArtifact:
            return "xmark.seal.fill"
        case nil:
            return "questionmark.diamond"
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
