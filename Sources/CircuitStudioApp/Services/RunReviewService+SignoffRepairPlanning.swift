import DesignFlowKernel
import Foundation
import Xcircuite
import DesignFlowKernel

extension RunReviewService {
    public func formulateSignoffRepairPlanningProblem(
        runID: String,
        drcRepairHintPath explicitDRCRepairHintPath: String? = nil,
        lvsRepairHintPath explicitLVSRepairHintPath: String? = nil,
        formulationID: String? = nil,
        intentID: String? = nil,
        intent: String? = nil,
        problemID: String? = nil,
        actorKind: XcircuiteRunActionActor.Kind = .human,
        actorIdentifier: String,
        note: String = "",
        projectRoot: URL
    ) throws -> RunReviewSignoffRepairPlanningResult {
        let bundle = try reviewBundler.makeReviewBundle(runID: runID, projectRoot: projectRoot)
        let drcRepairHintPath = explicitDRCRepairHintPath
            ?? repairHintArtifact(domain: .drc, in: bundle.artifacts)?.path
        let lvsRepairHintPath = explicitLVSRepairHintPath
            ?? repairHintArtifact(domain: .lvs, in: bundle.artifacts)?.path
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
            bundleArtifacts: bundle.artifacts,
            projectRoot: projectRoot
        )
        let compilation = try XcircuiteSignoffRepairFormulationBuilder(
            packageStore: store,
            artifactStore: XcircuitePlanningArtifactStore(packageStore: store)
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
        let actionDomainArtifact = try actionDomainArtifact(runID: runID, projectRoot: projectRoot)
        let outputArtifacts = [
            actionDomainArtifact,
            compilation.compilation.formulationArtifact,
            compilation.compilation.problemArtifact,
        ]
        let record = XcircuiteRunActionRecord(
            actionID: "signoff-repair-planning-\(UUID().uuidString)",
            runID: runID,
            stageID: commonStageID(for: inputArtifacts, in: bundle.artifacts),
            actor: XcircuiteRunActionActor(kind: actorKind, identifier: actorIdentifier),
            actionKind: "review.formulateSignoffRepairPlanningProblem",
            status: .succeeded,
            inputs: inputArtifacts,
            outputs: outputArtifacts,
            metadata: signoffRepairPlanningMetadata(
                drcRepairHintPath: drcRepairHintPath,
                lvsRepairHintPath: lvsRepairHintPath,
                actionDomainArtifact: actionDomainArtifact,
                compilation: compilation,
                note: note
            )
        )
        try store.appendRunAction(record, inProjectAt: projectRoot)

        return RunReviewSignoffRepairPlanningResult(
            runID: runID,
            formulationID: compilation.formulationID,
            problemID: compilation.problemID,
            drcRepairHintPath: drcRepairHintPath,
            lvsRepairHintPath: lvsRepairHintPath,
            actionDomainArtifact: actionDomainArtifact,
            repairFormulationArtifact: compilation.compilation.formulationArtifact,
            planningProblemArtifact: compilation.compilation.problemArtifact,
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
                artifact.format == .json && isRepairHintArtifact(artifact, domain: domain)
            }
            .sorted { left, right in
                if left.stageID != right.stageID {
                    return (left.stageID ?? "") < (right.stageID ?? "")
                }
                return left.path < right.path
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
        if artifact.artifactID == exactArtifactID {
            return true
        }
        let searchable = [
            artifact.artifactID,
            artifact.role,
            artifact.path,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        return searchable.contains(token)
            && (searchable.contains("repair-hints") || artifact.path.lowercased().hasSuffix(exactFileName))
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
        guard let artifact = bundleArtifacts.first(where: { $0.path == path }) else {
            return
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
        bundleArtifacts: [FlowRunReviewArtifact],
        projectRoot: URL
    ) throws -> [XcircuiteFileReference] {
        var references: [XcircuiteFileReference] = []
        if let drcRepairHintPath {
            references.append(try repairHintInputArtifact(
                path: drcRepairHintPath,
                artifactID: "drc-repair-hints",
                bundleArtifacts: bundleArtifacts,
                projectRoot: projectRoot
            ))
        }
        if let lvsRepairHintPath {
            references.append(try repairHintInputArtifact(
                path: lvsRepairHintPath,
                artifactID: "lvs-repair-hints",
                bundleArtifacts: bundleArtifacts,
                projectRoot: projectRoot
            ))
        }
        return references
    }

    private func repairHintInputArtifact(
        path: String,
        artifactID: String,
        bundleArtifacts: [FlowRunReviewArtifact],
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        if let artifact = bundleArtifacts.first(where: { $0.path == path }) {
            return XcircuiteFileReference(
                artifactID: artifact.artifactID ?? artifactID,
                path: artifact.path,
                kind: artifact.kind,
                format: artifact.format,
                sha256: artifact.sha256,
                byteCount: artifact.byteCount,
                producedByRunID: runIDForProducedArtifact(artifact)
            )
        }
        return try store.fileReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: .report,
            format: .json,
            inProjectAt: projectRoot
        )
    }

    private func runIDForProducedArtifact(_ artifact: FlowRunReviewArtifact) -> String? {
        guard artifact.path.hasPrefix("\(XcircuitePackage.directoryName)/runs/") else {
            return nil
        }
        let components = artifact.path.split(separator: "/").map(String.init)
        guard components.count > 2 else {
            return nil
        }
        return components[2]
    }

    private func actionDomainArtifact(
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
        try store.fileReference(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/runs/\(runID)/\(XcircuitePlanningArtifactStore.actionDomainRelativePath)",
            artifactID: XcircuitePlanningArtifactStore.actionDomainArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
    }

    private func commonStageID(
        for inputArtifacts: [XcircuiteFileReference],
        in bundleArtifacts: [FlowRunReviewArtifact]
    ) -> String? {
        let inputPaths = Set(inputArtifacts.map(\.path))
        let stageIDs = Set(
            bundleArtifacts
                .filter { inputPaths.contains($0.path) }
                .compactMap(\.stageID)
        )
        guard stageIDs.count == 1 else {
            return nil
        }
        return stageIDs.first
    }

    private func signoffRepairPlanningMetadata(
        drcRepairHintPath: String?,
        lvsRepairHintPath: String?,
        actionDomainArtifact: XcircuiteFileReference,
        compilation: XcircuiteSignoffRepairFormulationResult,
        note: String
    ) -> [String: XcircuiteJSONValue] {
        var metadata: [String: XcircuiteJSONValue] = [
            "formulationID": .string(compilation.formulationID),
            "problemID": .string(compilation.problemID),
            "repairFormulationPath": .string(compilation.compilation.formulationArtifact.path),
            "planningProblemPath": .string(compilation.compilation.problemArtifact.path),
            "actionDomainPath": .string(actionDomainArtifact.path),
            "sourceReportCount": .number(Double(compilation.sourceReports.count)),
            "sourceReports": .array(compilation.sourceReports.map(sourceReportMetadataValue)),
            "note": .string(note),
        ]
        if let drcRepairHintPath {
            metadata["drcRepairHintPath"] = .string(drcRepairHintPath)
        }
        if let lvsRepairHintPath {
            metadata["lvsRepairHintPath"] = .string(lvsRepairHintPath)
        }
        return metadata
    }

    private func sourceReportMetadataValue(
        _ sourceReport: XcircuiteSignoffRepairFormulationResult.SourceReport
    ) -> XcircuiteJSONValue {
        .object([
            "sourceKind": .string(sourceReport.sourceKind),
            "path": .string(sourceReport.path),
            "backendID": .string(sourceReport.backendID),
            "topCell": .string(sourceReport.topCell),
            "status": .string(sourceReport.status),
            "activeDiagnosticCount": .number(Double(sourceReport.activeDiagnosticCount)),
            "hintCount": .number(Double(sourceReport.hintCount)),
            "unsupportedDiagnosticCount": .number(Double(sourceReport.unsupportedDiagnosticCount)),
        ])
    }
}
