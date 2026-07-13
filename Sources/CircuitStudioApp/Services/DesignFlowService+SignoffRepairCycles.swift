import Foundation
import CircuitStudioCore
import Xcircuite
import DesignFlowKernel

extension DesignFlowService {
    func formulateSignoffRepairPlanningProblem(
        _ command: DesignFlowCommand
    ) throws -> DesignFlowCommandResult {
        guard let projectRootPath = command.projectRootPath else {
            throw DesignFlowCommandError.missingProjectRoot
        }
        guard let runID = command.runID else {
            throw DesignFlowCommandError.missingRunID
        }
        guard let reviewer = command.approvalReviewer else {
            throw DesignFlowCommandError.missingApprovalReviewer
        }

        let projectRoot = URL(filePath: projectRootPath)
        let result = try RunReviewService().formulateSignoffRepairPlanningProblem(
            runID: runID,
            drcRepairHintPath: command.drcRepairHintPath,
            lvsRepairHintPath: command.lvsRepairHintPath,
            formulationID: command.planningFormulationID,
            intentID: command.planningIntentID,
            intent: command.planningIntent,
            problemID: command.planningProblemID,
            actorKind: command.actionActorKind ?? .human,
            actorIdentifier: reviewer,
            note: command.approvalNote ?? "",
            projectRoot: projectRoot
        )
        return DesignFlowCommandResult(
            kind: command.kind,
            runID: runID,
            projectRootPath: projectRootPath,
            actionLogPath: try actionLogPath(projectRoot: projectRoot, runID: runID),
            signoffRepairPlanningResult: result,
            actionDomainPath: try absolutePath(for: result.actionDomainArtifact, projectRoot: projectRoot),
            repairFormulationPath: try absolutePath(for: result.repairFormulationArtifact, projectRoot: projectRoot),
            planningProblemPath: try absolutePath(for: result.planningProblemArtifact, projectRoot: projectRoot),
            actionRecordIDs: [result.actionRecord.actionID],
            message: result.actionRecord.actionID
        )
    }

