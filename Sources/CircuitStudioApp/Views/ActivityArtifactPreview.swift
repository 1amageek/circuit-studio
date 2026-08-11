import AppKit
import Activity
import ArtifactView
import CircuitArtifactRenderer
import CircuiteFoundation
import DesignFlowKernel
import Foundation
import SwiftUI

struct ActivityArtifactPreview: View {
    let projectRoot: URL
    let activity: Activity
    let artifact: Activity.Artifact
    let artifactResourceLoader: any RunReviewArtifactResourceLoading

    @State private var resource: RunReviewArtifactResource?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let typeResolver: any CircuitArtifactTypeResolving = XcircuiteArtifactTypeResolver()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
        }
        .padding()
        .navigationTitle(artifact.displayName)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(artifact.reference.id.description, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy artifact path")
            }
        }
        .task(
            id: "\(activity.id):\(artifact.reference.id.description)"
        ) {
            await load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(artifact.displayName)
                    .font(.title3)
                    .bold()
                Spacer()
                Text(artifact.direction.title)
                    .font(.caption)
                    .foregroundStyle(artifact.direction.statusColor)
                Text(artifact.reference.descriptor.kind.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(artifact.reference.descriptor.format.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(artifact.reference.id.description)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Text(ByteCountFormatter.string(
                    fromByteCount: Int64(clamping: artifact.reference.byteCount),
                    countStyle: .file
                ))
                Text("SHA-256 \(artifact.reference.digest.hexadecimalValue)")
                    .textSelection(.enabled)
                if let runID = activity.runID {
                    Text("Run \(runID)")
                        .textSelection(.enabled)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var content: some View {
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
        } else if let resource {
            ArtifactCanvas(
                url: resource.url,
                type: typeResolver.artifactType(
                    kind: resource.artifact.binding.kind,
                    format: resource.artifact.binding.format
                ),
                title: artifactTitle(resource.artifact)
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

    private func load() async {
        guard !Task.isCancelled else { return }
        guard let runID = activity.runID else {
            errorMessage = "This activity is not linked to a canonical Run."
            return
        }

        isLoading = true
        resource = nil
        errorMessage = nil
        defer { isLoading = false }

        do {
            let bundle = try await RunReviewService().loadReviewBundle(
                runID: runID,
                projectRoot: projectRoot
            )
            guard let artifact = bundle.artifacts.first(where: matches) else {
                throw ActivityArtifactPreviewError.notFound(path: artifact.reference.id.description)
            }
            let loadedResource = try await artifactResourceLoader.load(
                runID: runID,
                artifact: artifact,
                projectRoot: projectRoot
            )
            guard !Task.isCancelled else { return }
            resource = loadedResource
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func matches(_ artifact: FlowRunReviewArtifact) -> Bool {
        artifact.reference == self.artifact.reference
    }

    private func artifactTitle(_ artifact: FlowRunReviewArtifact) -> String {
        let artifactID = artifact.binding.logicalID
        if !artifactID.isEmpty {
            return artifactID
        }
        return URL(filePath: artifact.binding.circuitStudioPresentationPath).lastPathComponent
    }
}

private enum ActivityArtifactPreviewError: LocalizedError {
    case notFound(path: String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path):
            return "No canonical Run artifact matches '\(path)'."
        }
    }
}

private extension Activity.Artifact {
    var displayName: String {
        "\(reference.descriptor.kind.rawValue)-\(reference.digest.hexadecimalValue.prefix(12))"
    }
}

private extension Activity.ArtifactDirection {
    var title: String {
        rawValue.capitalized
    }

    var statusColor: Color {
        switch self {
        case .input: return .blue
        case .output: return .green
        case .related: return .secondary
        }
    }
}
