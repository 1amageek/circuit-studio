import Foundation
import Testing
import CircuiteFoundation
import DesignFlowKernel
import Xcircuite
@testable import CircuitStudioApp

/// P1 artifact-contract gate: evidence bundles land in the canonical
/// `.xcircuite` run ledger with copied, digest-verified artifacts —
/// one record for human review and the agent loop alike.
@Suite("Xcircuite evidence run recorder", .timeLimit(.minutes(2)))
struct XcircuiteEvidenceRunRecorderTests {

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("evidence-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeProject(_ root: URL) {
        do {
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
        } catch {
            Issue.record("Failed to remove temporary evidence project at \(root.path): \(error)")
        }
    }

    private func writeFixture(_ text: String, named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func bundleLandsInRunLedgerWithVerifiedCopies() async throws {
        let root = try makeProject()
        defer { removeProject(root) }
        let scratch = root.appendingPathComponent("scratch")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        let report = try writeFixture("drc clean", named: "drc.rpt", in: scratch)
        let digest = try SHA256ContentDigester().digest(fileAt: report, using: .sha256).hexadecimalValue
        let reportBytes = Int64(try Data(contentsOf: report).count)
        let gds = try writeFixture("fake-gds", named: "top.gds", in: scratch)

        let bundle = TapeoutEvidenceBundle(
            designName: "TOP",
            targetClockPeriod: 1e-9,
            claims: [
                .init(
                    axis: .drc,
                    statement: "layout is DRC clean",
                    passed: true,
                    measured: "0 violations",
                    artifact: try evidenceArtifact(
                        id: "drc-report",
                        kind: "report",
                        path: report.path,
                        status: .available,
                        sha256: digest,
                        byteCount: reportBytes
                    ),
                    kind: .signoff
                ),
                .init(
                    axis: .functional, statement: "golden trace matches", passed: true,
                    measured: "match", artifact: nil, kind: .signoff
                ),
                .init(
                    axis: .timing, statement: "setup/hold close", passed: true,
                    measured: "slack +120ps", artifact: nil, kind: .signoff
                ),
                .init(
                    axis: .lvs, statement: "layout matches schematic", passed: true,
                    measured: "match", artifact: nil, kind: .signoff
                ),
            ],
            gdsPath: gds.path
        )

        let recorded = try await XcircuiteEvidenceRunRecorder().record(
            bundle, projectRoot: root, runID: "run-evidence-1"
        )

        #expect(recorded.manifest.status == .succeeded)
        // evidence.json + drc report copy + gds copy
        #expect(recorded.manifest.artifacts.count == 3)
        #expect(Set(recorded.manifest.artifacts.compactMap(\.artifactID)) == [
            "tapeout-evidence",
            "drc-report",
            "gds",
        ])
        for reference in recorded.manifest.artifacts {
            let url = root.appendingPathComponent(reference.path)
            #expect(FileManager.default.fileExists(atPath: url.path), "\(reference.path)")
            #expect(reference.sha256 == (try SHA256ContentDigester().digest(fileAt: url, using: .sha256).hexadecimalValue))
            #expect(reference.path.hasPrefix(".xcircuite/runs/run-evidence-1/"))
        }
        let kinds = Set(recorded.manifest.artifacts.map(\.kind))
        #expect(kinds.contains(.report))
        #expect(kinds.contains(.layout))