    func runSignoffRepairCandidateCycle(
        _ command: DesignFlowCommand
    ) async throws -> DesignFlowCommandResult {
        guard let projectRootPath = command.projectRootPath else {
            throw DesignFlowCommandError.missingProjectRoot
        }
        guard let runID = command.runID else {
            throw DesignFlowCommandError.missingRunID
        }
        guard let reviewer = command.approvalReviewer else {
            throw DesignFlowCommandError.missingApprovalReviewer
        }

        let projectRoot = URL(filePath: projectRootPath)
        let strategy = command.candidateStrategy ?? "first-ready-action-per-objective"
        let verificationMode = command.candidateVerificationMode ?? "post-execution"
        let planning = try RunReviewService().formulateSignoffRepairPlanningProblem(
            runID: runID,
            drcRepairHintPath: command.drcRepairHintPath,
            lvsRepairHintPath: command.lvsRepairHintPath,
            formulationID: command.planningFormulationID,
            intentID: command.planningIntentID,
            intent: command.planningIntent,
            problemID: command.planningProblemID,
            actorKind: command.actionActorKind ?? .human,
            actorIdentifier: reviewer,
            note: command.approvalNote ?? "",
            projectRoot: projectRoot
        )
        let generation = try XcircuiteCandidatePlanGenerator().generateCandidatePlan(
            request: XcircuiteCandidatePlanGenerationRequest(
                runID: runID,
                problemPath: planning.planningProblemArtifact.path,
                rejectedPlansArtifactID: XcircuitePlanningArtifactStore.rejectedPlansArtifactID,
                strategy: strategy,
                calibrationPolicy: "disabled"
            ),
            projectRoot: projectRoot
        )
        let execution = try await XcircuiteCandidatePlanExecutor().executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(
                runID: runID,
                candidatePlanPath: generation.candidatePlanArtifact.path,
                actor: reviewer
            ),
            projectRoot: projectRoot
        )
        let verification = try await XcircuiteCandidatePlanVerifier().verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: runID,
                candidatePlanPath: generation.candidatePlanArtifact.path,
                verificationMode: verificationMode
            ),
            projectRoot: projectRoot
        )
        let cycleIndex = try nextSignoffRepairCandidateCycleIndex(
            runID: runID,
            projectRoot: projectRoot
        )
        let cycleActionID = "signoff-repair-candidate-cycle-\(UUID().uuidString)"
        let cycleCreatedAt = Date()
        let priorCycles = try RunReviewService()
            .loadRun(runID: runID, projectRoot: projectRoot)
            .signoff
            .repairCandidateCycles
        let selectedActionDomainIDs = selectedActionDomainIDs(from: generation.symbolicPlannerTrace)
        let planningProblem = try planningProblem(
            from: planning.planningProblemArtifact,
            projectRoot: projectRoot
        )
        let selectedObjectiveDomainIDs = selectedObjectiveDomainIDs(
            from: generation.symbolicPlannerTrace,
            problem: planningProblem
        )
        let currentCycle = RunReviewSignoffRepairCandidateCycleHistoryItem(
            actionID: cycleActionID,
            cycleIndex: cycleIndex,
            status: verification.accepted ? .succeeded : .blocked,
            planID: generation.planID,
            generationStatus: generation.status,
            executionStatus: execution.status,
            verificationStatus: verification.status,
            accepted: verification.accepted,
            rejectedPlansPath: generation.symbolicPlannerTrace?.rejectedPlansPath,
            rejectedPlanFeedbackRecordCount: generation.symbolicPlannerTrace?.rejectedPlanFeedbackRecordCount ?? 0,
            globalRejectedPlanFeedbackCount: generation.symbolicPlannerTrace?.globalRejectedPlanFeedbackCount ?? 0,
            selectedActionIDs: generation.symbolicPlannerTrace?.selectedActionIDs ?? [],
            selectedActionDomainIDs: selectedActionDomainIDs,
            selectedObjectiveDomainIDs: selectedObjectiveDomainIDs,
            feedbackPenalizedActionIDs: feedbackPenalizedActionIDs(from: generation.symbolicPlannerTrace),
            feedbackRankChanges: feedbackRankChanges(from: generation.symbolicPlannerTrace),
            feedbackScoreDeltas: feedbackScoreDeltas(from: generation.symbolicPlannerTrace),
            candidatePlanArtifact: generation.candidatePlanArtifact,
            planExecutionArtifact: execution.planExecutionArtifact,
            planVerificationArtifact: verification.planVerificationArtifact,
            rejectedPlansArtifact: verification.rejectedPlansArtifact,
            designDiffArtifact: execution.designDiffArtifact,
            createdAt: cycleCreatedAt
        )
        let historySummary = RunReviewSignoffRepairCandidateCycleHistorySummary(
            cycles: priorCycles + [currentCycle]
        )
        let historySummaryArtifact = try persistSignoffRepairCandidateCycleHistorySummary(
            historySummary,
            runID: runID,
            projectRoot: projectRoot
        )
        let cycleActionRecord = try appendSignoffRepairCandidateCycleActionRecord(
            actionID: cycleActionID,
            runID: runID,
            cycleIndex: cycleIndex,
            actorKind: command.actionActorKind ?? .human,
            actorIdentifier: reviewer,
            createdAt: cycleCreatedAt,
            strategy: strategy,
            verificationMode: verificationMode,
            planning: planning,
            generation: generation,
            execution: execution,
            verification: verification,
            selectedActionDomainIDs: selectedActionDomainIDs,
            selectedObjectiveDomainIDs: selectedObjectiveDomainIDs,
            historySummaryArtifact: historySummaryArtifact,
            projectRoot: projectRoot
        )
        let cycleResult = RunReviewSignoffRepairCandidateCycleResult(
            runID: runID,
            cycleIndex: cycleIndex,
            strategy: strategy,
            verificationMode: verificationMode,
            planningResult: planning,
            candidateGeneration: generation,
            candidateExecution: execution,
            candidateVerification: verification,
            cycleActionRecord: cycleActionRecord
        )
        return DesignFlowCommandResult(
            kind: command.kind,
            runID: runID,
            projectRootPath: projectRootPath,
            actionLogPath: try actionLogPath(projectRoot: projectRoot, runID: runID),
            designDiffPath: try execution.designDiffArtifact.map {
                try absolutePath(for: $0, projectRoot: projectRoot)
            },
            signoffRepairPlanningResult: planning,
            signoffRepairCandidateCycleResult: cycleResult,
            signoffRepairCandidateCycleHistorySummary: historySummary,
            actionDomainPath: try absolutePath(for: planning.actionDomainArtifact, projectRoot: projectRoot),
            repairFormulationPath: try absolutePath(for: planning.repairFormulationArtifact, projectRoot: projectRoot),
            planningProblemPath: try absolutePath(for: planning.planningProblemArtifact, projectRoot: projectRoot),
            candidatePlanPath: try absolutePath(for: generation.candidatePlanArtifact, projectRoot: projectRoot),
            planExecutionPath: try absolutePath(for: execution.planExecutionArtifact, projectRoot: projectRoot),
            planVerificationPath: try absolutePath(for: verification.planVerificationArtifact, projectRoot: projectRoot),
            rejectedPlansPath: try verification.rejectedPlansArtifact.map {
                try absolutePath(for: $0, projectRoot: projectRoot)
            },
            candidateCycleHistorySummaryPath: try absolutePath(for: historySummaryArtifact, projectRoot: projectRoot),
            candidateAccepted: verification.accepted,
            actionRecordIDs: [
                planning.actionRecord.actionID,
                execution.planID + "-execution",
                verification.planID + "-verification",
                cycleActionRecord.actionID,
            ],
            message: cycleActionRecord.actionID
        )
    }

    private func persistSignoffRepairCandidateCycleHistorySummary(
        _ summary: RunReviewSignoffRepairCandidateCycleHistorySummary,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        let store = XcircuitePackageStore()
        let runDirectory = try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
        let planningDirectory = runDirectory.appending(path: "planning")
        try store.ensureDirectory(at: planningDirectory)
        let summaryURL = planningDirectory.appending(path: "candidate-cycle-history-summary.json")
        try store.writeJSON(summary, to: summaryURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/runs/\(runID)/\(XcircuitePlanningArtifactStore.candidateCycleHistorySummaryRelativePath)"
        let reference = try store.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: XcircuitePlanningArtifactStore.candidateCycleHistorySummaryArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try store.upsertRunArtifact(reference, runID: runID, inProjectAt: projectRoot)
        return reference
    }

    private func appendSignoffRepairCandidateCycleActionRecord(
        actionID: String,
        runID: String,
        cycleIndex: Int,
        actorKind: XcircuiteRunActionActor.Kind,
        actorIdentifier: String,
        createdAt: Date,
        strategy: String,
        verificationMode: String,
        planning: RunReviewSignoffRepairPlanningResult,
        generation: XcircuiteCandidatePlanGenerationResult,
        execution: XcircuiteCandidatePlanExecutionResult,
        verification: XcircuiteCandidatePlanVerificationResult,
        selectedActionDomainIDs: [String],
        selectedObjectiveDomainIDs: [String],
        historySummaryArtifact: XcircuiteFileReference,
        projectRoot: URL
    ) throws -> XcircuiteRunActionRecord {
        let store = XcircuitePackageStore()
        let outputs = [
            generation.candidatePlanArtifact,
            generation.problemTranslationAuditArtifact,
            generation.actionDomainSnapshotArtifact,
            generation.symbolicPlannerTraceArtifact,
            execution.planExecutionArtifact,
            execution.designDiffArtifact,
            verification.planVerificationArtifact,
            verification.rejectedPlansArtifact,
            historySummaryArtifact,
        ].compactMap { $0 } + execution.producedArtifacts
        let record = XcircuiteRunActionRecord(
            actionID: actionID,
            runID: runID,
            actor: XcircuiteRunActionActor(kind: actorKind, identifier: actorIdentifier),
            actionKind: "review.runSignoffRepairCandidateCycle",
            status: verification.accepted ? .succeeded : .blocked,
            inputs: [
                planning.actionDomainArtifact,
                planning.repairFormulationArtifact,
                planning.planningProblemArtifact,
            ],
            outputs: outputs,
            metadata: [
                "candidateCycleIndex": .number(Double(cycleIndex)),
                "strategy": .string(strategy),
                "verificationMode": .string(verificationMode),
                "formulationID": .string(planning.formulationID),
                "problemID": .string(planning.problemID),
                "planID": .string(generation.planID),
                "generationStatus": .string(generation.status),
                "executionStatus": .string(execution.status),
                "verificationStatus": .string(verification.status),
                "accepted": .bool(verification.accepted),
                "rejectedPlansPath": .string(generation.symbolicPlannerTrace?.rejectedPlansPath ?? ""),
                "rejectedPlanFeedbackRecordCount": .number(
                    Double(generation.symbolicPlannerTrace?.rejectedPlanFeedbackRecordCount ?? 0)
                ),
                "globalRejectedPlanFeedbackCount": .number(
                    Double(generation.symbolicPlannerTrace?.globalRejectedPlanFeedbackCount ?? 0)
                ),
                "selectedActionIDs": .array(
                    (generation.symbolicPlannerTrace?.selectedActionIDs ?? []).map { .string($0) }
                ),
                "selectedActionDomainIDs": .array(
                    selectedActionDomainIDs.map { .string($0) }
                ),
                "selectedObjectiveDomainIDs": .array(
                    selectedObjectiveDomainIDs.map { .string($0) }
                ),
                "feedbackPenalizedActionIDs": .array(
                    feedbackPenalizedActionIDs(from: generation.symbolicPlannerTrace).map { .string($0) }
                ),
                "feedbackRankChanges": .array(
                    feedbackRankChanges(from: generation.symbolicPlannerTrace).map { .string($0) }
                ),
                "feedbackScoreDeltas": .array(
                    feedbackScoreDeltas(from: generation.symbolicPlannerTrace).map { .string($0) }
                ),
            ],
            createdAt: createdAt
        )
        try store.appendRunAction(record, inProjectAt: projectRoot)
        return record
    }

    private func nextSignoffRepairCandidateCycleIndex(
        runID: String,
        projectRoot: URL
    ) throws -> Int {
        let existingCount = try XcircuitePackageStore()
            .loadRunActions(runID: runID, inProjectAt: projectRoot)
            .filter { $0.actionKind == "review.runSignoffRepairCandidateCycle" }
            .count
        return existingCount + 1
    }

    private func feedbackPenalizedActionIDs(
        from trace: XcircuiteSymbolicPlannerTrace?
    ) -> [String] {
        let actionIDs = trace?.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.compactMap { actionTrace in
                actionTrace.scoreComponents.contains {
                    $0.termID.hasPrefix("feedback.") && $0.contribution < 0
                } ? actionTrace.actionID : nil
            }
        } ?? []
        return uniquePreservingOrder(actionIDs)
    }

    private func selectedActionDomainIDs(
        from trace: XcircuiteSymbolicPlannerTrace?
    ) -> [String] {
        let domainIDs = trace?.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.compactMap { actionTrace in
                actionTrace.selected ? actionTrace.domainID : nil
            }
        } ?? []
        return uniquePreservingOrder(domainIDs)
    }

    private func selectedObjectiveDomainIDs(
        from trace: XcircuiteSymbolicPlannerTrace?,
        problem: XcircuiteCircuitPlanningProblem
    ) -> [String] {
        var domainsByObjectiveID: [String: String] = [:]
        for objective in problem.objectives where domainsByObjectiveID[objective.objectiveID] == nil {
            domainsByObjectiveID[objective.objectiveID] = objective.domain
        }
        let objectiveIDs = trace?.objectiveTraces.compactMap { objectiveTrace in
            objectiveTrace.selectedActionID == nil ? nil : objectiveTrace.objectiveID
        } ?? []
        return uniquePreservingOrder(objectiveIDs.compactMap { domainsByObjectiveID[$0] })
    }

    private func planningProblem(
        from reference: XcircuiteFileReference,
        projectRoot: URL
    ) throws -> XcircuiteCircuitPlanningProblem {
        let url = try XcircuitePackageStore().url(
            forProjectRelativePath: reference.path,
            inProjectAt: projectRoot
        )
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(XcircuiteCircuitPlanningProblem.self, from: data)
        } catch {
            throw StudioError.projectLoadFailed("Failed to load planning problem for candidate cycle history: \(error.localizedDescription)")
        }
    }

    private func feedbackRankChanges(
        from trace: XcircuiteSymbolicPlannerTrace?
    ) -> [String] {
        let changes: [String] = trace?.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.compactMap { actionTrace in
                guard actionTrace.rejectedFeedbackRankDelta != 0 else {
                    return nil
                }
                return "\(actionTrace.actionID):\(actionTrace.rankBeforeRejectedFeedback)->\(actionTrace.rank)"
            }
        } ?? []
        return uniquePreservingOrder(changes)
    }

    private func feedbackScoreDeltas(
        from trace: XcircuiteSymbolicPlannerTrace?
    ) -> [String] {
        let deltas: [String] = trace?.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.compactMap { actionTrace in
                guard actionTrace.rejectedFeedbackScoreDelta != 0 else {
                    return nil
                }
                return "\(actionTrace.actionID):\(actionTrace.rejectedFeedbackScoreDelta)"
            }
        } ?? []
        return uniquePreservingOrder(deltas)
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
