import DesignFlowKernel
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
        from actions: [FlowRunActionRecord]
    ) -> [String: [RunReviewWaiverEditApplication]] {
        var applications: [String: [RunReviewWaiverEditApplication]] = [:]
        for action in actions where action.actionKind == RunReviewWaiverEditApplication.actionKind {
            guard let context = action.context.reviewDecision,
                  context.kind == .waiver,
                  let proposalID = context.targetPath,
                  let before = action.inputs.last,
                  let after = action.outputs.first
            else {
                continue
            }
            applications[context.targetID, default: []].append(
                RunReviewWaiverEditApplication(
                    actionRecordID: action.actionID,
                    runID: action.runID,
                    actor: action.actor.identifier,
                    waiverReviewID: context.targetID,
                    proposalID: proposalID,
                    targetPath: after.path,
                    operation: context.decision,
                    beforeSHA256: before.sha256,
                    afterSHA256: after.sha256,
                    appliedAt: action.createdAt,
                    note: context.reason
                )
            )
        }
        return applications
    }

    func waiverEditVerificationsByReviewID(
        from actions: [FlowRunActionRecord],
        projectRoot: URL
    ) throws -> [String: [RunReviewWaiverEditVerification]] {
        var verifications: [String: [RunReviewWaiverEditVerification]] = [:]
        for action in actions where action.actionKind == RunReviewWaiverEditVerification.actionKind {
            guard let context = action.context.reviewDecision,
                  context.kind == .waiver,
                  let proposalID = context.targetPath,
                  let applicationActionID = action.context.iterationID,
                  let verificationArtifact = action.outputs.first(where: {
                      $0.artifactID == "post-waiver-edit-physical-verification"
                  })
            else {
                continue
            }
            let reportURL = projectRoot.appending(path: verificationArtifact.path)
            let report = try JSONDecoder().decode(
                DesignFlowVerificationReport.self,
                from: Data(contentsOf: reportURL)
            )
            let layoutTrustPath = action.outputs.first(where: {
                $0.artifactID == "post-waiver-edit-layout-trust"
            })?.path
            let rejectedPlansPath = action.outputs.first(where: {
                $0.artifactID == XcircuitePlanningArtifactStore.rejectedPlansArtifactID
            })?.path
            verifications[context.targetID, default: []].append(
                RunReviewWaiverEditVerification(
                    actionRecordID: action.actionID,
                    runID: action.runID,
                    actor: action.actor.identifier,
                    waiverReviewID: context.targetID,
                    proposalID: proposalID,
                    applicationActionID: applicationActionID,
                    verificationReportPath: verificationArtifact.path,
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
