import Foundation
import DesignFlowKernel
import DesignFlowKernel

extension RunReviewService {
    public func failureStateSummary(from review: RunReview) -> RunReviewFailureStateSummary {
        failureStateSummary(
            bundle: review.bundle,
            stages: review.stages,
            planningDecodeIssues: review.planning.decodeIssues,
            signoffDecodeIssues: review.signoff.decodeIssues,
            waiverDecodeIssues: review.waivers.decodeIssues
        )
    }

    func failureStateSummary(
        bundle: FlowRunReviewBundle,
        stages: [StageReview],
        planningDecodeIssues: [PlanningArtifactDecodeIssue],
        signoffDecodeIssues: [RunReviewArtifactDecodeIssue],
        waiverDecodeIssues: [RunReviewArtifactDecodeIssue]
    ) -> RunReviewFailureStateSummary {
        var states: [RunReviewFailureStateSummary.State] = []
        var seenStateIDs = Set<String>()
        let itemsByArtifactPath = reviewItemsByArtifactPath(bundle.reviewItems)

        for artifact in bundle.artifacts.sorted(by: artifactSortOrder) {
            guard
                let integrity = artifact.integrity,
                let kind = failureKind(for: integrity.status)
            else {
                continue
            }

            let linkedItems = itemsByArtifactPath[artifact.path, default: []]
            appendState(
                &states,
                seenStateIDs: &seenStateIDs,
                RunReviewFailureStateSummary.State(
                    stateID: "\(kind.rawValue):\(artifact.path)",
                    kind: kind,
                    severity: severity(for: kind),
                    title: title(for: kind),
                    message: integrity.message,
                    stageID: artifact.stageID,
                    itemID: linkedItems.first?.itemID,
                    nextActionID: linkedItems.first(where: { $0.nextActionID != nil })?.nextActionID,
                    artifactRefs: [failureArtifactReference(artifact)],
                    diagnosticCodes: uniqueSorted(linkedItems.flatMap(\.diagnosticCodes)),
                    suggestedActions: suggestedActions(for: kind)
                )
            )
        }

        for stage in stages.sorted(by: stageSortOrder) {
            appendBlockedStageStates(
                stage,
                bundle: bundle,
                states: &states,
                seenStateIDs: &seenStateIDs
            )
        }

        appendDecodeFailureStates(
            planningDecodeIssues: planningDecodeIssues,
            signoffDecodeIssues: signoffDecodeIssues,
            waiverDecodeIssues: waiverDecodeIssues,
            bundle: bundle,
            states: &states,
            seenStateIDs: &seenStateIDs
        )

        appendTextDetectedStates(
            from: bundle,
            states: &states,
            seenStateIDs: &seenStateIDs
        )

        return RunReviewFailureStateSummary(
            states: states.sorted(by: failureStateSortOrder)
        )
    }

    private func appendBlockedStageStates(
        _ stage: StageReview,
        bundle: FlowRunReviewBundle,
        states: inout [RunReviewFailureStateSummary.State],
        seenStateIDs: inout Set<String>
    ) {
        let stageItems = bundle.reviewItems.filter { $0.stageID == stage.result.stageID }
        let stageArtifacts = bundle.artifacts.filter { $0.stageID == stage.result.stageID }

        for gate in stage.result.gates where gate.status == .failed || gate.status == .incomplete {
            let linkedItem = stageItems.first { item in
                item.diagnosticCodes.contains { code in
                    gate.diagnostics.contains { $0.code == code }
                }
            } ?? stageItems.first { $0.nextActionID != nil }
            appendState(
                &states,
                seenStateIDs: &seenStateIDs,
                RunReviewFailureStateSummary.State(
                    stateID: "blocked-gate:\(stage.result.stageID):\(gate.gateID):\(gate.status.rawValue)",
                    kind: .blockedGate,
                    severity: gate.status == .failed ? .error : .warning,
                    title: gate.gateID == "approval" ? "Decide approval gate" : "Resolve blocked gate",
                    message: blockedGateMessage(stage: stage.result, gate: gate),
                    stageID: stage.result.stageID,
                    gateID: gate.gateID,
                    itemID: linkedItem?.itemID,
                    nextActionID: linkedItem?.nextActionID,
                    artifactRefs: stageArtifacts.map(failureArtifactReference).sorted(by: artifactReferenceSortOrder),
                    diagnosticCodes: gate.diagnostics.map(\.code),
                    suggestedActions: suggestedActionsForBlockedGate(gate.gateID)
                )
            )
        }

        if stage.result.status == .blocked {
            let linkedItem = stageItems.first { $0.kind == .stageBlocker }
                ?? stageItems.first { $0.nextActionID != nil }
            appendState(
                &states,
                seenStateIDs: &seenStateIDs,
                RunReviewFailureStateSummary.State(
                    stateID: "blocked-stage:\(stage.result.stageID)",
                    kind: .blockedGate,
                    severity: .warning,
                    title: "Resolve blocked stage",
                    message: "The stage is blocked and needs a concrete unblock decision before the run can continue.",
                    stageID: stage.result.stageID,
                    itemID: linkedItem?.itemID,
                    nextActionID: linkedItem?.nextActionID,
                    artifactRefs: stageArtifacts.map(failureArtifactReference).sorted(by: artifactReferenceSortOrder),
                    diagnosticCodes: uniqueSorted(stage.result.diagnostics.map(\.code)),
                    suggestedActions: ["inspect-review-item", "record-unblock-decision", "resume-run"]
                )
            )
        }
    }

