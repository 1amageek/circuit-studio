import DesignFlowKernel
import CircuiteFoundation
import Foundation

extension RunReviewService {
    public func verifiedArtifactResource(
        runID: String,
        artifact: FlowRunReviewArtifact,
        projectRoot: URL
    ) async throws -> RunReviewArtifactResource {
        let store = try workspaceStore(projectRoot: projectRoot)
        let loader = configuredLedgerLoader(store: store)
        let bundle = try await configuredReviewBundler(store: store, loader: loader)
            .makeReviewBundle(runID: runID, projectRoot: projectRoot)
        guard let recordedArtifact = bundle.artifacts.first(where: { isSameArtifact($0, as: artifact) }) else {
            throw RunReviewServiceError.artifactResourceNotFound(
                runID: runID,
                artifactPath: artifact.reference.path
            )
        }

        return try makeVerifiedArtifactResource(
            runID: runID,
            artifact: recordedArtifact,
            projectRoot: projectRoot
        )
    }

    private func makeVerifiedArtifactResource(
        runID: String,
        artifact: FlowRunReviewArtifact,
        projectRoot: URL
    ) throws -> RunReviewArtifactResource {
        guard let integrity = artifact.integrity, integrity.status == .verified else {
            throw RunReviewServiceError.artifactResourceIntegrityUnverified(
                path: artifact.reference.path,
                status: artifact.integrity?.status.rawValue ?? "missing",
                message: artifact.integrity?.message ?? "No recorded artifact integrity state is available."
            )
        }
        let url: URL
        do {
            url = try verifiedArtifactURL(for: artifact, projectRoot: projectRoot)
        } catch RunReviewServiceError.artifactPreviewEscapesProject(_) {
            throw RunReviewServiceError.artifactResourceEscapesProject(path: artifact.reference.path)
        }

        let resolvedPath = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw RunReviewServiceError.artifactResourceInputMissing(path: artifact.reference.path)
        }

        let resourceValues: URLResourceValues
        do {
            resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            throw RunReviewServiceError.artifactResourceUnreadable(
                path: artifact.reference.path,
                message: error.localizedDescription
            )
        }
        guard resourceValues.isRegularFile == true else {
            throw RunReviewServiceError.artifactResourceInputMissing(path: artifact.reference.path)
        }
        guard resourceValues.fileSize.map({ $0 >= 0 }) == true else {
            throw RunReviewServiceError.artifactResourceUnreadable(
                path: artifact.reference.path,
                message: "Artifact byte count is unavailable."
            )
        }
        let verification = LocalArtifactVerifier().verify(artifact.reference, relativeTo: projectRoot)
        guard verification.isVerified else {
            throw RunReviewServiceError.artifactResourceIntegrityUnverified(
                path: artifact.reference.path,
                status: verification.issues.first?.code.rawValue ?? "integrity-failure",
                message: verification.issues.map(\.code.rawValue).joined(separator: ", ")
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
