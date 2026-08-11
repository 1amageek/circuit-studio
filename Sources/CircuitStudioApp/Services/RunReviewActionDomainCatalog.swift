import Xcircuite

struct RunReviewActionDomainCatalog: Sendable {
    private struct OperationKey: Hashable, Sendable {
        let domainID: String
        let operationID: String
    }

    private let operationsByKey: [OperationKey: XcircuiteActionDomainOperation]

    init(snapshot: XcircuitePlanningActionDomainSnapshot) {
        var indexed: [OperationKey: XcircuiteActionDomainOperation] = [:]
        indexed.reserveCapacity(snapshot.domains.reduce(0) { $0 + $1.operations.count })
        for domain in snapshot.domains {
            for operation in domain.operations {
                indexed[
                    OperationKey(
                        domainID: domain.domainID,
                        operationID: operation.operationID
                    )
                ] = operation
            }
        }
        operationsByKey = indexed
    }

    static var empty: Self {
        Self(snapshot: XcircuitePlanningActionDomainSnapshot(
            runID: "run-review",
            generatedAt: "run-review-projection",
            domains: []
        ))
    }

    func repairHint(
        domainID: String,
        operationID: String,
        reason: String
    ) -> RunReviewSignoffRepairActionHint? {
        guard let operation = operationsByKey[
            OperationKey(domainID: domainID, operationID: operationID)
        ], operation.candidateMutationExecutable else {
            return nil
        }
        return RunReviewSignoffRepairActionHint(
            domainID: domainID,
            operationID: operation.operationID,
            readinessState: operation.readinessState,
            reason: reason,
            requiredInputRefs: operation.inputRefs,
            verificationGates: operation.verificationGates
        )
    }
}
