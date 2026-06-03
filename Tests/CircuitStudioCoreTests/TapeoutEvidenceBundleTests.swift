import Foundation
import Testing
@testable import CircuitStudioApp

/// BC4 — the evidence bundle. Tool-independent checks that `verify()` is a trustworthy gate:
/// it passes only when every required axis is present and passed AND its backing artifact
/// exists, and it throws (never silently passes) on a failed claim, a missing axis, or a
/// vanished artifact.
@Suite("Tapeout evidence bundle")
struct TapeoutEvidenceBundleTests {

    private func claim(
        _ axis: TapeoutEvidenceBundle.Axis,
        passed: Bool,
        artifact: TapeoutEvidenceArtifact? = nil,
        kind: TapeoutEvidenceBundle.Claim.Kind = .signoff
    ) -> TapeoutEvidenceBundle.Claim {
        .init(axis: axis, statement: "\(axis.rawValue) ok", passed: passed, measured: "m", artifact: artifact, kind: kind)
    }

    private func publishTestArtifact(
        in directory: URL,
        fileName: String = "artifact.log",
        contents: String = "clean"
    ) throws -> TapeoutEvidenceArtifact {
        let record = try ArtifactPublisher(runDirectory: directory).publishData(
            Data(contents.utf8),
            id: fileName,
            kind: "test-artifact",
            relativePath: fileName
        )
        return TapeoutEvidenceArtifact(publicationRecord: record)
    }

