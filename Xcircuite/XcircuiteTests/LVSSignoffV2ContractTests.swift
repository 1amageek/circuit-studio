import Testing
@testable import CircuitStudioApp

@Suite("LVS signoff host contract", .timeLimit(.minutes(1)))
struct LVSSignoffContractTests {
    @Test func completedMatchAndReadyAuthorizesSignoff() {
        let projection = LVSSignoffProjection(document: document(
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
            executionStatus: "completed",
            verdict: "blocked",
            readiness: "blocked",
            blockingReasons: [reason]
        ))

        #expect(projection.status == "blocked")
        #expect(!projection.passed)
        #expect(projection.blockingReasons == [reason])
    }

    private func document(
        executionStatus: String,
        verdict: String,
        readiness: String,
        blockingReasons: [LVSReviewBlockingReason]
    ) -> LVSReviewDocument {
        LVSReviewDocument(
            schemaVersion: LVSReviewDocument.currentSchemaVersion,
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
