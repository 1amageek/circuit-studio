import Foundation
import CircuiteFoundation
import CircuitStudioCore
import DRCEngine
import LVSEngine
import Xcircuite
import DesignFlowKernel

extension DesignFlowService {
    func formulateSignoffRepairPlanningProblem(
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
        let result = try await RunReviewService().formulateSignoffRepairPlanningProblem(
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
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
        let strategy = command.candidateStrategy ?? "first-ready-action-per-objective"
        let verificationMode = command.candidateVerificationMode ?? "post-execution"
        let planning = if hasExplicitSignoffRepairPlanningInput(command) {
            try await RunReviewService().formulateSignoffRepairPlanningProblem(
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
        } else if let retained = try await retainedSignoffRepairPlanningResult(
            runID: runID,
            workspaceStore: workspaceStore
        ) {
            retained
        } else {
            try await RunReviewService().formulateSignoffRepairPlanningProblem(
                runID: runID,
                actorKind: command.actionActorKind ?? .human,
                actorIdentifier: reviewer,
                note: command.approvalNote ?? "",
                projectRoot: projectRoot
            )
        }
        let rejectedPlansReference = try await latestRejectedPlansReference(
            runID: runID,
            workspaceStore: workspaceStore
        )
        let generation = try await XcircuiteCandidatePlanGenerator(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        ).generateCandidatePlan(
            request: XcircuiteCandidatePlanGenerationRequest(
                runID: runID,
                problemPath: planning.planningProblemArtifact.path,
                rejectedPlansPath: rejectedPlansReference?.path,
                strategy: strategy,
                calibrationPolicy: "disabled"
            ),
            projectRoot: projectRoot
        )
        let execution = try await XcircuiteCandidatePlanExecutor(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        ).executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(
                runID: runID,
                candidatePlanPath: generation.candidatePlanArtifact.path,
                actor: reviewer
            ),
            projectRoot: projectRoot
        )
        let verification = try await XcircuiteCandidatePlanVerifier(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        ).verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: runID,
                candidatePlanPath: generation.candidatePlanArtifact.path,
                verificationMode: verificationMode
            ),
            projectRoot: projectRoot
        )
        let cycleIndex = try await nextSignoffRepairCandidateCycleIndex(
            runID: runID,
            workspaceStore: workspaceStore
        )
        let cycleActionID = "signoff-repair-candidate-cycle-\(UUID().uuidString)"
        let cycleCreatedAt = Date()
        let priorCycles = try await RunReviewService()
            .loadRun(runID: runID, projectRoot: projectRoot)
            .signoff
            .repairCandidateCycles
        let selectedActionDomainIDs = selectedActionDomainIDs(from: generation.symbolicPlannerTrace)
        let planningProblem = try await planningProblem(
            from: planning.planningProblemArtifact,
            workspaceStore: workspaceStore
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
        let historySummaryArtifact = try prepareSignoffRepairCandidateCycleHistorySummary(
            historySummary,
            cycleIndex: cycleIndex,
            runID: runID
        )
        let cycleArtifact = try prepareSignoffRepairCandidateCycle(
            currentCycle,
            runID: runID
        )
        let cycleActionRecord = try await appendSignoffRepairCandidateCycleActionRecord(
            actionID: cycleActionID,
            runID: runID,
            cycleIndex: cycleIndex,
            actorKind: command.actionActorKind ?? .human,
            actorIdentifier: reviewer,
            createdAt: cycleCreatedAt,
            planning: planning,
            generation: generation,
            execution: execution,
            verification: verification,
            historySummaryArtifact: historySummaryArtifact,
            cycleArtifact: cycleArtifact,
            workspaceStore: workspaceStore
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
            candidateCycleHistorySummaryPath: try absolutePath(
                for: historySummaryArtifact.reference,
                projectRoot: projectRoot
            ),
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

    private func hasExplicitSignoffRepairPlanningInput(_ command: DesignFlowCommand) -> Bool {
        command.drcRepairHintPath != nil
            || command.lvsRepairHintPath != nil
            || command.planningFormulationID != nil
            || command.planningIntentID != nil
            || command.planningIntent != nil
            || command.planningProblemID != nil
    }

    private func retainedSignoffRepairPlanningResult(
        runID: String,
        workspaceStore: XcircuiteWorkspaceStore
    ) async throws -> RunReviewSignoffRepairPlanningResult? {
        let actions = try await workspaceStore.loadRunActions(runID: runID)
        guard let action = actions.last(where: {
            $0.actionKind == "review.formulateSignoffRepairPlanningProblem" && $0.status == .succeeded
        }) else {
            return nil
        }
        guard let actionDomainArtifact = action.outputs.first(where: {
            $0.artifactID == XcircuitePlanningArtifactStore.actionDomainArtifactID
        }), let formulationArtifact = action.outputs.first(where: {
            $0.artifactID == XcircuitePlanningArtifactStore.repairPlanFormulationArtifactID
        }), let problemArtifact = action.outputs.first(where: {
            $0.artifactID == XcircuitePlanningArtifactStore.problemArtifactID
        }) else {
            throw StudioError.projectLoadFailed(
                "Retained signoff repair planning action is missing required output artifacts."
            )
        }
        for reference in [actionDomainArtifact, formulationArtifact, problemArtifact] + action.inputs {
            _ = try await workspaceStore.verify(reference)
        }
        let formulation = try await workspaceStore.readJSON(
            XcircuiteRepairPlanFormulation.self,
            from: formulationArtifact.path
        )
        let problem = try await workspaceStore.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: problemArtifact.path
        )
        guard formulation.runID == runID, problem.runID == runID else {
            throw StudioError.projectLoadFailed(
                "Retained signoff repair planning artifacts do not match their run or problem identity."
            )
        }
        let sourceReports = try await retainedSignoffRepairSourceReports(
            action.inputs,
            workspaceStore: workspaceStore
        )
        return RunReviewSignoffRepairPlanningResult(
            runID: runID,
            formulationID: formulation.formulationID,
            problemID: problem.problemID,
            drcRepairHintPath: action.inputs.first(where: { $0.artifactID == "drc-repair-hints" })?.path,
            lvsRepairHintPath: action.inputs.first(where: { $0.artifactID == "lvs-repair-hints" })?.path,
            actionDomainArtifact: actionDomainArtifact,
            repairFormulationArtifact: formulationArtifact,
            planningProblemArtifact: problemArtifact,
            sourceReports: sourceReports,
            actionRecord: action
        )
    }

    private func retainedSignoffRepairSourceReports(
        _ references: [ArtifactReference],
        workspaceStore: XcircuiteWorkspaceStore
    ) async throws -> [XcircuiteSignoffRepairFormulationResult.SourceReport] {
        var reports: [XcircuiteSignoffRepairFormulationResult.SourceReport] = []
        for reference in references {
            switch reference.artifactID {
            case "drc-repair-hints":
                let report = try await workspaceStore.readJSON(DRCRepairHintReport.self, from: reference.path)
                reports.append(signoffRepairSourceReport(kind: "drc", report: report, reference: reference))
            case "lvs-repair-hints":
                let report = try await workspaceStore.readJSON(LVSRepairHintReport.self, from: reference.path)
                reports.append(signoffRepairSourceReport(kind: "lvs", report: report, reference: reference))
            default:
                continue
            }
        }
        return reports.sorted { $0.sourceKind < $1.sourceKind }
    }

    private func signoffRepairSourceReport(
        kind: String,
        report: DRCRepairHintReport,
        reference: ArtifactReference
    ) -> XcircuiteSignoffRepairFormulationResult.SourceReport {
        XcircuiteSignoffRepairFormulationResult.SourceReport(
            sourceKind: kind,
            path: reference.path,
            backendID: report.backendID,
            topCell: report.topCell,
            status: report.status,
            activeDiagnosticCount: report.activeDiagnosticCount,
            hintCount: report.hintCount,
            unsupportedDiagnosticCount: report.unsupportedDiagnosticIndexes.count,
            artifactID: reference.artifactID,
            sha256: reference.digest.hexadecimalValue,
            byteCount: Int64(exactly: reference.byteCount),
            integrityStatus: "verified"
        )
    }

    private func signoffRepairSourceReport(
        kind: String,
        report: LVSRepairHintReport,
        reference: ArtifactReference
    ) -> XcircuiteSignoffRepairFormulationResult.SourceReport {
        XcircuiteSignoffRepairFormulationResult.SourceReport(
            sourceKind: kind,
            path: reference.path,
            backendID: report.backendID,
            topCell: report.topCell,
            status: report.status,
            activeDiagnosticCount: report.activeDiagnosticCount,
            hintCount: report.hintCount,
            unsupportedDiagnosticCount: report.unsupportedDiagnosticIndexes.count,
            artifactID: reference.artifactID,
            sha256: reference.digest.hexadecimalValue,
            byteCount: Int64(exactly: reference.byteCount),
            integrityStatus: "verified"
        )
    }

    private func prepareSignoffRepairCandidateCycle(
        _ cycle: RunReviewSignoffRepairCandidateCycleHistoryItem,
        runID: String
    ) throws -> XcircuitePreparedArtifact {
        let filename = "candidate-cycle-\(cycle.cycleIndex).json"
        let planningPath = "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/planning"
        let projectRelativePath = "\(planningPath)/\(filename)"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let content = try encoder.encode(cycle)
        return XcircuitePreparedArtifact(
            reference: ArtifactReference(
                id: try ArtifactID(rawValue: "signoff-repair-candidate-cycle-\(cycle.cycleIndex)"),
                locator: ArtifactLocator(
                    location: try ArtifactLocation(workspaceRelativePath: projectRelativePath),
                    role: .output,
                    kind: .report,
                    format: .json
                ),
                digest: try SHA256ContentDigester().digest(data: content, using: .sha256),
                byteCount: UInt64(content.count)
            ),
            content: content
        )
    }

    private func prepareSignoffRepairCandidateCycleHistorySummary(
        _ summary: RunReviewSignoffRepairCandidateCycleHistorySummary,
        cycleIndex: Int,
        runID: String
    ) throws -> XcircuitePreparedArtifact {
        let planningPath = "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/planning"
        let projectRelativePath = "\(planningPath)/candidate-cycle-history/history-\(cycleIndex).json"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let content = try encoder.encode(summary)
        return XcircuitePreparedArtifact(
            reference: ArtifactReference(
                id: try ArtifactID(
                    rawValue: "\(XcircuitePlanningArtifactStore.candidateCycleHistorySummaryArtifactID)-\(cycleIndex)"
                ),
                locator: ArtifactLocator(
                    location: try ArtifactLocation(workspaceRelativePath: projectRelativePath),
                    role: .output,
                    kind: .other,
                    format: .json
                ),
                digest: try SHA256ContentDigester().digest(data: content, using: .sha256),
                byteCount: UInt64(content.count)
            ),
            content: content
        )
    }

    private func appendSignoffRepairCandidateCycleActionRecord(
        actionID: String,
        runID: String,
        cycleIndex: Int,
        actorKind: FlowRunActor.Kind,
        actorIdentifier: String,
        createdAt: Date,
        planning: RunReviewSignoffRepairPlanningResult,
        generation: XcircuiteCandidatePlanGenerationResult,
        execution: XcircuiteCandidatePlanExecutionResult,
        verification: XcircuiteCandidatePlanVerificationResult,
        historySummaryArtifact: XcircuitePreparedArtifact,
        cycleArtifact: XcircuitePreparedArtifact,
        workspaceStore: XcircuiteWorkspaceStore
    ) async throws -> FlowRunActionRecord {
        let foundationOutputs: [ArtifactReference] = [
            generation.candidatePlanArtifact,
            generation.problemTranslationAuditArtifact,
            generation.actionDomainSnapshotArtifact,
            generation.symbolicPlannerTraceArtifact,
            execution.planExecutionArtifact,
            execution.designDiffArtifact,
            verification.planVerificationArtifact,
        ].compactMap { $0 } + execution.producedArtifacts
        let outputs = foundationOutputs + [
            historySummaryArtifact.reference,
            cycleArtifact.reference,
        ]
        let record = FlowRunActionRecord(
            actionID: actionID,
            runID: runID,
            actor: FlowRunActor(kind: actorKind, identifier: actorIdentifier),
            actionKind: "review.runSignoffRepairCandidateCycle",
            status: verification.accepted ? .succeeded : .blocked,
            inputs: [
                planning.actionDomainArtifact,
                planning.repairFormulationArtifact,
                planning.planningProblemArtifact,
            ],
            outputs: outputs,
            context: FlowRunActionContext(iterationID: String(cycleIndex)),
            createdAt: createdAt
        )
        _ = try await workspaceStore.appendActionArtifacts(
            [historySummaryArtifact, cycleArtifact],
            action: record
        )
        return record
    }

    private func nextSignoffRepairCandidateCycleIndex(
        runID: String,
        workspaceStore: XcircuiteWorkspaceStore
    ) async throws -> Int {
        let existingCount = try await workspaceStore
            .loadRunActions(runID: runID)
            .filter { $0.actionKind == "review.runSignoffRepairCandidateCycle" }
            .count
        return existingCount + 1
    }

    private func latestRejectedPlansReference(
        runID: String,
        workspaceStore: XcircuiteWorkspaceStore
    ) async throws -> ArtifactReference? {
        let ledger = try await workspaceStore.loadRunLedger(runID: runID)
        guard let reference = ledger.actions.reversed()
            .lazy
            .flatMap(\.outputs)
            .first(where: {
                $0.artifactID == XcircuitePlanningArtifactStore.rejectedPlansArtifactID
            }) else {
            return nil
        }
        _ = try await workspaceStore.verify(reference)
        return reference
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
        from reference: ArtifactReference,
        workspaceStore: XcircuiteWorkspaceStore
    ) async throws -> XcircuiteCircuitPlanningProblem {
        do {
            _ = try await workspaceStore.verify(reference)
            return try await workspaceStore.readJSON(
                XcircuiteCircuitPlanningProblem.self,
                from: reference.path
            )
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
