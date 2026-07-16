import DesignFlowKernel
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
                artifactPath: artifact.path
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
                path: artifact.path,
                status: artifact.integrity?.status.rawValue ?? "missing",
                message: artifact.integrity?.message ?? "No recorded artifact integrity state is available."
            )
        }
        guard let expectedByteCount = artifact.byteCount else {
            throw RunReviewServiceError.artifactResourceIntegrityUnverified(
                path: artifact.path,
                status: FlowRunReviewArtifactIntegrityStatus.missingByteCount.rawValue,
                message: "A non-negative recorded byte count is required."
            )
        }
        guard let expectedSHA256 = artifact.sha256,
              RoundTripArtifactDigest.isValidSHA256(expectedSHA256) else {
            throw RunReviewServiceError.artifactResourceIntegrityUnverified(
                path: artifact.path,
                status: FlowRunReviewArtifactIntegrityStatus.invalidDigest.rawValue,
                message: "A valid recorded SHA-256 digest is required."
            )
        }

        let url: URL
        do {
            url = try verifiedArtifactURL(for: artifact, projectRoot: projectRoot)
        } catch RunReviewServiceError.artifactPreviewEscapesProject(_) {
            throw RunReviewServiceError.artifactResourceEscapesProject(path: artifact.path)
        }

        let resolvedPath = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw RunReviewServiceError.artifactResourceInputMissing(path: artifact.path)
        }

        let resourceValues: URLResourceValues
        do {
            resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            throw RunReviewServiceError.artifactResourceUnreadable(
                path: artifact.path,
                message: error.localizedDescription
            )
        }
        guard resourceValues.isRegularFile == true else {
            throw RunReviewServiceError.artifactResourceInputMissing(path: artifact.path)
        }
        guard let fileSize = resourceValues.fileSize, fileSize >= 0 else {
            throw RunReviewServiceError.artifactResourceUnreadable(
                path: artifact.path,
                message: "Artifact byte count is unavailable."
            )
        }
        let actualByteCount = UInt64(fileSize)

        let digest: RoundTripArtifactDigest
        do {
            digest = try RoundTripArtifactDigest.compute(url: url)
        } catch {
            throw RunReviewServiceError.artifactResourceUnreadable(
                path: artifact.path,
                message: error.localizedDescription
            )
        }

        guard actualByteCount == expectedByteCount else {
            throw RunReviewServiceError.artifactResourceIntegrityUnverified(
                path: artifact.path,
                status: FlowRunReviewArtifactIntegrityStatus.byteCountMismatch.rawValue,
                message: "Recorded byte count \(expectedByteCount) does not match \(actualByteCount)."
            )
        }
        guard digest.sha256 == expectedSHA256.lowercased() else {
            throw RunReviewServiceError.artifactResourceIntegrityUnverified(
                path: artifact.path,
                status: FlowRunReviewArtifactIntegrityStatus.sha256Mismatch.rawValue,
                message: "Recorded SHA-256 does not match the current artifact."
            )
        }

        return RunReviewArtifactResource(
            runID: runID,
            artifact: artifact,
            url: url,
            digest: digest
        )
    }
}
