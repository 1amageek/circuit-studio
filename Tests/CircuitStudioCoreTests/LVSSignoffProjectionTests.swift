import Testing
@testable import CircuitStudioApp

@Suite("LVS signoff projection", .timeLimit(.minutes(1)))
struct LVSSignoffProjectionTests {
    @Test func v2MatchUsesExecutionVerdictAndReadiness() {
        let projection = LVSSignoffProjection(document: document(
            executionStatus: "completed",
            verdict: "match",
            readiness: "ready"
        ))

        #expect(projection.status == "match")
        #expect(projection.passed)
        #expect(projection.blockingReasons.isEmpty)
    }

    @Test func blockedV2ResultRemainsBlockedAndExplainsWhy() {
        let reason = LVSReviewBlockingReason(
            code: "device_policy_partial",
            message: "The selected device policy was only partially applied.",
            evidenceReferences: ["lvs-device-policy-application-report"]
        )
        let projection = LVSSignoffProjection(document: document(
            executionStatus: "completed",
            verdict: "blocked",
            readiness: "blocked",
            blockingReasons: [reason]
        ))

        #expect(projection.status == "blocked")
        #expect(!projection.passed)
        #expect(projection.blockingReasons == [reason])
    }

    @Test func schemaV1CannotAuthorizeSignoff() {
        let projection = LVSSignoffProjection(document: document(
            schemaVersion: 1,
            executionStatus: "completed",
            verdict: "match",
            readiness: "ready"
        ))

        #expect(projection.status == "blocked")
        #expect(!projection.passed)
        #expect(projection.blockingReasons.contains { $0.code == "lvs_v2_contract_missing" })
    }

    private func document(
        schemaVersion: Int = 2,
        executionStatus: String,
        verdict: String,
        readiness: String,
        blockingReasons: [LVSReviewBlockingReason] = []
    ) -> LVSReviewDocument {
        LVSReviewDocument(
            schemaVersion: schemaVersion,
            reportURL: nil,
            manifestURL: nil,
            summary: LVSReviewSummary(
                executionStatus: executionStatus,
                verdict: verdict,
                readiness: readiness,
                blockingReasons: blockingReasons,
                toolName: "NativeLVS",
                topCell: "TOP",
                layoutInputKind: "layout-netlist",
                activeMismatchCount: verdict == "mismatch" ? 1 : 0,
                waivedMismatchCount: 0,
                mismatchBuckets: [],
                extractedLayoutNetlistURL: nil
            )
        )
    }
}
