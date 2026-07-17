import CircuiteFoundation
import Foundation
import STAEngine
import Testing
@testable import CircuitStudioApp

/// BC1.4 — the unified verdict. Functional (golden-trace) and timing (STA) signoff fold into
/// ONE result that passes only when every axis passes; a single failing axis fails the whole
/// and a missing required axis throws, so a constraint can never be silently dropped.
@Suite("Multi-constraint signoff")
struct MultiConstraintSignoffTests {

    private func result(setupSlack: Double, holdSlack: Double = 5e-12) throws -> STAExecutionResult {
        let timestamp = Date(timeIntervalSince1970: 1)
        return STAExecutionResult(
            runID: "unit",
            status: .completed,
            payload: STAPayload(
                worstSetupSlack: setupSlack,
                worstHoldSlack: holdSlack,
                analyzedCorners: ["tt"]
            ),
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(kind: .engine, identifier: "timing.sta", version: "1"),
                startedAt: timestamp,
                completedAt: timestamp
            )
        )
    }

    @Test("Functional + timing fold into a single passing verdict")
    func combinesPassingAxes() throws {
        // Functional: the gate CPU matches the reference on a small program.
        let program = try ACC4Assembler().assemble("LDI 5\nADD 0\nSUB 0\nJMP 0")
        let golden = ACC4Reference().run(program, cycles: 16).trace
        let actual = try ACC4Machine().run(program, cycles: 16)
        let fn = MultiConstraintSignoff.functional(passed: actual == golden, cycles: 16, evidence: "ACC4Machine==ACC4Reference")

        let timing = MultiConstraintSignoff.timing(try result(setupSlack: 1e-9), evidence: "STA")
        let verdict = try MultiConstraintSignoff().combine([fn, timing])

        #expect(verdict.passed)
        #expect(verdict.failing.isEmpty)
        #expect(verdict.axis(.functional)?.passed == true)
        #expect(verdict.axis(.timing)?.passed == true)
    }

    @Test("A timing violation fails the whole signoff even when function is correct")
    func timingViolationFailsAll() throws {
        let fn = MultiConstraintSignoff.functional(passed: true, cycles: 16, evidence: "ok")
        let timing = MultiConstraintSignoff.timing(try result(setupSlack: -1e-12), evidence: "STA")
        let verdict = try MultiConstraintSignoff().combine([fn, timing])

        #expect(!verdict.passed)
        #expect(verdict.failing.map(\.axis) == [.timing])
    }

    @Test("A missing required axis throws (a constraint cannot be silently dropped)")
    func missingAxisThrows() {
        let fn = MultiConstraintSignoff.functional(passed: true, cycles: 16, evidence: "ok")
        #expect(throws: MultiConstraintSignoff.SignoffError.missingRequiredAxis(.timing)) {
            _ = try MultiConstraintSignoff().combine([fn])
        }
    }
}