    private func appendDecodeFailureStates(
        planningDecodeIssues: [PlanningArtifactDecodeIssue],
        signoffDecodeIssues: [RunReviewArtifactDecodeIssue],
        waiverDecodeIssues: [RunReviewArtifactDecodeIssue],
        bundle: FlowRunReviewBundle,
        states: inout [RunReviewFailureStateSummary.State],
        seenStateIDs: inout Set<String>
    ) {
        for issue in planningDecodeIssues {
            appendState(
                &states,
                seenStateIDs: &seenStateIDs,
                RunReviewFailureStateSummary.State(
                    stateID: "decode:planning:\(issue.artifactPath)",
                    kind: .decodeFailure,
                    severity: .warning,
                    title: "Decode planning artifact",
                    message: issue.message,
                    stageID: nil,
                    artifactRefs: artifactReferences(
                        path: issue.artifactPath,
                        role: issue.artifactRole,
                        bundle: bundle
                    ),
                    suggestedActions: ["inspect-artifact-preview", "validate-artifact-schema"]
                )
            )
        }

        for issue in signoffDecodeIssues {
            appendState(
                &states,
                seenStateIDs: &seenStateIDs,
                RunReviewFailureStateSummary.State(
                    stateID: "decode:signoff:\(issue.artifactPath)",
                    kind: .decodeFailure,
                    severity: .error,
                    title: "Decode signoff artifact",
                    message: issue.message,
                    stageID: nil,
                    artifactRefs: artifactReferences(
                        path: issue.artifactPath,
                        role: issue.artifactRole,
                        bundle: bundle
                    ),
                    suggestedActions: ["inspect-artifact-preview", "regenerate-signoff-artifact"]
                )
            )
        }

        for issue in waiverDecodeIssues {
            appendState(
                &states,
                seenStateIDs: &seenStateIDs,
                RunReviewFailureStateSummary.State(
                    stateID: "decode:waiver:\(issue.artifactPath)",
                    kind: .decodeFailure,
                    severity: .warning,
                    title: "Decode waiver artifact",
                    message: issue.message,
                    stageID: nil,
                    artifactRefs: artifactReferences(
                        path: issue.artifactPath,
                        role: issue.artifactRole,
                        bundle: bundle
                    ),
                    suggestedActions: ["inspect-artifact-preview", "repair-waiver-artifact"]
                )
            )
        }
    }