    @Test("A bundle with every axis passing and artifacts present verifies")
    func passingBundleVerifies() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "evi-\(UUID().uuidString)")
        defer { removeCoreTestTemporaryDirectory(dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let functionalArtifact = try publishTestArtifact(in: dir, fileName: "functional.log")
        let timingArtifact = try publishTestArtifact(in: dir, fileName: "timing.log")
        let drcArtifact = try publishTestArtifact(in: dir, fileName: "drc.log")
        let lvsArtifact = try publishTestArtifact(in: dir, fileName: "lvs.log")

        let bundle = TapeoutEvidenceBundle(designName: "d", targetClockPeriod: 2e-9, claims: [
            claim(.functional, passed: true, artifact: functionalArtifact),
            claim(.timing, passed: true, artifact: timingArtifact),
            claim(.drc, passed: true, artifact: drcArtifact),
            claim(.lvs, passed: true, artifact: lvsArtifact),
        ], gdsPath: nil)
        #expect(bundle.passed)
        try bundle.verify(runDirectory: dir)
        let manifest = try bundle.jsonManifest()
        #expect(manifest.contains(#""schemaVersion" : 3"#))
        #expect(manifest.contains(#""kind" : "signoff""#))
        #expect(manifest.contains(#""sha256""#))
    }

    @Test("A passing claim without a backing artifact fails when artifacts are required")
    func passingClaimWithoutArtifactThrowsWhenArtifactsAreRequired() {
        let bundle = TapeoutEvidenceBundle(designName: "d", targetClockPeriod: nil, claims: [
            claim(.functional, passed: true),
        ], gdsPath: nil)

        #expect(throws: TapeoutEvidenceBundle.VerificationError.missingArtifactReference(
            axis: .functional,
            statement: "functional ok"
        )) {
            try bundle.verify(requiredAxes: [.functional], runDirectory: FileManager.default.temporaryDirectory)
        }
    }

    @Test("A failed claim fails the bundle and throws on verify")
    func failedClaimThrows() {
        let bundle = TapeoutEvidenceBundle(designName: "d", targetClockPeriod: nil, claims: [
            claim(.functional, passed: true), claim(.timing, passed: true),
            claim(.drc, passed: false), claim(.lvs, passed: true),
        ], gdsPath: nil)
        #expect(!bundle.passed)
        #expect(bundle.failing.map(\.axis) == [.drc])
        #expect(throws: TapeoutEvidenceBundle.VerificationError.claimFailed(axis: .drc, statement: "drc ok")) {
            try bundle.verify(requireArtifacts: false)
        }
    }

    @Test("Repeated axis lookup aggregates all claims for that axis")
    func repeatedAxisLookupAggregatesClaims() {
        let bundle = TapeoutEvidenceBundle(designName: "d", targetClockPeriod: nil, claims: [
            .init(axis: .timing, statement: "setup met", passed: true, measured: "ok", artifact: nil, kind: .signoff),
            .init(axis: .timing, statement: "spice validation", passed: false, measured: "failed", artifact: nil, kind: .signoff),
        ], gdsPath: nil)

        #expect(bundle.claims(for: .timing).count == 2)
        #expect(bundle.claim(.timing)?.passed == false)
    }

    @Test("Supporting evidence does not satisfy a required signoff axis")
    func supportingEvidenceDoesNotSatisfyRequiredAxis() {
        let bundle = TapeoutEvidenceBundle(designName: "d", targetClockPeriod: nil, claims: [
            claim(.antenna, passed: true, kind: .supportingEvidence),
        ], gdsPath: nil)

        #expect(bundle.claims(for: .antenna).count == 1)
        #expect(bundle.supportingClaims(for: .antenna).count == 1)
        #expect(bundle.signoffClaims(for: .antenna).isEmpty)
        #expect(bundle.claim(.antenna) == nil)
        #expect(!bundle.passed)
        #expect(throws: TapeoutEvidenceBundle.VerificationError.missingAxis(.antenna)) {
            try bundle.verify(requiredAxes: [.antenna], requireArtifacts: false)
        }
    }

    @Test("Failed supporting evidence is still audited")
    func failedSupportingEvidenceThrows() {
        let bundle = TapeoutEvidenceBundle(designName: "d", targetClockPeriod: nil, claims: [
            claim(.functional, passed: true),
            claim(.antenna, passed: false, kind: .supportingEvidence),
        ], gdsPath: nil)

        #expect(!bundle.passed)
        #expect(throws: TapeoutEvidenceBundle.VerificationError.claimFailed(axis: .antenna, statement: "antenna ok")) {
            try bundle.verify(requiredAxes: [.functional], requireArtifacts: false)
        }
    }

    @Test("Decoded claims without an explicit kind are rejected")
    func decodedClaimWithoutKindFails() {
        let data = Data("""
        {
          "artifact": null,
          "axis": "functional",
          "measured": "m",
          "passed": true,
          "statement": "functional ok"
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TapeoutEvidenceBundle.Claim.self, from: data)
        }
    }

    @Test("Bundles without schema version are rejected")
    func bundleWithoutSchemaVersionFails() {
        let data = Data("""
        {
          "designName": "d",
          "targetClockPeriod": null,
          "claims": [
            {
              "artifact": null,
              "axis": "functional",
              "kind": "signoff",
              "measured": "m",
              "passed": true,
              "statement": "functional ok"
            }
          ],
          "gdsPath": null
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TapeoutEvidenceBundle.self, from: data)
        }
    }

    @Test("Unsupported bundle schema versions are rejected")
    func unsupportedBundleSchemaVersionFails() {
        let data = Data("""
        {
          "schemaVersion": 1,
          "designName": "d",
          "targetClockPeriod": null,
          "claims": [
            {
              "artifact": null,
              "axis": "functional",
              "kind": "signoff",
              "measured": "m",
              "passed": true,
              "statement": "functional ok"
            }
          ],
          "gdsPath": null
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TapeoutEvidenceBundle.self, from: data)
        }
    }

    @Test("Current bundle schema rejects claims without explicit kind")
    func currentBundleSchemaRequiresClaimKind() {
        let data = Data("""
        {
          "schemaVersion": 3,
          "designName": "d",
          "targetClockPeriod": null,
          "claims": [
            {
              "artifact": null,
              "axis": "functional",
              "measured": "m",
              "passed": true,
              "statement": "functional ok"
            }
          ],
          "gdsPath": null
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TapeoutEvidenceBundle.self, from: data)
        }
    }

    @Test("A missing required axis throws (a constraint cannot be silently dropped)")
    func missingAxisThrows() {
        let bundle = TapeoutEvidenceBundle(designName: "d", targetClockPeriod: nil,
                                           claims: [claim(.functional, passed: true), claim(.timing, passed: true)],
                                           gdsPath: nil)
        #expect(!bundle.passed)
        #expect(throws: TapeoutEvidenceBundle.VerificationError.missingAxis(.drc)) {
            try bundle.verify(requiredAxes: [.functional, .timing, .drc, .lvs])
        }
    }

    @Test("A vanished backing artifact throws (evidence must be on disk)")
    func missingArtifactThrows() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "evi-missing-\(UUID().uuidString)")
        defer { removeCoreTestTemporaryDirectory(dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let artifact = try publishTestArtifact(in: dir, fileName: "trace.json")
        try FileManager.default.removeItem(at: dir.appending(path: artifact.path))

        let bundle = TapeoutEvidenceBundle(designName: "d", targetClockPeriod: nil, claims: [
            claim(.functional, passed: true, artifact: artifact),
        ], gdsPath: nil)
        #expect(throws: TapeoutEvidenceBundle.VerificationError.self) {
            try bundle.verify(requiredAxes: [.functional], runDirectory: dir)
        }
    }

    @Test("An altered backing artifact throws even when the file still exists")
    func alteredArtifactThrows() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "evi-altered-\(UUID().uuidString)")
        defer { removeCoreTestTemporaryDirectory(dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let artifact = try publishTestArtifact(in: dir, fileName: "trace.json", contents: "clean")
        try Data("dirty".utf8).write(to: dir.appending(path: artifact.path))

        let bundle = TapeoutEvidenceBundle(designName: "d", targetClockPeriod: nil, claims: [
            claim(.functional, passed: true, artifact: artifact),
        ], gdsPath: nil)
        #expect(throws: TapeoutEvidenceBundle.VerificationError.self) {
            try bundle.verify(requiredAxes: [.functional], runDirectory: dir)
        }
    }

    @Test("A path-only claim artifact is rejected by the current schema")
    func pathOnlyArtifactFailsDecoding() {
        let data = Data("""
        {
          "schemaVersion": 3,
          "designName": "d",
          "targetClockPeriod": null,
          "claims": [
            {
              "artifact": "/tmp/trace.json",
              "axis": "functional",
              "kind": "signoff",
              "measured": "m",
              "passed": true,
              "statement": "functional ok"
            }
          ],
          "gdsPath": null
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TapeoutEvidenceBundle.self, from: data)
        }
    }
}
