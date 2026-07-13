import Foundation
import Testing
import DesignFlowKernel
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

    @Test func bundleLandsInRunLedgerWithVerifiedCopies() throws {
        let root = try makeProject()
        defer { removeProject(root) }
        let scratch = root.appendingPathComponent("scratch")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        let report = try writeFixture("drc clean", named: "drc.rpt", in: scratch)
        let digest = try XcircuiteHasher().sha256(fileAt: report)
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
                    artifact: TapeoutEvidenceArtifact(
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

        let recorded = try XcircuiteEvidenceRunRecorder().record(
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
            #expect(reference.sha256 == (try XcircuiteHasher().sha256(fileAt: url)))
            #expect(reference.producedByRunID == "run-evidence-1")
        }
        let kinds = Set(recorded.manifest.artifacts.map(\.kind))
        #expect(kinds.contains(.report))
        #expect(kinds.contains(.layout))

        // The project manifest only locates the run; lifecycle is resolved from its manifest.
        let snapshots = try XcircuitePackageStore().listRunSnapshots(inProjectAt: root)
        let snapshot = try #require(snapshots.first { $0.runID == "run-evidence-1" })
        #expect(snapshot.status == .succeeded)
        #expect(snapshot.reference.manifestPath == ".xcircuite/runs/run-evidence-1/manifest.json")
    }

    @Test func failingBundleIsRecordedAsFailed() throws {
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

        let recorded = try XcircuiteEvidenceRunRecorder().record(
            bundle, projectRoot: root, runID: "run-evidence-2"
        )
        #expect(recorded.manifest.status == .failed)
    }

    @Test func tamperedArtifactDigestIsAnIntegrityError() throws {
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
                    artifact: TapeoutEvidenceArtifact(
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

        #expect(throws: XcircuiteEvidenceRunRecorder.RecorderError.self) {
            try XcircuiteEvidenceRunRecorder().record(
                bundle, projectRoot: root, runID: "run-evidence-3"
            )
        }
        let manifest = try XcircuitePackageStore().loadRunManifest(
            runID: "run-evidence-3",
            inProjectAt: root
        )
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.contains { $0.path.hasSuffix("evidence.json") })
        #expect(manifest.artifacts.contains { $0.artifactID == "evidence-error" })
    }

    @Test func tamperedArtifactByteCountIsAnIntegrityError() throws {
        let root = try makeProject()
        defer { removeProject(root) }
        let scratch = root.appendingPathComponent("scratch")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let report = try writeFixture("byte-count content", named: "drc.rpt", in: scratch)
        let digest = try XcircuiteHasher().sha256(fileAt: report)
        let reportBytes = Int64(try Data(contentsOf: report).count)

        let bundle = TapeoutEvidenceBundle(
            designName: "TOP",
            targetClockPeriod: 1e-9,
            claims: [
                .init(
                    axis: .drc, statement: "layout is DRC clean", passed: true,
                    measured: "0 violations",
                    artifact: TapeoutEvidenceArtifact(
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

        #expect(throws: XcircuiteEvidenceRunRecorder.RecorderError.artifactByteCountMismatch(
            id: "drc-report",
            claimed: reportBytes + 1,
            actual: reportBytes
        )) {
            try XcircuiteEvidenceRunRecorder().record(
                bundle, projectRoot: root, runID: "run-evidence-4"
            )
        }
        let manifest = try XcircuitePackageStore().loadRunManifest(
            runID: "run-evidence-4",
            inProjectAt: root
        )
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.contains { $0.artifactID == "evidence-error" })
    }

    @Test func unsafeArtifactIDIsRejectedBeforeCapture() throws {
        let root = try makeProject()
        defer { removeProject(root) }
        let report = try writeFixture("drc clean", named: "unsafe-id.rpt", in: root)
        let digest = try XcircuiteHasher().sha256(fileAt: report)
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
                    artifact: TapeoutEvidenceArtifact(
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

        #expect(throws: XcircuitePackageError.invalidIdentifier(
            kind: XcircuiteIdentifierKind.artifactID.rawValue,
            value: "../escape"
        )) {
            try XcircuiteEvidenceRunRecorder().record(
                bundle,
                projectRoot: root,
                runID: "run-evidence-unsafe-id"
            )
        }
        let manifest = try XcircuitePackageStore().loadRunManifest(
            runID: "run-evidence-unsafe-id",
            inProjectAt: root
        )
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.contains { $0.artifactID == "evidence-error" })
    }

    @Test func duplicateArtifactIDsAreRejectedAsAmbiguousEvidence() throws {
        let root = try makeProject()
        defer { removeProject(root) }
        let first = try writeFixture("drc clean", named: "first.rpt", in: root)
        let second = try writeFixture("lvs clean", named: "second.rpt", in: root)
        let firstDigest = try XcircuiteHasher().sha256(fileAt: first)
        let secondDigest = try XcircuiteHasher().sha256(fileAt: second)
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
                    artifact: TapeoutEvidenceArtifact(
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
                    artifact: TapeoutEvidenceArtifact(
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

        #expect(throws: XcircuiteEvidenceRunRecorder.RecorderError.duplicateArtifactID(
            "signoff-report"
        )) {
            try XcircuiteEvidenceRunRecorder().record(
                bundle,
                projectRoot: root,
                runID: "run-evidence-duplicate-id"
            )
        }
        let manifest = try XcircuitePackageStore().loadRunManifest(
            runID: "run-evidence-duplicate-id",
            inProjectAt: root
        )
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.contains { $0.artifactID == "evidence-error" })
    }

    @Test func reservedFailureArtifactIDCannotBeClaimedByBundle() throws {
        let root = try makeProject()
        defer { removeProject(root) }
        let report = try writeFixture("drc clean", named: "reserved-id.rpt", in: root)
        let digest = try XcircuiteHasher().sha256(fileAt: report)
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
                    artifact: TapeoutEvidenceArtifact(
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

        #expect(throws: XcircuiteEvidenceRunRecorder.RecorderError.duplicateArtifactID(
            "evidence-error"
        )) {
            try XcircuiteEvidenceRunRecorder().record(
                bundle,
                projectRoot: root,
                runID: "run-evidence-reserved-id"
            )
        }
        let manifest = try XcircuitePackageStore().loadRunManifest(
            runID: "run-evidence-reserved-id",
            inProjectAt: root
        )
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.filter { $0.artifactID == "evidence-error" }.count == 1)
    }

    @Test func symlinkedSourceIsCapturedAsARegularImmutableFile() throws {
        let root = try makeProject()
        let outside = try makeProject()
        defer { removeProject(root) }
        defer { removeProject(outside) }
        let target = try writeFixture("verified report", named: "target.rpt", in: outside)
        let source = root.appending(path: "source-link.rpt")
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: target)
        let digest = try XcircuiteHasher().sha256(fileAt: target)
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
                    artifact: TapeoutEvidenceArtifact(
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

        let recorded = try XcircuiteEvidenceRunRecorder().record(
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

    @Test func symlinkedCaptureDirectoryCannotEscapeProjectRoot() throws {
        let root = try makeProject()
        let outside = try makeProject()
        defer { removeProject(root) }
        defer { removeProject(outside) }
        let source = try writeFixture("drc clean", named: "source.rpt", in: root)
        let digest = try XcircuiteHasher().sha256(fileAt: source)
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
                    artifact: TapeoutEvidenceArtifact(
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
        let escapedPath = "\(XcircuitePackage.directoryName)/runs/\(runID)/artifacts/symlink-report-source.rpt"

        #expect(throws: XcircuitePackageError.unsafeProjectPath(escapedPath)) {
            try XcircuiteEvidenceRunRecorder().record(
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
        let manifest = try XcircuitePackageStore().loadRunManifest(
            runID: runID,
            inProjectAt: root
        )
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.contains { $0.artifactID == "evidence-error" })
    }
}