        let manifest = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunManifest(runID: "run-evidence-1")
        #expect(manifest.status == .succeeded)
    }

    @Test func failingBundleIsRecordedAsFailed() async throws {
        let root = try makeProject()
        defer { removeProject(root) }

        let bundle = TapeoutEvidenceBundle(
            designName: "TOP",
            targetClockPeriod: 1e-9,
            claims: [
                .init(
                    axis: .drc, statement: "layout is DRC clean", passed: false,
                    measured: "3 violations", artifact: nil, kind: .signoff
                ),
            ],
            gdsPath: nil
        )

        let recorded = try await XcircuiteEvidenceRunRecorder().record(
            bundle, projectRoot: root, runID: "run-evidence-2"
        )
        #expect(recorded.manifest.status == .failed)
    }

    @Test func tamperedArtifactDigestIsAnIntegrityError() async throws {
        let root = try makeProject()
        defer { removeProject(root) }
        let scratch = root.appendingPathComponent("scratch")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let report = try writeFixture("tampered content", named: "drc.rpt", in: scratch)
        let reportBytes = Int64(try Data(contentsOf: report).count)

        let bundle = TapeoutEvidenceBundle(
            designName: "TOP",
            targetClockPeriod: 1e-9,
            claims: [
                .init(
                    axis: .drc, statement: "layout is DRC clean", passed: true,
                    measured: "0 violations",
                    artifact: try evidenceArtifact(
                        id: "drc-report",
                        kind: "report",
                        path: report.path,
                        status: .available,
                        sha256: String(repeating: "0", count: 64),
                        byteCount: reportBytes
                    ),
                    kind: .signoff
                ),
            ],
            gdsPath: nil
        )

        await #expect(throws: XcircuiteEvidenceRunRecorder.RecorderError.self) {
            try await XcircuiteEvidenceRunRecorder().record(
                bundle, projectRoot: root, runID: "run-evidence-3"
            )
        }
        let manifest = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunManifest(runID: "run-evidence-3")
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.contains { $0.path.hasSuffix("evidence.json") })
        #expect(manifest.artifacts.contains { $0.artifactID == "evidence-error" })
    }

    @Test func tamperedArtifactByteCountIsAnIntegrityError() async throws {
        let root = try makeProject()
        defer { removeProject(root) }
        let scratch = root.appendingPathComponent("scratch")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let report = try writeFixture("byte-count content", named: "drc.rpt", in: scratch)
        let digest = try SHA256ContentDigester().digest(fileAt: report, using: .sha256).hexadecimalValue
        let reportBytes = Int64(try Data(contentsOf: report).count)

        let bundle = TapeoutEvidenceBundle(
            designName: "TOP",
            targetClockPeriod: 1e-9,
            claims: [
                .init(
                    axis: .drc, statement: "layout is DRC clean", passed: true,
                    measured: "0 violations",
                    artifact: try evidenceArtifact(
                        id: "drc-report",
                        kind: "report",
                        path: report.path,
                        status: .available,
                        sha256: digest,
                        byteCount: reportBytes + 1
                    ),
                    kind: .signoff
                ),
            ],
            gdsPath: nil
        )

        await #expect(throws: XcircuiteEvidenceRunRecorder.RecorderError.artifactByteCountMismatch(
            id: "drc-report",
            claimed: reportBytes + 1,
            actual: reportBytes
        )) {
            try await XcircuiteEvidenceRunRecorder().record(
                bundle, projectRoot: root, runID: "run-evidence-4"
            )
        }
        let manifest = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunManifest(runID: "run-evidence-4")
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.contains { $0.artifactID == "evidence-error" })
    }

    @Test func unsafeArtifactIDIsRejectedBeforeCapture() async throws {
        let root = try makeProject()
        defer { removeProject(root) }
        let report = try writeFixture("drc clean", named: "unsafe-id.rpt", in: root)
        let digest = try SHA256ContentDigester().digest(fileAt: report, using: .sha256).hexadecimalValue
        let byteCount = Int64(try Data(contentsOf: report).count)
        let bundle = TapeoutEvidenceBundle(
            designName: "TOP",
            targetClockPeriod: 1e-9,
            claims: [
                .init(
                    axis: .drc,
                    statement: "layout is DRC clean",
                    passed: true,
                    measured: "0 violations",
                    artifact: try evidenceArtifact(
                        id: "../escape",
                        kind: "report",
                        path: report.path,
                        status: .available,
                        sha256: digest,
                        byteCount: byteCount
                    ),
                    kind: .signoff
                ),
            ],
            gdsPath: nil
        )

        await #expect(throws: FlowIdentifierValidationError.invalidIdentifier(
            kind: FlowIdentifierKind.artifactID.rawValue,
            value: "../escape"
        )) {
            try await XcircuiteEvidenceRunRecorder().record(
                bundle,
                projectRoot: root,
                runID: "run-evidence-unsafe-id"
            )
        }
        let manifest = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunManifest(runID: "run-evidence-unsafe-id")
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.contains { $0.artifactID == "evidence-error" })
    }

    @Test func duplicateArtifactIDsAreRejectedAsAmbiguousEvidence() async throws {
        let root = try makeProject()
        defer { removeProject(root) }
        let first = try writeFixture("drc clean", named: "first.rpt", in: root)
        let second = try writeFixture("lvs clean", named: "second.rpt", in: root)
        let firstDigest = try SHA256ContentDigester().digest(fileAt: first, using: .sha256).hexadecimalValue
        let secondDigest = try SHA256ContentDigester().digest(fileAt: second, using: .sha256).hexadecimalValue
        let firstByteCount = Int64(try Data(contentsOf: first).count)
        let secondByteCount = Int64(try Data(contentsOf: second).count)
        let bundle = TapeoutEvidenceBundle(
            designName: "TOP",
            targetClockPeriod: 1e-9,
            claims: [
                .init(
                    axis: .drc,
                    statement: "layout is DRC clean",
                    passed: true,
                    measured: "0 violations",
                    artifact: try evidenceArtifact(
                        id: "signoff-report",
                        kind: "report",
                        path: first.path,
                        status: .available,
                        sha256: firstDigest,
                        byteCount: firstByteCount
                    ),
                    kind: .signoff
                ),
                .init(
                    axis: .lvs,
                    statement: "layout matches schematic",
                    passed: true,
                    measured: "match",
                    artifact: try evidenceArtifact(
                        id: "signoff-report",
                        kind: "report",
                        path: second.path,
                        status: .available,
                        sha256: secondDigest,
                        byteCount: secondByteCount
                    ),
                    kind: .signoff
                ),
            ],
            gdsPath: nil
        )

        await #expect(throws: XcircuiteEvidenceRunRecorder.RecorderError.duplicateArtifactID(
            "signoff-report"
        )) {
            try await XcircuiteEvidenceRunRecorder().record(
                bundle,
                projectRoot: root,
                runID: "run-evidence-duplicate-id"
            )
        }
        let manifest = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunManifest(runID: "run-evidence-duplicate-id")
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.contains { $0.artifactID == "evidence-error" })
    }

    @Test func reservedFailureArtifactIDCannotBeClaimedByBundle() async throws {
        let root = try makeProject()
        defer { removeProject(root) }
        let report = try writeFixture("drc clean", named: "reserved-id.rpt", in: root)
        let digest = try SHA256ContentDigester().digest(fileAt: report, using: .sha256).hexadecimalValue
        let byteCount = Int64(try Data(contentsOf: report).count)
        let bundle = TapeoutEvidenceBundle(
            designName: "TOP",
            targetClockPeriod: 1e-9,
            claims: [
                .init(
                    axis: .drc,
                    statement: "layout is DRC clean",
                    passed: true,
                    measured: "0 violations",
                    artifact: try evidenceArtifact(
                        id: "evidence-error",
                        kind: "report",
                        path: report.path,
                        status: .available,
                        sha256: digest,
                        byteCount: byteCount
                    ),
                    kind: .signoff
                ),
            ],
            gdsPath: nil
        )

        await #expect(throws: XcircuiteEvidenceRunRecorder.RecorderError.duplicateArtifactID(
            "evidence-error"
        )) {
            try await XcircuiteEvidenceRunRecorder().record(
                bundle,
                projectRoot: root,
                runID: "run-evidence-reserved-id"
            )
        }
        let manifest = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunManifest(runID: "run-evidence-reserved-id")
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.filter { $0.artifactID == "evidence-error" }.count == 1)
    }

    @Test func symlinkedSourceIsCapturedAsARegularImmutableFile() async throws {
        let root = try makeProject()
        let outside = try makeProject()
        defer { removeProject(root) }
        defer { removeProject(outside) }
        let target = try writeFixture("verified report", named: "target.rpt", in: outside)
        let source = root.appending(path: "source-link.rpt")
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: target)
        let digest = try SHA256ContentDigester().digest(fileAt: target, using: .sha256).hexadecimalValue
        let byteCount = Int64(try Data(contentsOf: target).count)
        let bundle = TapeoutEvidenceBundle(
            designName: "TOP",
            targetClockPeriod: 1e-9,
            claims: [
                .init(
                    axis: .drc,
                    statement: "layout is DRC clean",
                    passed: true,
                    measured: "0 violations",
                    artifact: try evidenceArtifact(
                        id: "drc-report",
                        kind: "report",
                        path: source.path,
                        status: .available,
                        sha256: digest,
                        byteCount: byteCount
                    ),
                    kind: .signoff
                ),
            ],
            gdsPath: nil
        )

        let recorded = try await XcircuiteEvidenceRunRecorder().record(
            bundle,
            projectRoot: root,
            runID: "run-evidence-source-link"
        )
        let reference = try #require(recorded.manifest.artifacts.first {
            $0.artifactID == "drc-report"
        })
        let capturedURL = root.appending(path: reference.path)
        let values = try capturedURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        #expect(values.isRegularFile == true)
        #expect(values.isSymbolicLink != true)
        #expect(try String(contentsOf: capturedURL, encoding: .utf8) == "verified report")
    }

    @Test func symlinkedCaptureDirectoryCannotEscapeProjectRoot() async throws {
        let root = try makeProject()
        let outside = try makeProject()
        defer { removeProject(root) }
        defer { removeProject(outside) }
        let source = try writeFixture("drc clean", named: "source.rpt", in: root)
        let digest = try SHA256ContentDigester().digest(fileAt: source, using: .sha256).hexadecimalValue
        let byteCount = Int64(try Data(contentsOf: source).count)
        let runID = "run-evidence-symlink"
        let runDirectory = root.appending(path: ".xcircuite/runs/\(runID)")
        try FileManager.default.createDirectory(
            at: runDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: runDirectory.appending(path: "artifacts"),
            withDestinationURL: outside
        )
        let bundle = TapeoutEvidenceBundle(
            designName: "TOP",
            targetClockPeriod: 1e-9,
            claims: [
                .init(
                    axis: .drc,
                    statement: "layout is DRC clean",
                    passed: true,
                    measured: "0 violations",
                    artifact: try evidenceArtifact(
                        id: "symlink-report",
                        kind: "report",
                        path: source.path,
                        status: .available,
                        sha256: digest,
                        byteCount: byteCount
                    ),
                    kind: .signoff
                ),
            ],
            gdsPath: nil
        )
        let escapedPath = "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/artifacts/symlink-report-source.rpt"

        await #expect(throws: XcircuiteWorkspaceStoreError.pathOutsideWorkspace(escapedPath)) {
            try await XcircuiteEvidenceRunRecorder().record(
                bundle,
                projectRoot: root,
                runID: runID
            )
        }
        let outsideContents = try FileManager.default.contentsOfDirectory(
            at: outside,
            includingPropertiesForKeys: nil
        )
        #expect(outsideContents.isEmpty)
        let manifest = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunManifest(runID: runID)
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.contains { $0.artifactID == "evidence-error" })
    }
}

private func evidenceArtifact(
    id: String,
    kind: String,
    path: String,
    status: ArtifactPublicationStatus,
    sha256: String,
    byteCount: Int64
) throws -> TapeoutEvidenceArtifact {
    guard status == .available else {
        throw ArtifactPublicationRecordValidationError.unavailableStatusRequired
    }
    let url = URL(filePath: path)
    let locator = ArtifactLocator(
        location: try ArtifactLocation(fileURL: url),
        role: .output,
        kind: try ArtifactKind(rawValue: kind),
        format: try ArtifactFormat(
            rawValue: url.pathExtension.isEmpty ? ArtifactFormat.unknown.rawValue : url.pathExtension
        )
    )
    let reference = ArtifactReference(
        id: try ArtifactID(rawValue: id),
        locator: locator,
        digest: try ContentDigest(algorithm: .sha256, hexadecimalValue: sha256),
        byteCount: UInt64(byteCount)
    )
    return TapeoutEvidenceArtifact(
        publicationRecord: ArtifactPublicationRecord(reference: reference)
    )
}
