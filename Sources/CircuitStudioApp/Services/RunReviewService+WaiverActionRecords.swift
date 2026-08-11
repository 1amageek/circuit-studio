import DesignFlowKernel
import CircuiteFoundation
import Foundation
import Xcircuite

extension RunReviewService {
    func waiverDecisionsByReviewID(
        from actions: [FlowRunActionRecord]
    ) -> [String: RunReviewWaiverDecision] {
        var decisions: [String: RunReviewWaiverDecision] = [:]
        for action in actions where action.actionKind == RunReviewWaiverDecision.actionKind {
            guard let context = action.context.reviewDecision,
                  context.kind == .waiver,
                  let decision = RunReviewWaiverDecisionValue(rawValue: context.decision)
            else {
                continue
            }
            decisions[context.targetID] = RunReviewWaiverDecision(
                actionRecordID: action.actionID,
                runID: action.runID,
                actor: action.actor.identifier,
                decision: decision,
                decidedAt: action.createdAt,
                note: context.reason
            )
        }
        return decisions
    }

    func waiverEditProposalSelectionsByReviewID(
        from actions: [FlowRunActionRecord]
    ) -> [String: [RunReviewWaiverEditProposalSelection]] {
        var selections: [String: [RunReviewWaiverEditProposalSelection]] = [:]
        for action in actions where action.actionKind == RunReviewWaiverEditProposalSelection.actionKind {
            guard let context = action.context.reviewDecision,
                  context.kind == .waiver,
                  context.decision == "selected",
                  let proposalID = context.targetPath
            else {
                continue
            }
            selections[context.targetID, default: []].append(
                RunReviewWaiverEditProposalSelection(
                    actionRecordID: action.actionID,
                    runID: action.runID,
                    actor: action.actor.identifier,
                    waiverReviewID: context.targetID,
                    proposalID: proposalID,
                    selectedAt: action.createdAt,
                    note: context.reason
                )
            )
        }
        return selections
    }

    func waiverEditApplicationsByReviewID(
        from actions: [FlowRunActionRecord],
        artifacts: [FlowRunReviewArtifact]
    ) throws -> [String: [RunReviewWaiverEditApplication]] {
        var applications: [String: [RunReviewWaiverEditApplication]] = [:]
        for action in actions where action.actionKind == RunReviewWaiverEditApplication.actionKind {
            guard let decision = action.context.reviewDecision,
                  decision.kind == .waiver,
                  let edit = action.context.artifactEdit,
                  edit.proposalID.isEmpty == false,
                  edit.targetPath.isEmpty == false,
                  edit.operation.isEmpty == false,
                  action.inputs.count == 1,
                  action.outputs.count == 2
            else {
                throw RunReviewServiceError.invalidArtifactReference(
                    path: action.outputs.first?.id.description
                        ?? action.inputs.last?.id.description
                        ?? action.actionID,
                    message: "Waiver edit action has an invalid typed artifact-edit contract."
                )
            }
            let before = action.outputs[0]
            let after = action.outputs[1]
            guard before.descriptor.role == .output,
                  after.descriptor.role == .output,
                  before.digest != after.digest,
                  try exactReviewBinding(for: before, in: artifacts).descriptor == before.descriptor,
                  try exactReviewBinding(for: after, in: artifacts).descriptor == after.descriptor,
                  decision.targetPath == edit.proposalID,
                  decision.decision == edit.operation else {
                throw RunReviewServiceError.invalidArtifactReference(
                    path: edit.targetPath,
                    message: "Waiver edit action references do not match its typed edit context."
                )
            }
            applications[decision.targetID, default: []].append(
                RunReviewWaiverEditApplication(
                    actionRecordID: action.actionID,
                    runID: action.runID,
                    actor: action.actor.identifier,
                    waiverReviewID: decision.targetID,
                    proposalID: edit.proposalID,
                    targetPath: edit.targetPath,
                    operation: edit.operation,
                    beforeSHA256: before.digest.hexadecimalValue,
                    afterSHA256: after.digest.hexadecimalValue,
                    appliedAt: action.createdAt,
                    note: decision.reason
                )
            )
        }
        return applications
    }

