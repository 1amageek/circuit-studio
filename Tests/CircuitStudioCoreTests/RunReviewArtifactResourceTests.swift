import DesignFlowKernel
import Foundation
import Testing
@testable import CircuitStudioApp

@Suite("Run review artifact resource")
struct RunReviewArtifactResourceTests {
    @Test func returnsAURLOnlyAfterRevalidatingTheRecordedDigest() async throws {
        let fixture = try RunReviewArtifactResourceFixture(contents: "time,v(out)\n0,0\n1,1\n")
        defer { fixture.remove() }

        let resource = try await RunReviewArtifactResourceLoader(service: fixture.service).load(
            runID: fixture.runID,
            artifact: fixture.artifact,
            projectRoot: fixture.root
        )

        #expect(resource.artifact == fixture.artifact)
        #expect(resource.url.standardizedFileURL == fixture.file.standardizedFileURL)
        #expect(resource.digest == fixture.digest)
    }

    @Test func rejectsContentChangedAfterLedgerVerification() async throws {
        let fixture = try RunReviewArtifactResourceFixture(contents: "original")
        defer { fixture.remove() }
        try Data("modified".utf8).write(to: fixture.file)

        do {
            _ = try await fixture.service.verifiedArtifactResource(
                runID: fixture.runID,
                artifact: fixture.artifact,
                projectRoot: fixture.root
            )
            Issue.record("A modified artifact was exposed to the renderer.")
        } catch let error as RunReviewServiceError {
            guard case .artifactResourceIntegrityUnverified(_, let status, _) = error else {
                Issue.record("Unexpected run review error: \(error)")
                return
            }
            #expect(status == "sha256Mismatch")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func rejectsAnArtifactOutsideTheProjectRoot() async throws {
        let fixture = try RunReviewArtifactResourceFixture(contents: "inside")
        defer { fixture.remove() }
        let outsideDirectory = FileManager.default.temporaryDirectory
            .appending(path: "RunReviewOutside-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: outsideDirectory)
            } catch {
                Issue.record("Failed to remove outside artifact fixture: \(error)")
            }
        }
        let outsideFile = outsideDirectory.appending(path: "outside.csv", directoryHint: .notDirectory)
        let outsideData = Data("outside".utf8)
        try outsideData.write(to: outsideFile)
        let outsideDigest = RoundTripArtifactDigest.compute(data: outsideData)
        let outsideArtifact = fixture.artifact(
            path: outsideFile.path(percentEncoded: false),
            digest: outsideDigest
        )
        let service = fixture.service(artifact: outsideArtifact)

        do {
            _ = try await service.verifiedArtifactResource(
                runID: fixture.runID,
                artifact: outsideArtifact,
                projectRoot: fixture.root
            )
            Issue.record("An artifact outside the project root was exposed to the renderer.")
        } catch let error as RunReviewServiceError {
            #expect(error == .artifactResourceEscapesProject(path: outsideArtifact.path))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

private struct RunReviewArtifactResourceFixture {
    let root: URL
    let file: URL
    let runID = "renderer-run"
    let digest: RoundTripArtifactDigest
    let artifact: FlowRunReviewArtifact

    init(contents: String) throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "RunReviewArtifactResourceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let artifactDirectory = root.appending(path: "artifacts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        let file = artifactDirectory.appending(path: "waveform.csv", directoryHint: .notDirectory)
        let data = Data(contents.utf8)
        try data.write(to: file)
        let digest = RoundTripArtifactDigest.compute(data: data)

        self.root = root
        self.file = file
        self.digest = digest
        self.artifact = Self.makeArtifact(path: "artifacts/waveform.csv", digest: digest)
    }

    var service: RunReviewService {
        service(artifact: artifact)
    }

    func service(artifact: FlowRunReviewArtifact) -> RunReviewService {
        let summary = FlowRunLedgerSummary(
            runID: runID,
            status: .succeeded
        )
        let bundle = FlowRunReviewBundle(
            runID: runID,
            status: .succeeded,
            summary: summary,
            artifacts: [artifact]
        )
        return RunReviewService(reviewBundler: RunReviewArtifactBundleStub(bundle: bundle))
    }

    func artifact(path: String, digest: RoundTripArtifactDigest) -> FlowRunReviewArtifact {
        Self.makeArtifact(path: path, digest: digest)
    }

    func remove() {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove run review artifact fixture: \(error)")
        }
    }

    private static func makeArtifact(
        path: String,
        digest: RoundTripArtifactDigest
    ) -> FlowRunReviewArtifact {
        let byteCount = UInt64(digest.byteCount)
        return FlowRunReviewArtifact(
            role: "waveform",
            artifactID: "waveform",
            stageID: "simulation",
            path: path,
            kind: .waveform,
            format: .csv,
            sha256: digest.sha256,
            byteCount: byteCount,
            integrity: FlowRunReviewArtifactIntegrity(
                status: .verified,
                expectedSHA256: digest.sha256,
                actualSHA256: digest.sha256,
                expectedByteCount: byteCount,
                actualByteCount: byteCount,
                message: "Artifact integrity is verified."
            )
        )
    }
}

private struct RunReviewArtifactBundleStub: FlowRunReviewBundling {
    let bundle: FlowRunReviewBundle

    func makeReviewBundle(runID: String, projectRoot: URL) async throws -> FlowRunReviewBundle {
        bundle
    }
}
