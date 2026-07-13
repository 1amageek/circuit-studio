import DesignFlowKernel
import Foundation
import Xcircuite
import DesignFlowKernel

extension RunReviewService {
    func waiverDecisionsByReviewID(
        from actions: [XcircuiteRunActionRecord]
    ) -> [String: RunReviewWaiverDecision] {
        var decisions: [String: RunReviewWaiverDecision] = [:]
        for action in actions where action.actionKind == RunReviewWaiverDecision.actionKind {
            guard let reviewID = waiverStringMetadata("waiverReviewID", in: action),
                  let rawDecision = waiverStringMetadata("decision", in: action),
                  let decision = RunReviewWaiverDecisionValue(rawValue: rawDecision)
            else {
                continue
            }
            decisions[reviewID] = RunReviewWaiverDecision(
                actionRecordID: action.actionID,
                runID: action.runID,
                actor: action.actor.identifier,
                decision: decision,
                decidedAt: action.createdAt,
                note: waiverStringMetadata("note", in: action) ?? ""
            )
        }
        return decisions
    }

    func waiverEditProposalSelectionsByReviewID(
        from actions: [XcircuiteRunActionRecord]
    ) -> [String: [RunReviewWaiverEditProposalSelection]] {
        var selections: [String: [RunReviewWaiverEditProposalSelection]] = [:]
        for action in actions where action.actionKind == RunReviewWaiverEditProposalSelection.actionKind {
            guard let reviewID = waiverStringMetadata("waiverReviewID", in: action),
                  let proposalID = waiverStringMetadata("proposalID", in: action)
            else {
                continue
            }
            selections[reviewID, default: []].append(
                RunReviewWaiverEditProposalSelection(
                    actionRecordID: action.actionID,
                    runID: action.runID,
                    actor: action.actor.identifier,
                    waiverReviewID: reviewID,
                    proposalID: proposalID,
                    selectedAt: action.createdAt,
                    note: waiverStringMetadata("note", in: action) ?? ""
                )
            )
        }
        return selections
    }

    func waiverEditApplicationsByReviewID(
        from actions: [XcircuiteRunActionRecord]
    ) -> [String: [RunReviewWaiverEditApplication]] {
        var applications: [String: [RunReviewWaiverEditApplication]] = [:]
        for action in actions where action.actionKind == RunReviewWaiverEditApplication.actionKind {
            guard let reviewID = waiverStringMetadata("waiverReviewID", in: action),
                  let proposalID = waiverStringMetadata("proposalID", in: action),
                  let targetPath = waiverStringMetadata("targetPath", in: action),
                  let operation = waiverStringMetadata("operation", in: action),
                  let beforeSHA256 = waiverStringMetadata("beforeSHA256", in: action),
                  let afterSHA256 = waiverStringMetadata("afterSHA256", in: action)
            else {
                continue
            }
            applications[reviewID, default: []].append(
                RunReviewWaiverEditApplication(
                    actionRecordID: action.actionID,
                    runID: action.runID,
                    actor: action.actor.identifier,
                    waiverReviewID: reviewID,
                    proposalID: proposalID,
                    targetPath: targetPath,
                    operation: operation,
                    beforeSHA256: beforeSHA256,
                    afterSHA256: afterSHA256,
                    appliedAt: action.createdAt,
                    note: waiverStringMetadata("note", in: action) ?? ""
                )
            )
        }
        return applications
    }