    func waiverEditVerificationsByReviewID(
        from actions: [FlowRunActionRecord],
        artifacts: [FlowRunReviewArtifact],
        artifactReader: any XcircuiteArtifactBindingReading
    ) async throws -> [String: [RunReviewWaiverEditVerification]] {
        var verifications: [String: [RunReviewWaiverEditVerification]] = [:]
        for action in actions where action.actionKind == RunReviewWaiverEditVerification.actionKind {
            let outputReferences = Set(action.outputs)
            let outputBindings = Array(Set(
                artifacts
                    .filter { outputReferences.contains($0.reference) }
                    .map(\.binding)
            ))
            guard outputReferences.allSatisfy({ reference in
                outputBindings.contains { $0.reference == reference }
            }) else {
                throw RunReviewServiceError.invalidArtifactReference(
                    path: action.outputs.first?.id.description ?? action.actionID,
                    message: "Waiver edit verification output availability is missing from the review bundle."
                )
            }
            guard let context = action.context.reviewDecision,
                  context.kind == .waiver,
                  let edit = action.context.artifactEdit,
                  context.targetPath == edit.proposalID,
                  let applicationActionID = action.context.iterationID,
                  let verificationArtifact = try uniqueBinding(in: outputBindings, where: {
                      $0.logicalID.hasPrefix("post-waiver-edit-physical-verification-")
                  })
            else {
                throw RunReviewServiceError.invalidArtifactReference(
                    path: action.outputs.first?.id.description ?? action.actionID,
                    message: "Waiver edit verification action has an invalid typed artifact-edit contract."
                )
            }
            guard let applicationAction = actions.first(where: {
                $0.actionID == applicationActionID
                    && $0.actionKind == RunReviewWaiverEditApplication.actionKind
            }),
            let appliedReference = applicationAction.outputs.last,
            action.inputs.contains(appliedReference),
            applicationAction.context.artifactEdit == edit else {
                throw RunReviewServiceError.invalidArtifactReference(
                    path: edit.targetPath,
                    message: "Waiver edit verification is not bound to its exact application output."
                )
            }
            let verificationPath = try verificationArtifact.requireLocalRelativePath().stringValue
            let report = try JSONDecoder().decode(
                DesignFlowVerificationReport.self,
                from: try await artifactReader.loadArtifactContent(for: verificationArtifact)
            )
            let layoutTrustPath = try uniqueBinding(in: outputBindings, where: {
                $0.logicalID.hasPrefix("post-waiver-edit-layout-trust-")
            }).map { try $0.requireLocalRelativePath().stringValue }
            let rejectedPlansPath = try uniqueBinding(in: outputBindings, where: {
                $0.logicalID == XcircuitePlanningArtifactStore.rejectedPlansArtifactID
            }).map { try $0.requireLocalRelativePath().stringValue }
            verifications[context.targetID, default: []].append(
                RunReviewWaiverEditVerification(
                    actionRecordID: action.actionID,
                    runID: action.runID,
                    actor: action.actor.identifier,
                    waiverReviewID: context.targetID,
                    proposalID: edit.proposalID,
                    applicationActionID: applicationActionID,
                    verificationReportPath: verificationPath,
                    layoutTrustReportPath: layoutTrustPath,
                    status: report.status,
                    readyForPEX: report.readyForPEX,
                    drcPassed: report.drc.passed,
                    drcViolationCount: report.drc.violationCount,
                    lvsPassed: report.lvs.passed,
                    planningFeedbackStatus: context.decision,
                    rejectedPlansPath: rejectedPlansPath,
                    reportSummary: waiverEditVerificationReportSummary(report),
                    verifiedAt: action.createdAt,
                    note: context.reason
                )
            )
        }
        return verifications
    }

