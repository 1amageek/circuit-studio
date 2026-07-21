import DesignFlowKernel
import Foundation
import CircuiteFoundation
import Xcircuite

extension RunReviewService {
    public func formulateSignoffRepairPlanningProblem(
        runID: String,
        drcRepairHintPath explicitDRCRepairHintPath: String? = nil,
        lvsRepairHintPath explicitLVSRepairHintPath: String? = nil,
        formulationID: String? = nil,
        intentID: String? = nil,
        intent: String? = nil,
        problemID: String? = nil,
        actorKind: FlowRunActor.Kind = .human,
        actorIdentifier: String,
        note: String = "",
        projectRoot: URL
    ) async throws -> RunReviewSignoffRepairPlanningResult {
        let store = try workspaceStore(projectRoot: projectRoot)
        let loader = configuredReviewLedgerLoader(store: store)
        let bundle = try await configuredReviewBundler(store: store, loader: loader)
            .makeReviewBundle(
                runID: runID,
                workspaceID: try await workspaceID(store: store)
            )
        let drcRepairHintPath = explicitDRCRepairHintPath
            ?? repairHintArtifact(domain: .drc, in: bundle.artifacts)?.reference.locator.location.value
        let lvsRepairHintPath = explicitLVSRepairHintPath
            ?? repairHintArtifact(domain: .lvs, in: bundle.artifacts)?.reference.locator.location.value
        guard drcRepairHintPath != nil || lvsRepairHintPath != nil else {
            throw RunReviewServiceError.signoffRepairHintNotFound(runID: runID)
        }

        try validateRepairHintInputIntegrity(
            drcRepairHintPath: drcRepairHintPath,
            lvsRepairHintPath: lvsRepairHintPath,
            bundleArtifacts: bundle.artifacts
        )
        let inputArtifacts = try repairHintInputArtifacts(
            drcRepairHintPath: drcRepairHintPath,
            lvsRepairHintPath: lvsRepairHintPath,
            bundleArtifacts: bundle.artifacts
        )
        let compilation = try await XcircuiteSignoffRepairFormulationBuilder(
            workspaceStore: store,
            artifactStore: XcircuitePlanningArtifactStore(workspaceStore: store)
        ).compile(
            request: XcircuiteSignoffRepairFormulationRequest(
                runID: runID,
                drcRepairHintPath: drcRepairHintPath,
                lvsRepairHintPath: lvsRepairHintPath,
                formulationID: formulationID,
                intentID: intentID,
                intent: intent,
                problemID: problemID
            ),
            projectRoot: projectRoot
        )
        let actionDomainArtifact = compilation.actionDomainArtifact
        let outputArtifacts = [
            actionDomainArtifact,
            compilation.compilation.formulationArtifact,
            compilation.compilation.problemArtifact,
        ]
        let record = FlowRunActionRecord(
            actionID: "signoff-repair-planning-\(UUID().uuidString)",
            runID: runID,
            stageID: commonStageID(for: inputArtifacts, in: bundle.artifacts),
            actor: FlowRunActor(kind: actorKind, identifier: actorIdentifier),
            actionKind: "review.formulateSignoffRepairPlanningProblem",
            status: .succeeded,
            inputs: inputArtifacts,
            outputs: outputArtifacts,
            context: FlowRunActionContext(iterationID: compilation.formulationID)
        )
        try await store.appendRunAction(record)

        return RunReviewSignoffRepairPlanningResult(
            runID: runID,
            formulationID: compilation.formulationID,
            problemID: compilation.problemID,
            drcRepairHintPath: drcRepairHintPath,
            lvsRepairHintPath: lvsRepairHintPath,
            actionDomainArtifact: actionDomainArtifact,
            repairFormulationArtifact: outputArtifacts[1],
            planningProblemArtifact: outputArtifacts[2],
            sourceReports: compilation.sourceReports,
            actionRecord: record
        )
    }

    private enum SignoffRepairHintDomain {
        case drc
        case lvs
    }

    private func repairHintArtifact(
        domain: SignoffRepairHintDomain,
        in artifacts: [FlowRunReviewArtifact]
    ) -> FlowRunReviewArtifact? {
        artifacts
            .filter { artifact in
                artifact.reference.locator.format == .json && isRepairHintArtifact(artifact, domain: domain)
            }
            .sorted { left, right in
                if left.stageID != right.stageID {
                    return (left.stageID ?? "") < (right.stageID ?? "")
                }
                return left.reference.locator.location.value < right.reference.locator.location.value
            }
            .last
    }

