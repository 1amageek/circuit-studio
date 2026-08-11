import DesignFlowKernel
import CircuiteFoundation
import Foundation
import Xcircuite

extension RunReviewService {
    public func verifiedArtifactResource(
        runID: String,
        artifact: FlowRunReviewArtifact,
        projectRoot: URL
    ) async throws -> RunReviewArtifactResource {
        let store = try workspaceStore(projectRoot: projectRoot)
        let loader = configuredReviewLedgerLoader(store: store)
        let bundle = try await configuredReviewBundler(store: store, loader: loader)
            .makeReviewBundle(
                runID: runID,
                workspaceID: try await workspaceID(store: store)
            )
        guard let recordedArtifact = bundle.artifacts.first(where: { isSameArtifact($0, as: artifact) }) else {
            throw RunReviewServiceError.artifactResourceNotFound(
                runID: runID,
                artifactPath: artifact.binding.circuitStudioPresentationPath
            )
        }

        return try await makeVerifiedArtifactResource(
            runID: runID,
            artifact: recordedArtifact,
            projectRoot: projectRoot,
            artifactReader: store
        )
    }

    private func makeVerifiedArtifactResource(
        runID: String,
        artifact: FlowRunReviewArtifact,
        projectRoot: URL,
        artifactReader: any XcircuiteArtifactBindingReading
    ) async throws -> RunReviewArtifactResource {
        let presentationPath = artifact.binding.circuitStudioPresentationPath
        guard let integrity = artifact.integrity, integrity.status == .verified else {
            throw RunReviewServiceError.artifactResourceIntegrityUnverified(
                path: presentationPath,
                status: artifact.integrity?.status.rawValue ?? "missing",
                message: artifact.integrity?.message ?? "No recorded artifact integrity state is available."
            )
        }
        let url: URL
        do {
            url = try verifiedArtifactURL(for: artifact, projectRoot: projectRoot)
        } catch RunReviewServiceError.artifactPreviewEscapesProject(_) {
            throw RunReviewServiceError.artifactResourceEscapesProject(path: presentationPath)
        }

        let resolvedPath = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw RunReviewServiceError.artifactResourceInputMissing(path: presentationPath)
        }

        let resourceValues: URLResourceValues
        do {
            resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            throw RunReviewServiceError.artifactResourceUnreadable(
                path: presentationPath,
                message: error.localizedDescription
            )
        }
        guard resourceValues.isRegularFile == true else {
            throw RunReviewServiceError.artifactResourceInputMissing(path: presentationPath)
        }
        guard resourceValues.fileSize.map({ $0 >= 0 }) == true else {
            throw RunReviewServiceError.artifactResourceUnreadable(
                path: presentationPath,
                message: "Artifact byte count is unavailable."
            )
        }
        do {
            _ = try await artifactReader.loadArtifactContent(for: artifact.binding)
        } catch XcircuiteWorkspaceStoreError.artifactIntegrityFailed(_, let issues) {
            throw RunReviewServiceError.artifactResourceIntegrityUnverified(
                path: presentationPath,
                status: issues.first?.code.rawValue ?? "integrity-failure",
                message: issues.map(\.code.rawValue).joined(separator: ", ")
            )
        } catch {
            throw RunReviewServiceError.artifactResourceIntegrityUnverified(
                path: presentationPath,
                status: "integrity-failure",
                message: error.localizedDescription
            )
        }

        return RunReviewArtifactResource(
            runID: runID,
            artifact: artifact,
            url: url,
            reference: artifact.reference
        )
    }
}