    private func exactReviewBinding(
        for reference: ArtifactReference,
        in artifacts: [FlowRunReviewArtifact]
    ) throws -> FlowArtifactBinding {
        let bindings = Set(
            artifacts
                .filter { $0.reference == reference }
                .map(\.binding)
        )
        guard bindings.count == 1, let binding = bindings.first else {
            throw RunReviewServiceError.invalidArtifactReference(
                path: reference.id.description,
                message: bindings.isEmpty
                    ? "Action artifact availability is missing from the review bundle."
                    : "Action artifact identity resolves to multiple availability bindings."
            )
        }
        return binding
    }

    private func uniqueBinding(
        in bindings: [FlowArtifactBinding],
        where predicate: (FlowArtifactBinding) -> Bool
    ) throws -> FlowArtifactBinding? {
        let matches = bindings.filter(predicate)
        guard matches.count <= 1 else {
            throw RunReviewServiceError.invalidArtifactReference(
                path: matches.first?.reference.id.description ?? "unknown-artifact",
                message: "Action output role resolves to multiple availability bindings."
            )
        }
        return matches.first
    }

    func waiverEditVerificationReportSummary(
        _ report: DesignFlowVerificationReport
    ) -> RunReviewWaiverEditVerificationReportSummary {
        RunReviewWaiverEditVerificationReportSummary(
            status: report.status,
            readyForPEX: report.readyForPEX,
            drc: RunReviewWaiverEditVerificationDRCSummary(
                passed: report.drc.passed,
                violationCount: report.drc.violationCount,
                violationsByKind: report.drc.violationsByKind
                    .sorted { $0.key < $1.key }
                    .map { RunReviewWaiverVerificationBucket(label: $0.key, count: $0.value) }
            ),
            lvs: RunReviewWaiverEditVerificationLVSSummary(
                passed: report.lvs.passed,
                schematicHashMatches: report.lvs.schematicHashMatches,
                connectivityExtractionSkipped: report.lvs.connectivityExtractionSkipped,
                issueCounts: lvsIssueBuckets(report.lvs)
            ),
            layoutTrustPassed: report.layoutTrust?.passed,
            externalSignoffPassed: report.externalSignoff?.passed,
            externalSignoffReadyForPEX: report.externalSignoff?.readyForPEX
        )
    }

    func lvsIssueBuckets(
        _ summary: DesignFlowLVSVerificationSummary
    ) -> [RunReviewWaiverVerificationBucket] {
        var buckets: [RunReviewWaiverVerificationBucket] = []

        func append(_ label: String, _ count: Int) {
            if count > 0 {
                buckets.append(RunReviewWaiverVerificationBucket(label: label, count: count))
            }
        }

        append("missingLayoutInstances", summary.missingLayoutInstances.count)
        append("extraLayoutInstances", summary.extraLayoutInstances.count)
        append("missingLayoutNets", summary.missingLayoutNets.count)
        append("extraLayoutNets", summary.extraLayoutNets.count)
        append("danglingMappedInstanceIDs", summary.danglingMappedInstanceIDs.count)
        append("danglingMappedNetIDs", summary.danglingMappedNetIDs.count)
        append("physicalShorts", summary.physicalShorts.count)
        append("physicalOpens", summary.physicalOpens.count)
        append("unconnectedLayoutPins", summary.unconnectedLayoutPins.count)
        append("terminalMismatches", summary.terminalMismatches.count)
        append("missingExternalLayoutPorts", summary.missingExternalLayoutPorts.count)
        append("invalidLayoutTerminals", summary.invalidLayoutTerminals.count)
        append("duplicateLayoutTerminals", summary.duplicateLayoutTerminals.count)
        append("deviceParameterMismatches", summary.deviceParameterMismatches.count)
        append("duplicateLayoutDevices", summary.duplicateLayoutDevices.count)
        append("layoutTopologyErrors", summary.layoutTopologyErrors.count)
        append("skippedComponents", summary.skippedComponents.count)
        if summary.connectivityExtractionSkipped {
            append("connectivityExtractionSkipped", 1)
        }
        return buckets
    }
}