    func waiverEditVerificationsByReviewID(
        from actions: [XcircuiteRunActionRecord]
    ) -> [String: [RunReviewWaiverEditVerification]] {
        var verifications: [String: [RunReviewWaiverEditVerification]] = [:]
        for action in actions where action.actionKind == RunReviewWaiverEditVerification.actionKind {
            guard let reviewID = waiverStringMetadata("waiverReviewID", in: action),
                  let proposalID = waiverStringMetadata("proposalID", in: action),
                  let applicationActionID = waiverStringMetadata("applicationActionID", in: action),
                  let verificationReportPath = waiverStringMetadata("verificationReportPath", in: action),
                  let status = waiverStringMetadata("verificationStatus", in: action),
                  let readyForPEX = waiverBoolMetadata("readyForPEX", in: action),
                  let drcPassed = waiverBoolMetadata("drcPassed", in: action),
                  let drcViolationCount = waiverIntMetadata("drcViolationCount", in: action),
                  let lvsPassed = waiverBoolMetadata("lvsPassed", in: action)
            else {
                continue
            }
            verifications[reviewID, default: []].append(
                RunReviewWaiverEditVerification(
                    actionRecordID: action.actionID,
                    runID: action.runID,
                    actor: action.actor.identifier,
                    waiverReviewID: reviewID,
                    proposalID: proposalID,
                    applicationActionID: applicationActionID,
                    verificationReportPath: verificationReportPath,
                    layoutTrustReportPath: waiverStringMetadata("layoutTrustReportPath", in: action),
                    status: status,
                    readyForPEX: readyForPEX,
                    drcPassed: drcPassed,
                    drcViolationCount: drcViolationCount,
                    lvsPassed: lvsPassed,
                    planningFeedbackStatus: waiverStringMetadata("planningFeedbackStatus", in: action) ?? "not-recorded",
                    rejectedPlansPath: waiverStringMetadata("rejectedPlansPath", in: action),
                    reportSummary: waiverEditVerificationReportSummary(
                        in: action,
                        status: status,
                        readyForPEX: readyForPEX,
                        drcPassed: drcPassed,
                        drcViolationCount: drcViolationCount,
                        lvsPassed: lvsPassed
                    ),
                    verifiedAt: action.createdAt,
                    note: waiverStringMetadata("note", in: action) ?? ""
                )
            )
        }
        return verifications
    }

    func waiverStringMetadata(_ key: String, in action: XcircuiteRunActionRecord) -> String? {
        guard case .string(let value) = action.metadata[key] else {
            return nil
        }
        return value
    }

    func waiverBoolMetadata(_ key: String, in action: XcircuiteRunActionRecord) -> Bool? {
        guard case .bool(let value) = action.metadata[key] else {
            return nil
        }
        return value
    }

    func waiverIntMetadata(_ key: String, in action: XcircuiteRunActionRecord) -> Int? {
        guard case .number(let value) = action.metadata[key] else {
            return nil
        }
        return Int(value)
    }

    func waiverEditVerificationSummaryMetadataValue(
        _ report: DesignFlowVerificationReport
    ) -> XcircuiteJSONValue {
        var summary: [String: XcircuiteJSONValue] = [
            "status": .string(report.status),
            "readyForPEX": .bool(report.readyForPEX),
            "drc": .object([
                "passed": .bool(report.drc.passed),
                "violationCount": .number(Double(report.drc.violationCount)),
                "violationsByKind": .array(
                    report.drc.violationsByKind
                        .sorted { $0.key < $1.key }
                        .map { waiverVerificationBucketMetadataValue(label: $0.key, count: $0.value) }
                ),
            ]),
            "lvs": .object([
                "passed": .bool(report.lvs.passed),
                "schematicHashMatches": .bool(report.lvs.schematicHashMatches),
                "connectivityExtractionSkipped": .bool(report.lvs.connectivityExtractionSkipped),
                "issueCounts": .array(
                    lvsIssueBuckets(report.lvs).map {
                        waiverVerificationBucketMetadataValue(label: $0.label, count: $0.count)
                    }
                ),
            ]),
        ]
        if let layoutTrust = report.layoutTrust {
            summary["layoutTrustPassed"] = .bool(layoutTrust.passed)
        }
        if let externalSignoff = report.externalSignoff {
            summary["externalSignoffPassed"] = .bool(externalSignoff.passed)
            summary["externalSignoffReadyForPEX"] = .bool(externalSignoff.readyForPEX)
        }
        return .object(summary)
    }

