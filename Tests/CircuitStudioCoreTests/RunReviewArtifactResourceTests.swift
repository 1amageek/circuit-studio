import DesignFlowKernel
import CircuiteFoundation
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
            #expect(status == "digestMismatch")
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
        let outsideDigest = try SHA256ContentDigester().digest(data: outsideData, using: .sha256)
        let outsideArtifact = try fixture.artifact(
            path: outsideFile.path(percentEncoded: false),
            digest: outsideDigest,
            byteCount: UInt64(outsideData.count)
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
            #expect(error == .artifactResourceEscapesProject(path: outsideArtifact.reference.path))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

private struct RunReviewArtifactResourceFixture {
    let root: URL
    let file: URL
    let runID = "renderer-run"
    let digest: ContentDigest
    let artifact: FlowRunReviewArtifact

    init(contents: String) throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "RunReviewArtifactResourceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let artifactDirectory = root.appending(path: "artifacts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        let file = artifactDirectory.appending(path: "waveform.csv", directoryHint: .notDirectory)
        let data = Data(contents.utf8)
        try data.write(to: file)
        let digest = try SHA256ContentDigester().digest(data: data, using: .sha256)

        self.root = root
        self.file = file
        self.digest = digest
        self.artifact = try Self.makeArtifact(
            path: "artifacts/waveform.csv",
            digest: digest,
            byteCount: UInt64(data.count)
        )
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

    func artifact(path: String, digest: ContentDigest, byteCount: UInt64) throws -> FlowRunReviewArtifact {
        try Self.makeArtifact(path: path, digest: digest, byteCount: byteCount)
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
        digest: ContentDigest,
        byteCount: UInt64
    ) throws -> FlowRunReviewArtifact {
        let reference = ArtifactReference(
            id: try ArtifactID(rawValue: "waveform"),
            locator: ArtifactLocator(
                location: path.hasPrefix("/")
                    ? try ArtifactLocation(fileURL: URL(filePath: path))
                    : try ArtifactLocation(workspaceRelativePath: path),
                role: try ArtifactRole(validatingRawValue: "waveform"),
                kind: .waveform,
                format: .csv
            ),
            digest: digest,
            byteCount: byteCount
        )
        return FlowRunReviewArtifact(
            reference: reference,
            purpose: try FlowRunReviewArtifactPurpose(validatingRawValue: "waveform"),
            stageID: "simulation",
            integrity: FlowRunReviewArtifactIntegrity(
                status: .verified,
                expectedSHA256: digest.hexadecimalValue,
                actualSHA256: digest.hexadecimalValue,
                expectedByteCount: byteCount,
                actualByteCount: byteCount,
                message: "Artifact integrity is verified."
            )
        )
    }
}

private struct RunReviewArtifactBundleStub: FlowRunReviewBundling {
    let bundle: FlowRunReviewBundle

    func makeReviewBundle(runID: String, workspaceID: FlowWorkspaceID) async throws -> FlowRunReviewBundle {
        bundle
    }
}
