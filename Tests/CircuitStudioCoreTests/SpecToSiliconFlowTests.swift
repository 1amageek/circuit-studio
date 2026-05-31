import Foundation
import Testing
@testable import CircuitStudioApp

/// BC4 / DoD-6 — the autonomous single-call flow: from an intent (program + target clock) it
/// closes functional + timing (always) and physical (when the toolchain is present), emits a
/// GDS, and produces a machine-checkable evidence bundle — no human in the loop.
@Suite("Spec-to-silicon flow")
struct SpecToSiliconFlowTests {

    static let fibonacci = """
        LDI 1
        STA 0
        STA 1
        loop: LDA 0
        ADD 1
        STA 2
        LDA 1
        STA 0
        LDA 2
        STA 1
        JMP loop
        """

    private func intent() throws -> SpecToSiliconFlow.Intent {
        SpecToSiliconFlow.Intent(designName: "acc4flow",
                                 program: try ACC4Assembler().assemble(Self.fibonacci),
                                 cycles: 60, targetClockPeriod: 5e-9)
    }

    @Test("Autonomous functional + timing closure yields a verifiable bundle (tool-independent)",
          .timeLimit(.minutes(4)))
    func functionalTimingBundle() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "flow-\(UUID().uuidString)")
        let result = try await SpecToSiliconFlow(runPhysical: false).run(try intent(), artifactDirectory: dir)

        #expect(result.bundle.claim(.functional)?.passed == true)
        #expect(result.bundle.claim(.timing)?.passed == true)
        // The functional + timing axes verify, and their artifacts are on disk.
        try result.bundle.verify(requiredAxes: [.functional, .timing])
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "acc4flow.evidence.json").path))
        // Requiring the physical axes (not run) must FAIL — honest, never a silent pass.
        #expect(throws: TapeoutEvidenceBundle.VerificationError.self) {
            try result.bundle.verify(requiredAxes: [.functional, .timing, .drc, .lvs])
        }
    }

    @Test("Full autonomous flow incl. real DRC + LVS yields a fully-verified bundle + GDS",
          .enabled(if: Sky130GeneratedDRCTests.available), .timeLimit(.minutes(12)))
    func fullBundleSignsOff() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "flow-full-\(UUID().uuidString)")
        let result = try await SpecToSiliconFlow(runPhysical: true).run(try intent(), artifactDirectory: dir)

        #expect(result.bundle.passed, "failing: \(result.bundle.failing.map { ($0.axis, $0.measured) })")
        // Every axis present, passed, and backed by an artifact on disk.
        try result.bundle.verify(requiredAxes: [.functional, .timing, .drc, .lvs])
        let gds = try #require(result.gdsPath)
        #expect(FileManager.default.fileExists(atPath: gds.path))
        #expect(result.bundle.claim(.drc)?.passed == true)
        #expect(result.bundle.claim(.lvs)?.passed == true)
    }
}
