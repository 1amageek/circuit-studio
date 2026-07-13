import Testing
@testable import CircuitStudioApp

@Suite("LVS signoff v2 host contract", .timeLimit(.minutes(1)))
struct LVSSignoffV2ContractTests {
    @Test func completedMatchAndReadyAuthorizesSignoff() {
        let projection = LVSSignoffProjection(document: document(
            schemaVersion: 2,
            passed: true,
            completed: true,
            executionStatus: "completed",
            verdict: "match",
            readiness: "ready",
            blockingReasons: []
        ))

        #expect(projection.status == "match")
        #expect(projection.passed)
    }

    @Test func blockingReasonsRemainVisible() {
        let reason = LVSReviewBlockingReason(
            code: "device_policy_partial",
            message: "The selected device policy was only partially applied.",
            evidenceReferences: ["lvs-device-policy-application-report"]
        )
        let projection = LVSSignoffProjection(document: document(
            schemaVersion: 2,
            passed: false,
            completed: true,
            executionStatus: "completed",
            verdict: "blocked",
            readiness: "blocked",
            blockingReasons: [reason]
        ))

        #expect(projection.status == "blocked")
        #expect(!projection.passed)
        #expect(projection.blockingReasons == [reason])
    }

    @Test func legacyPassedFieldCannotAuthorizeFlowSignoff() {
        let projection = LVSSignoffProjection(document: document(
            schemaVersion: 1,
            passed: true,
            completed: true,
            executionStatus: nil,
            verdict: nil,
            readiness: nil,
            blockingReasons: nil
        ))

        #expect(projection.status == "blocked")
        #expect(!projection.passed)
        #expect(projection.blockingReasons.contains { $0.code == "lvs_v2_contract_missing" })
    }

    private func document(
        schemaVersion: Int,
        passed: Bool,
        completed: Bool,
        executionStatus: String?,
        verdict: String?,
        readiness: String?,
        blockingReasons: [LVSReviewBlockingReason]?
    ) -> LVSReviewDocument {
        LVSReviewDocument(
            schemaVersion: schemaVersion,
            reportURL: nil,
            manifestURL: nil,
            summary: LVSReviewSummary(
                status: passed ? "passed" : "failed",
                executionStatus: executionStatus,
                verdict: verdict,
                readiness: readiness,
                blockingReasons: blockingReasons,
                toolName: "NativeLVS",
                topCell: "TOP",
                layoutInputKind: "layout-netlist",
                passed: passed,
                completed: completed,
                activeMismatchCount: verdict == "mismatch" ? 1 : 0,
                waivedMismatchCount: 0,
                mismatchBuckets: [],
                extractedLayoutNetlistURL: nil
            )
        )
    }
}