    private func appendTextDetectedStates(
        from bundle: FlowRunReviewBundle,
        states: inout [RunReviewFailureStateSummary.State],
        seenStateIDs: inout Set<String>
    ) {
        for item in bundle.reviewItems {
            if containsStaleEvidenceSignal(item) {
                appendState(
                    &states,
                    seenStateIDs: &seenStateIDs,
                    RunReviewFailureStateSummary.State(
                        stateID: "stale-review-item:\(item.itemID)",
                        kind: .staleEvidence,
                        severity: severity(from: item.severity),
                        title: item.title,
                        message: item.reason,
                        stageID: item.stageID,
                        itemID: item.itemID,
                        nextActionID: item.nextActionID,
                        artifactRefs: item.artifactPaths.flatMap {
                            artifactReferences(path: $0, role: "review-item", bundle: bundle)
                        },
                        diagnosticCodes: item.diagnosticCodes,
                        suggestedActions: ["inspect-review-item", "regenerate-evidence"]
                    )
                )
            }

            if containsUnsupportedActionSignal(item) {
                appendState(
                    &states,
                    seenStateIDs: &seenStateIDs,
                    RunReviewFailureStateSummary.State(
                        stateID: "unsupported-review-item:\(item.itemID)",
                        kind: .unsupportedAction,
                        severity: severity(from: item.severity),
                        title: item.title,
                        message: item.reason,
                        stageID: item.stageID,
                        itemID: item.itemID,
                        nextActionID: item.nextActionID,
                        artifactRefs: item.artifactPaths.flatMap {
                            artifactReferences(path: $0, role: "review-item", bundle: bundle)
                        },
                        diagnosticCodes: item.diagnosticCodes,
                        suggestedActions: ["choose-supported-command", "request-human-decision"]
                    )
                )
            }
        }

        for action in bundle.summary.nextActions {
            let unsupportedCommands = action.suggestedCommands.filter { command in
                containsUnsupportedActionSignal(command.commandID)
                    || containsUnsupportedActionSignal(command.reason)
                    || containsUnsupportedActionSignal(command.executable)
            }
            guard !unsupportedCommands.isEmpty else {
                continue
            }
            appendState(
                &states,
                seenStateIDs: &seenStateIDs,
                RunReviewFailureStateSummary.State(
                    stateID: "unsupported-next-action:\(action.actionID)",
                    kind: .unsupportedAction,
                    severity: severity(from: action.severity),
                    title: "Choose supported action",
                    message: action.reason,
                    stageID: action.stageID,
                    nextActionID: action.actionID,
                    diagnosticCodes: action.diagnosticCodes,
                    suggestedActions: unsupportedCommands.map(\.commandID)
                )
            )
        }
    }

    private func reviewItemsByArtifactPath(
        _ items: [FlowRunReviewItem]
    ) -> [String: [FlowRunReviewItem]] {
        var index: [String: [FlowRunReviewItem]] = [:]
        for item in items {
            for path in item.artifactPaths {
                index[path, default: []].append(item)
            }
        }
        return index
    }

    private func failureKind(
        for status: FlowRunReviewArtifactIntegrityStatus
    ) -> RunReviewFailureStateSummary.Kind? {
        switch status {
        case .verified:
            nil
        case .missingArtifact:
            .missingArtifact
        case .missingDigest, .missingByteCount:
            .staleEvidence
        case .invalidDigest, .invalidByteCount, .byteCountMismatch, .sha256Mismatch, .invalidIdentifier,
             .noRecordedReference, .invalidPath, .unreadableArtifact:
            .integrityMismatch
        }
    }

    private func severity(
        for kind: RunReviewFailureStateSummary.Kind
    ) -> RunReviewFailureStateSummary.Severity {
        switch kind {
        case .missingArtifact, .integrityMismatch, .decodeFailure:
            .error
        case .staleEvidence, .blockedGate, .unsupportedAction:
            .warning
        }
    }

    private func severity(
        from severity: FlowDiagnosticSeverity
    ) -> RunReviewFailureStateSummary.Severity {
        switch severity {
        case .info:
            .info
        case .warning:
            .warning
        case .error:
            .error
        }
    }

    private func title(for kind: RunReviewFailureStateSummary.Kind) -> String {
        switch kind {
        case .missingArtifact:
            "Restore missing artifact"
        case .integrityMismatch:
            "Repair artifact integrity"
        case .staleEvidence:
            "Refresh stale evidence"
        case .blockedGate:
            "Resolve blocked gate"
        case .decodeFailure:
            "Repair decoded artifact"
        case .unsupportedAction:
            "Choose supported action"
        }
    }

    private func suggestedActions(for kind: RunReviewFailureStateSummary.Kind) -> [String] {
        switch kind {
        case .missingArtifact:
            ["restore-or-regenerate-artifact", "rerun-producing-stage"]
        case .integrityMismatch:
            ["inspect-ledger-reference", "rerun-artifact-integrity-gate"]
        case .staleEvidence:
            ["refresh-artifact-reference", "record-digest-and-byte-count"]
        case .blockedGate:
            ["inspect-review-item", "record-unblock-decision"]
        case .decodeFailure:
            ["inspect-artifact-preview", "validate-artifact-schema"]
        case .unsupportedAction:
            ["choose-supported-command", "request-human-decision"]
        }
    }

