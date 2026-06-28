import Foundation
import Xcircuite
import XcircuitePackage

public struct RunReviewSignoffRepairCandidateCycleResult: Sendable, Hashable, Codable {
    public let runID: String
    public let cycleIndex: Int
    public let strategy: String
    public let verificationMode: String
    public let planningResult: RunReviewSignoffRepairPlanningResult
    public let candidateGeneration: XcircuiteCandidatePlanGenerationResult
    public let candidateExecution: XcircuiteCandidatePlanExecutionResult
    public let candidateVerification: XcircuiteCandidatePlanVerificationResult
    public let cycleActionRecord: XcircuiteRunActionRecord

    public init(
        runID: String,
        cycleIndex: Int = 1,
        strategy: String,
        verificationMode: String,
        planningResult: RunReviewSignoffRepairPlanningResult,
        candidateGeneration: XcircuiteCandidatePlanGenerationResult,
        candidateExecution: XcircuiteCandidatePlanExecutionResult,
        candidateVerification: XcircuiteCandidatePlanVerificationResult,
        cycleActionRecord: XcircuiteRunActionRecord
    ) {
        self.runID = runID
        self.cycleIndex = cycleIndex
        self.strategy = strategy
        self.verificationMode = verificationMode
        self.planningResult = planningResult
        self.candidateGeneration = candidateGeneration
        self.candidateExecution = candidateExecution
        self.candidateVerification = candidateVerification
        self.cycleActionRecord = cycleActionRecord
    }
}
