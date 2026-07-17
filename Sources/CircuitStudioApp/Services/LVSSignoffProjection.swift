import Foundation

struct LVSSignoffProjection: Sendable, Hashable {
    let status: String
    let passed: Bool
    let executionStatus: String
    let verdict: String
    let readiness: String
    let blockingReasons: [LVSReviewBlockingReason]

    init(document: LVSReviewDocument) {
        let summary = document.summary
        executionStatus = summary.executionStatus
        verdict = summary.verdict
        readiness = summary.readiness

        var reasons = summary.blockingReasons
        let hasCurrentSchema = document.schemaVersion == LVSReviewDocument.currentSchemaVersion
        let valuesAreKnown = Self.executionStatuses.contains(executionStatus)
            && Self.verdicts.contains(verdict)
            && Self.readinessValues.contains(readiness)
        guard hasCurrentSchema, valuesAreKnown else {
            status = "blocked"
            passed = false
            reasons.append(Self.contractReason(
                code: "lvs_contract_missing",
                message: "The LVS summary does not contain the current execution, verdict, and readiness contract."
            ))
            blockingReasons = reasons
            return
        }

        let expectedPassed = summary.executionStatus == "completed"
            && summary.verdict == "match"
            && summary.readiness == "ready"
        let blockedContractIsValid: Bool
        if summary.executionStatus == "completed"
            && summary.verdict != "blocked"
            && summary.readiness == "ready" {
            blockedContractIsValid = reasons.isEmpty
        } else {
            blockedContractIsValid = summary.verdict == "blocked"
                && summary.readiness == "blocked"
                && !reasons.isEmpty
        }

        guard blockedContractIsValid else {
            status = "blocked"
            passed = false
            reasons.append(Self.contractReason(
                code: "lvs_contract_inconsistent",
                message: "The LVS summary contains contradictory execution, verdict, readiness, or blocking-reason fields."
            ))
            blockingReasons = reasons
            return
        }

        status = expectedPassed ? "match" : summary.verdict
        passed = expectedPassed
        blockingReasons = reasons
    }

    private static func contractReason(
        code: String,
        message: String
    ) -> LVSReviewBlockingReason {
        LVSReviewBlockingReason(
            code: code,
            message: message,
            evidenceReferences: []
        )
    }

    private static let executionStatuses = Set(["completed", "timedOut", "cancelled", "failed"])
    private static let verdicts = Set(["match", "mismatch", "blocked"])
    private static let readinessValues = Set(["ready", "blocked"])
}