    private func isRepairHintArtifact(
        _ artifact: FlowRunReviewArtifact,
        domain: SignoffRepairHintDomain
    ) -> Bool {
        let token: String
        let exactArtifactID: String
        let exactFileName: String
        switch domain {
        case .drc:
            token = "drc"
            exactArtifactID = "drc-repair-hints"
            exactFileName = "drc-repair-hints.json"
        case .lvs:
            token = "lvs"
            exactArtifactID = "lvs-repair-hints"
            exactFileName = "lvs-repair-hints.json"
        }
        if artifact.reference.id.rawValue == exactArtifactID {
            return true
        }
        let searchable = [
            artifact.reference.id.rawValue,
            artifact.purpose.rawValue,
            artifact.reference.locator.location.value,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        return searchable.contains(token)
            && (searchable.contains("repair-hints") || artifact.reference.locator.location.value.lowercased().hasSuffix(exactFileName))
    }

    private func validateRepairHintInputIntegrity(
        drcRepairHintPath: String?,
        lvsRepairHintPath: String?,
        bundleArtifacts: [FlowRunReviewArtifact]
    ) throws {
        if let drcRepairHintPath {
            try validateRepairHintArtifactIntegrity(
                path: drcRepairHintPath,
                bundleArtifacts: bundleArtifacts
            )
        }
        if let lvsRepairHintPath {
            try validateRepairHintArtifactIntegrity(
                path: lvsRepairHintPath,
                bundleArtifacts: bundleArtifacts
            )
        }
    }

    private func validateRepairHintArtifactIntegrity(
        path: String,
        bundleArtifacts: [FlowRunReviewArtifact]
    ) throws {
        let matches = bundleArtifacts.filter { $0.reference.locator.location.value == path }
        guard matches.count == 1, let artifact = matches.first else {
            throw RunReviewServiceError.signoffRepairHintIntegrityUnverified(
                path: path,
                status: matches.isEmpty ? "missing" : "ambiguous",
                message: matches.isEmpty
                    ? "The repair-hint artifact is not retained by the run ledger."
                    : "The run ledger retains multiple identities at the repair-hint path."
            )
        }
        guard let integrity = artifact.integrity else {
            throw RunReviewServiceError.signoffRepairHintIntegrityUnverified(
                path: path,
                status: "missing",
                message: "Artifact integrity was not recorded."
            )
        }
        guard integrity.status == .verified else {
            throw RunReviewServiceError.signoffRepairHintIntegrityUnverified(
                path: path,
                status: integrity.status.rawValue,
                message: integrity.message
            )
        }
    }

    private func repairHintInputArtifacts(
        drcRepairHintPath: String?,
        lvsRepairHintPath: String?,
        bundleArtifacts: [FlowRunReviewArtifact]
    ) throws -> [ArtifactReference] {
        var references: [ArtifactReference] = []
        if let drcRepairHintPath {
            references.append(try repairHintInputArtifact(
                path: drcRepairHintPath,
                bundleArtifacts: bundleArtifacts
            ))
        }
        if let lvsRepairHintPath {
            references.append(try repairHintInputArtifact(
                path: lvsRepairHintPath,
                bundleArtifacts: bundleArtifacts
            ))
        }
        return references
    }

    private func repairHintInputArtifact(
        path: String,
        bundleArtifacts: [FlowRunReviewArtifact]
    ) throws -> ArtifactReference {
        let matches = bundleArtifacts.filter {
            $0.reference.locator.location.value == path
        }
        guard matches.count == 1, let artifact = matches.first else {
            throw RunReviewServiceError.signoffRepairHintIntegrityUnverified(
                path: path,
                status: matches.isEmpty ? "missing" : "ambiguous",
                message: matches.isEmpty
                    ? "The repair-hint artifact is not retained by the run ledger."
                    : "The run ledger retains multiple identities at the repair-hint path."
            )
        }
        return artifact.reference
    }

    private func runIDForProducedArtifact(_ artifact: FlowRunReviewArtifact) -> String? {
        guard artifact.reference.locator.location.value.hasPrefix("\(XcircuiteWorkspaceLayout.directoryName)/runs/") else {
            return nil
        }
        let components = artifact.reference.locator.location.value.split(separator: "/").map(String.init)
        guard components.count > 2 else {
            return nil
        }
        return components[2]
    }

    private func commonStageID(
        for inputArtifacts: [ArtifactReference],
        in bundleArtifacts: [FlowRunReviewArtifact]
    ) -> String? {
        let inputReferences = Set(inputArtifacts)
        let stageIDs = Set(
            bundleArtifacts
                .filter { inputReferences.contains($0.reference) }
                .compactMap(\.stageID)
        )
        guard stageIDs.count == 1 else {
            return nil
        }
        return stageIDs.first
    }

}