    private func suggestedActionsForBlockedGate(_ gateID: String) -> [String] {
        if gateID == "approval" {
            return ["inspect-review-item", "record-approval-decision", "resume-run"]
        }
        return ["inspect-review-item", "repair-gate-inputs", "rerun-stage-after-unblock"]
    }

    private func blockedGateMessage(stage: FlowStageResult, gate: FlowGateResult) -> String {
        let diagnosticText = gate.diagnostics.map(\.message).filter { !$0.isEmpty }.joined(separator: " ")
        if !diagnosticText.isEmpty {
            return diagnosticText
        }
        return "Gate \(gate.gateID) is \(gate.status.rawValue) for stage \(stage.stageID)."
    }

    private func artifactReferences(
        path: String,
        role: String,
        bundle: FlowRunReviewBundle
    ) -> [RunReviewFailureStateSummary.ArtifactReference] {
        let refs = bundle.artifacts.filter { $0.path == path }
        if !refs.isEmpty {
            return refs.map(failureArtifactReference).sorted(by: artifactReferenceSortOrder)
        }
        return [
            RunReviewFailureStateSummary.ArtifactReference(
                role: role,
                artifactID: nil,
                stageID: nil,
                path: path,
                kind: XcircuiteFileKind.other.rawValue,
                format: XcircuiteFileFormat.unknown.rawValue,
                integrityStatus: nil,
                integrityMessage: nil
            ),
        ]
    }

    private func failureArtifactReference(
        _ artifact: FlowRunReviewArtifact
    ) -> RunReviewFailureStateSummary.ArtifactReference {
        RunReviewFailureStateSummary.ArtifactReference(
            role: artifact.role,
            artifactID: artifact.artifactID,
            stageID: artifact.stageID,
            path: artifact.path,
            kind: artifact.kind.rawValue,
            format: artifact.format.rawValue,
            integrityStatus: artifact.integrity?.status.rawValue,
            integrityMessage: artifact.integrity?.message
        )
    }

    private func appendState(
        _ states: inout [RunReviewFailureStateSummary.State],
        seenStateIDs: inout Set<String>,
        _ state: RunReviewFailureStateSummary.State
    ) {
        guard seenStateIDs.insert(state.stateID).inserted else {
            return
        }
        states.append(state)
    }

    private func containsStaleEvidenceSignal(_ item: FlowRunReviewItem) -> Bool {
        containsStaleEvidenceSignal(item.title)
            || containsStaleEvidenceSignal(item.reason)
            || item.diagnosticCodes.contains(where: containsStaleEvidenceSignal)
    }

    private func containsStaleEvidenceSignal(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("stale") || normalized.contains("outdated")
    }

    private func containsUnsupportedActionSignal(_ item: FlowRunReviewItem) -> Bool {
        containsUnsupportedActionSignal(item.title)
            || containsUnsupportedActionSignal(item.reason)
            || item.diagnosticCodes.contains(where: containsUnsupportedActionSignal)
    }

    private func containsUnsupportedActionSignal(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("unsupported") || normalized.contains("not supported")
    }

    private func artifactSortOrder(
        _ left: FlowRunReviewArtifact,
        _ right: FlowRunReviewArtifact
    ) -> Bool {
        if left.stageID != right.stageID {
            return (left.stageID ?? "") < (right.stageID ?? "")
        }
        if left.role != right.role {
            return left.role < right.role
        }
        return left.path < right.path
    }

    private func stageSortOrder(_ left: StageReview, _ right: StageReview) -> Bool {
        left.result.stageID < right.result.stageID
    }

    private func failureStateSortOrder(
        _ left: RunReviewFailureStateSummary.State,
        _ right: RunReviewFailureStateSummary.State
    ) -> Bool {
        if left.severity != right.severity {
            return severityRank(left.severity) > severityRank(right.severity)
        }
        if left.kind != right.kind {
            return left.kind.rawValue < right.kind.rawValue
        }
        return left.stateID < right.stateID
    }

    private func severityRank(_ severity: RunReviewFailureStateSummary.Severity) -> Int {
        switch severity {
        case .error:
            3
        case .warning:
            2
        case .info:
            1
        }
    }

    private func artifactReferenceSortOrder(
        _ left: RunReviewFailureStateSummary.ArtifactReference,
        _ right: RunReviewFailureStateSummary.ArtifactReference
    ) -> Bool {
        if left.role != right.role {
            return left.role < right.role
        }
        return left.path < right.path
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }
}
