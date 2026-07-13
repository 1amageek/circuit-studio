import AppKit
import Activity
import ArtifactView
import CircuitArtifactRenderer
import CircuiteFoundation
import DesignFlowKernel
import Foundation
import SwiftUI
import DesignFlowKernel

struct ActivityArtifactPreview: View {
    let projectRoot: URL
    let activity: Activity
    let reference: Activity.ArtifactReference
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
        .navigationTitle(reference.displayName)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(reference.path, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy artifact path")
            }
        }
        .task(id: "\(activity.id):\(reference.path):\(reference.sha256 ?? "")") {
            await load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(reference.displayName)
                    .font(.title3)
                    .bold()
                Spacer()
                Text(reference.direction.title)
                    .font(.caption)
                    .foregroundStyle(reference.direction.statusColor)
                Text(reference.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(reference.format)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(reference.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                if let byteCount = reference.byteCount {
                    Text(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                }
                if let sha256 = reference.sha256 {
                    Text("SHA-256 \(sha256)")
                        .textSelection(.enabled)
                }
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
            if let kind = FoundationArtifactTypeProjection.kind(resource.artifact.kind),
               let format = FoundationArtifactTypeProjection.format(resource.artifact.format) {
                ArtifactCanvas(
                    url: resource.url,
                    type: typeResolver.artifactType(kind: kind, format: format),
                    title: artifactTitle(resource.artifact)
                )
                .artifactContentMaxHeight(nil)
                .id(resource.digest)
            } else {
                ContentUnavailableView(
                    "Artifact format is not supported",
                    systemImage: "doc.questionmark"
                )
            }
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
            let bundle = try RunReviewService().loadReviewBundle(
                runID: runID,
                projectRoot: projectRoot
            )
            guard let artifact = bundle.artifacts.first(where: matches) else {
                throw ActivityArtifactPreviewError.notFound(path: reference.path)
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
        guard artifact.path == reference.path,
              artifact.role == reference.role,
              artifact.kind.rawValue == reference.kind,
              artifact.format.rawValue == reference.format else {
            return false
        }
        if let expectedSHA256 = reference.sha256 {
            return artifact.sha256 == expectedSHA256
        }
        return true
    }

    private func artifactTitle(_ artifact: FlowRunReviewArtifact) -> String {
        if let artifactID = artifact.artifactID, !artifactID.isEmpty {
            return artifactID
        }
        return URL(filePath: artifact.path).lastPathComponent
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

private extension Activity.ArtifactReference {
    var displayName: String {
        let name = URL(filePath: path).lastPathComponent
        return name.isEmpty ? path : name
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
