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
                    NSPasteboard.general.setString(artifact.reference.path, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy artifact path")
            }
        }
        .task(
            id: "\(activity.id):\(artifact.reference.path):\(artifact.reference.digest.hexadecimalValue)"
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
                Text(artifact.reference.kind.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(artifact.reference.format.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(artifact.reference.path)
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
                    kind: resource.artifact.reference.locator.kind,
                    format: resource.artifact.reference.locator.format
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
                throw ActivityArtifactPreviewError.notFound(path: artifact.reference.path)
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
        artifact.reference.locator.location.value == self.artifact.reference.path
            && artifact.purpose.rawValue == self.artifact.reference.locator.role.rawValue
            && artifact.reference.locator.kind.rawValue == self.artifact.reference.kind.rawValue
            && artifact.reference.locator.format.rawValue == self.artifact.reference.format.rawValue
            && artifact.reference.digest == self.artifact.reference.digest
    }

    private func artifactTitle(_ artifact: FlowRunReviewArtifact) -> String {
        let artifactID = artifact.reference.id.rawValue
        if !artifactID.isEmpty {
            return artifactID
        }
        return URL(filePath: artifact.reference.locator.location.value).lastPathComponent
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
        let name = URL(filePath: reference.path).lastPathComponent
        return name.isEmpty ? reference.path : name
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