    func waiverVerificationBucketMetadataValue(
        label: String,
        count: Int
    ) -> XcircuiteJSONValue {
        .object([
            "label": .string(label),
            "count": .number(Double(count)),
        ])
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

    func waiverEditVerificationReportSummary(
        in action: XcircuiteRunActionRecord,
        status: String,
        readyForPEX: Bool,
        drcPassed: Bool,
        drcViolationCount: Int,
        lvsPassed: Bool
    ) -> RunReviewWaiverEditVerificationReportSummary {
        guard case .object(let summaryObject) = action.metadata["verificationSummary"],
              let summaryStatus = waiverStringValue("status", in: summaryObject),
              let summaryReadyForPEX = waiverBoolValue("readyForPEX", in: summaryObject),
              let drc = drcSummaryValue(in: summaryObject),
              let lvs = lvsSummaryValue(in: summaryObject)
        else {
            return RunReviewWaiverEditVerificationReportSummary(
                status: status,
                readyForPEX: readyForPEX,
                drc: RunReviewWaiverEditVerificationDRCSummary(
                    passed: drcPassed,
                    violationCount: drcViolationCount
                ),
                lvs: RunReviewWaiverEditVerificationLVSSummary(
                    passed: lvsPassed,
                    schematicHashMatches: lvsPassed,
                    connectivityExtractionSkipped: false
                )
            )
        }

        return RunReviewWaiverEditVerificationReportSummary(
            status: summaryStatus,
            readyForPEX: summaryReadyForPEX,
            drc: drc,
            lvs: lvs,
            layoutTrustPassed: waiverBoolValue("layoutTrustPassed", in: summaryObject),
            externalSignoffPassed: waiverBoolValue("externalSignoffPassed", in: summaryObject),
            externalSignoffReadyForPEX: waiverBoolValue("externalSignoffReadyForPEX", in: summaryObject)
        )
    }

    func drcSummaryValue(
        in object: [String: XcircuiteJSONValue]
    ) -> RunReviewWaiverEditVerificationDRCSummary? {
        guard case .object(let drcObject) = object["drc"],
              let passed = waiverBoolValue("passed", in: drcObject),
              let violationCount = waiverIntValue("violationCount", in: drcObject)
        else {
            return nil
        }
        return RunReviewWaiverEditVerificationDRCSummary(
            passed: passed,
            violationCount: violationCount,
            violationsByKind: waiverBucketArrayValue("violationsByKind", in: drcObject)
        )
    }

    func lvsSummaryValue(
        in object: [String: XcircuiteJSONValue]
    ) -> RunReviewWaiverEditVerificationLVSSummary? {
        guard case .object(let lvsObject) = object["lvs"],
              let passed = waiverBoolValue("passed", in: lvsObject),
              let schematicHashMatches = waiverBoolValue("schematicHashMatches", in: lvsObject),
              let connectivityExtractionSkipped = waiverBoolValue("connectivityExtractionSkipped", in: lvsObject)
        else {
            return nil
        }
        return RunReviewWaiverEditVerificationLVSSummary(
            passed: passed,
            schematicHashMatches: schematicHashMatches,
            connectivityExtractionSkipped: connectivityExtractionSkipped,
            issueCounts: waiverBucketArrayValue("issueCounts", in: lvsObject)
        )
    }

    func waiverBucketArrayValue(
        _ key: String,
        in object: [String: XcircuiteJSONValue]
    ) -> [RunReviewWaiverVerificationBucket] {
        guard case .array(let values) = object[key] else {
            return []
        }
        return values.compactMap { value in
            guard case .object(let bucketObject) = value,
                  let label = waiverStringValue("label", in: bucketObject),
                  let count = waiverIntValue("count", in: bucketObject)
            else {
                return nil
            }
            return RunReviewWaiverVerificationBucket(label: label, count: count)
        }
    }

    func waiverStringValue(
        _ key: String,
        in object: [String: XcircuiteJSONValue]
    ) -> String? {
        guard case .string(let value) = object[key] else {
            return nil
        }
        return value
    }

    func waiverBoolValue(
        _ key: String,
        in object: [String: XcircuiteJSONValue]
    ) -> Bool? {
        guard case .bool(let value) = object[key] else {
            return nil
        }
        return value
    }

    func waiverIntValue(
        _ key: String,
        in object: [String: XcircuiteJSONValue]
    ) -> Int? {
        guard case .number(let value) = object[key] else {
            return nil
        }
        return Int(value)
    }
}
