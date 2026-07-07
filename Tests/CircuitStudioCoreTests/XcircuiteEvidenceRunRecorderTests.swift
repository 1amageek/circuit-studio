import Foundation
import Testing
import XcircuitePackage
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
        for reference in recorded.manifest.artifacts {
            let url = root.appendingPathComponent(reference.path)
            #expect(FileManager.default.fileExists(atPath: url.path), "\(reference.path)")
            #expect(reference.sha256 == (try XcircuiteHasher().sha256(fileAt: url)))
            #expect(reference.producedByRunID == "run-evidence-1")
        }
        let kinds = Set(recorded.manifest.artifacts.map(\.kind))
        #expect(kinds.contains(.report))
        #expect(kinds.contains(.layout))

        // The project manifest lists the run with its final status.
        let project = try XcircuitePackageStore().loadManifest(forProjectAt: root)
        let reference = try #require(project.runs.first { $0.runID == "run-evidence-1" })
        #expect(reference.status == .succeeded)
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
    }
}
