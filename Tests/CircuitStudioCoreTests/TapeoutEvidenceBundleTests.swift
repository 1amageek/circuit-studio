import Foundation
import Testing
@testable import CircuitStudioApp

/// BC4 — the evidence bundle. Tool-independent checks that `verify()` is a trustworthy gate:
/// it passes only when every required axis is present and passed AND its backing artifact
/// exists, and it throws (never silently passes) on a failed claim, a missing axis, or a
/// vanished artifact.
@Suite("Tapeout evidence bundle")
struct TapeoutEvidenceBundleTests {

    private func claim(_ axis: TapeoutEvidenceBundle.Axis, passed: Bool, artifact: String? = nil) -> TapeoutEvidenceBundle.Claim {
        .init(axis: axis, statement: "\(axis.rawValue) ok", passed: passed, measured: "m", artifact: artifact)
    }

    @Test("A bundle with every axis passing and artifacts present verifies")
    func passingBundleVerifies() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "evi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let artifact = dir.appending(path: "drc.log")
        try Data("clean".utf8).write(to: artifact)

        let bundle = TapeoutEvidenceBundle(designName: "d", targetClockPeriod: 2e-9, claims: [
            claim(.functional, passed: true), claim(.timing, passed: true),
            claim(.drc, passed: true, artifact: artifact.path), claim(.lvs, passed: true),
        ], gdsPath: nil)
        #expect(bundle.passed)
        try bundle.verify()                                   // does not throw
        #expect(!(try bundle.jsonManifest()).isEmpty)
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
            .init(axis: .timing, statement: "setup met", passed: true, measured: "ok", artifact: nil),
            .init(axis: .timing, statement: "spice validation", passed: false, measured: "failed", artifact: nil),
        ], gdsPath: nil)

        #expect(bundle.claims(for: .timing).count == 2)
        #expect(bundle.claim(.timing)?.passed == false)
    }

    @Test("A missing required axis throws (a constraint cannot be silently dropped)")
    func missingAxisThrows() {
        let bundle = TapeoutEvidenceBundle(designName: "d", targetClockPeriod: nil,
                                           claims: [claim(.functional, passed: true), claim(.timing, passed: true)],
                                           gdsPath: nil)
        #expect(throws: TapeoutEvidenceBundle.VerificationError.missingAxis(.drc)) {
            try bundle.verify(requiredAxes: [.functional, .timing, .drc, .lvs])
        }
    }

    @Test("A vanished backing artifact throws (evidence must be on disk)")
    func missingArtifactThrows() {
        let bundle = TapeoutEvidenceBundle(designName: "d", targetClockPeriod: nil, claims: [
            claim(.functional, passed: true, artifact: "/nonexistent/path/trace.json"),
        ], gdsPath: nil)
        #expect(throws: TapeoutEvidenceBundle.VerificationError.self) {
            try bundle.verify(requiredAxes: [.functional])
        }
    }
}
