import DesignFlowKernel
import Foundation
import CircuiteFoundation
import Xcircuite

extension RunReviewService {
    public func decideWaiverReview(
        runID: String,
        waiverReviewID: String,
        decision: RunReviewWaiverDecisionValue,
        reviewer: String,
        note: String = "",
        projectRoot: URL
    ) throws -> XcircuiteRunActionRecord {
        let ledger = try ledgerLoader.loadRunLedger(runID: runID, projectRoot: projectRoot)
        let bundle = try reviewBundler.makeReviewBundle(runID: runID, projectRoot: projectRoot)
        let summary = waiverReview(
            bundle: bundle,
            actions: ledger.actions,
            projectRoot: projectRoot
        )
        guard let item = summary.items.first(where: { $0.waiverReviewID == waiverReviewID }) else {
            throw RunReviewServiceError.waiverReviewNotFound(waiverReviewID: waiverReviewID)
        }

        var metadata: [String: XcircuiteJSONValue] = [
            "waiverReviewID": .string(item.waiverReviewID),
            "decision": .string(decision.rawValue),
            "domain": .string(item.domain),
            "artifactPath": .string(item.artifact.path),
            "waivedCount": .number(Double(item.waivedCount)),
            "unusedWaiverIDs": .array(item.unusedWaiverIDs.map { .string($0) }),
            "sourceReferences": .array(item.sourceReferences.map(sourceReferenceMetadataValue)),
            "editProposalIDs": .array(item.editProposals.map { .string($0.proposalID) }),
            "note": .string(note),
        ]
        if let artifactID = item.artifact.artifactID {
            metadata["artifactID"] = .string(artifactID)
        }
        if let stageID = item.stageID {
            metadata["stageID"] = .string(stageID)
        }

        let record = XcircuiteRunActionRecord(
            actionID: "waiver-review-\(UUID().uuidString)",
            runID: runID,
            stageID: item.stageID,
            actor: XcircuiteRunActionActor(kind: .human, identifier: reviewer),
            actionKind: RunReviewWaiverDecision.actionKind,
            status: .succeeded,
            inputs: [fileReference(from: item.artifact)],
            metadata: metadata
        )
        try store.appendRunAction(record, inProjectAt: projectRoot)
        return record
    }

    public func recordWaiverEditProposalSelection(
        runID: String,
        waiverReviewID: String,
        proposalID: String,
        reviewer: String,
        note: String = "",
        projectRoot: URL
    ) throws -> XcircuiteRunActionRecord {
        let ledger = try ledgerLoader.loadRunLedger(runID: runID, projectRoot: projectRoot)
        let bundle = try reviewBundler.makeReviewBundle(runID: runID, projectRoot: projectRoot)
        let summary = waiverReview(
            bundle: bundle,
            actions: ledger.actions,
            projectRoot: projectRoot
        )
        guard let item = summary.items.first(where: { $0.waiverReviewID == waiverReviewID }) else {
            throw RunReviewServiceError.waiverReviewNotFound(waiverReviewID: waiverReviewID)
        }
        guard let proposal = item.editProposals.first(where: { $0.proposalID == proposalID }) else {
            throw RunReviewServiceError.waiverEditProposalNotFound(
                waiverReviewID: waiverReviewID,
                proposalID: proposalID
            )
        }

        var metadata: [String: XcircuiteJSONValue] = [
            "waiverReviewID": .string(item.waiverReviewID),
            "proposalID": .string(proposal.proposalID),
            "domain": .string(item.domain),
            "artifactPath": .string(item.artifact.path),
            "kind": .string(proposal.kind),
            "proposalStatus": .string(proposal.status),
            "targetPath": .string(proposal.targetPath),
            "operation": .string(proposal.operation),
            "summary": .string(proposal.summary),
            "risk": .string(proposal.risk),
            "note": .string(note),
        ]
        if let waiverID = proposal.waiverID {
            metadata["waiverID"] = .string(waiverID)
        }
        if let replacementText = proposal.replacementText {
            metadata["replacementText"] = .string(replacementText)
        }
        if let artifactID = item.artifact.artifactID {
            metadata["artifactID"] = .string(artifactID)
        }
        if let stageID = item.stageID {
            metadata["stageID"] = .string(stageID)
        }

        let record = XcircuiteRunActionRecord(
            actionID: "waiver-edit-proposal-selection-\(UUID().uuidString)",
            runID: runID,
            stageID: item.stageID,
            actor: XcircuiteRunActionActor(kind: .human, identifier: reviewer),
            actionKind: RunReviewWaiverEditProposalSelection.actionKind,
            status: .succeeded,
            inputs: [fileReference(from: item.artifact)],
            metadata: metadata
        )
        try store.appendRunAction(record, inProjectAt: projectRoot)
        return record
    }

    public func applyWaiverEditProposal(
        runID: String,
        waiverReviewID: String,
        proposalID: String,
        reviewer: String,
        note: String = "",
        projectRoot: URL
    ) throws -> XcircuiteRunActionRecord {
        let ledger = try ledgerLoader.loadRunLedger(runID: runID, projectRoot: projectRoot)
        let bundle = try reviewBundler.makeReviewBundle(runID: runID, projectRoot: projectRoot)
        let summary = waiverReview(
            bundle: bundle,
            actions: ledger.actions,
            projectRoot: projectRoot
        )
        guard let item = summary.items.first(where: { $0.waiverReviewID == waiverReviewID }) else {
            throw RunReviewServiceError.waiverReviewNotFound(waiverReviewID: waiverReviewID)
        }
        guard let proposal = item.editProposals.first(where: { $0.proposalID == proposalID }) else {
            throw RunReviewServiceError.waiverEditProposalNotFound(
                waiverReviewID: waiverReviewID,
                proposalID: proposalID
            )
        }

        let appliedEdit = try applyEdit(proposal: proposal, projectRoot: projectRoot)
        var metadata: [String: XcircuiteJSONValue] = [
            "waiverReviewID": .string(item.waiverReviewID),
            "proposalID": .string(proposal.proposalID),
            "domain": .string(item.domain),
            "artifactPath": .string(item.artifact.path),
            "kind": .string(proposal.kind),
            "targetPath": .string(proposal.targetPath),
            "operation": .string(proposal.operation),
            "summary": .string(proposal.summary),
            "risk": .string(proposal.risk),
            "beforeSHA256": .string(appliedEdit.beforeReference.sha256),
            "afterSHA256": .string(appliedEdit.afterReference.sha256),
            "beforeByteCount": .number(Double(appliedEdit.beforeReference.byteCount)),
            "afterByteCount": .number(Double(appliedEdit.afterReference.byteCount)),
            "note": .string(note),
        ]
        if let waiverID = proposal.waiverID {
            metadata["waiverID"] = .string(waiverID)
        }
        if let artifactID = item.artifact.artifactID {
            metadata["artifactID"] = .string(artifactID)
        }
        if let stageID = item.stageID {
            metadata["stageID"] = .string(stageID)
        }

        let record = XcircuiteRunActionRecord(
            actionID: "waiver-edit-proposal-application-\(UUID().uuidString)",
            runID: runID,
            stageID: item.stageID,
            actor: XcircuiteRunActionActor(kind: .human, identifier: reviewer),
            actionKind: RunReviewWaiverEditApplication.actionKind,
            status: .succeeded,
            inputs: [
                fileReference(from: item.artifact),
                try FoundationArtifactTypeProjection.legacyReference(appliedEdit.beforeReference),
            ],
            outputs: [try FoundationArtifactTypeProjection.legacyReference(appliedEdit.afterReference)],
            metadata: metadata
        )
        try store.appendRunAction(record, inProjectAt: projectRoot)
        return record
    }

    public func recordWaiverEditVerification(
        runID: String,
        waiverReviewID: String,
        proposalID: String,
        reviewer: String,
        verificationReport: DesignFlowVerificationReport,
        verificationReportURL: URL,
        layoutTrustReportURL: URL?,
        note: String = "",
        projectRoot: URL
    ) throws -> XcircuiteRunActionRecord {
        let ledger = try ledgerLoader.loadRunLedger(runID: runID, projectRoot: projectRoot)
        let bundle = try reviewBundler.makeReviewBundle(runID: runID, projectRoot: projectRoot)
        let summary = waiverReview(
            bundle: bundle,
            actions: ledger.actions,
            projectRoot: projectRoot
        )
        guard let item = summary.items.first(where: { $0.waiverReviewID == waiverReviewID }) else {
            throw RunReviewServiceError.waiverReviewNotFound(waiverReviewID: waiverReviewID)
        }
        guard item.editProposals.contains(where: { $0.proposalID == proposalID }) else {
            throw RunReviewServiceError.waiverEditProposalNotFound(
                waiverReviewID: waiverReviewID,
                proposalID: proposalID
            )
        }
        guard let application = item.editApplications.last(where: { $0.proposalID == proposalID }) else {
            throw RunReviewServiceError.waiverEditApplicationNotFound(
                waiverReviewID: waiverReviewID,
                proposalID: proposalID
            )
        }

        let verificationReference = try projectFileReference(
            url: verificationReportURL,
            projectRoot: projectRoot,
            artifactID: "post-waiver-edit-physical-verification",
            kind: .report,
            format: .json
        )
        let layoutTrustReference = try layoutTrustReportURL.map {
            try projectFileReference(
                url: $0,
                projectRoot: projectRoot,
                artifactID: "post-waiver-edit-layout-trust",
                kind: .report,
                format: .json
            )
        }
        let targetReference = try waiverEditTargetReference(
            application: application,
            projectRoot: projectRoot
        )
        let feedback = try recordWaiverEditPlanningFeedback(
            runID: runID,
            waiverReviewID: item.waiverReviewID,
            proposalID: proposalID,
            application: application,
            targetReference: targetReference,
            verificationReport: verificationReport,
            verificationReference: verificationReference,
            layoutTrustReference: layoutTrustReference,
            projectRoot: projectRoot
        )

        var metadata: [String: XcircuiteJSONValue] = [
            "waiverReviewID": .string(item.waiverReviewID),
            "proposalID": .string(proposalID),
            "applicationActionID": .string(application.actionRecordID),
            "verificationReportPath": .string(verificationReference.path),
            "verificationStatus": .string(verificationReport.status),
            "readyForPEX": .bool(verificationReport.readyForPEX),
            "drcPassed": .bool(verificationReport.drc.passed),
            "drcViolationCount": .number(Double(verificationReport.drc.violationCount)),
            "lvsPassed": .bool(verificationReport.lvs.passed),
            "verificationSummary": waiverEditVerificationSummaryMetadataValue(verificationReport),
            "targetPath": .string(application.targetPath),
            "targetSHA256": .string(application.afterSHA256),
            "planningFeedbackStatus": .string(feedback.status),
            "candidatePlanPath": .string(feedback.candidatePlanRef.path),
            "planVerificationPath": .string(feedback.planVerificationRef.path),
            "note": .string(note),
        ]
        if let layoutTrustReference {
            metadata["layoutTrustReportPath"] = .string(layoutTrustReference.path)
        }
        if let rejectedPlansRef = feedback.rejectedPlansRef {
            metadata["rejectedPlansPath"] = .string(rejectedPlansRef.path)
        }
        if let artifactID = item.artifact.artifactID {
            metadata["artifactID"] = .string(artifactID)
        }
        if let stageID = item.stageID {
            metadata["stageID"] = .string(stageID)
        }

        let supplementaryLegacyReferences = try [layoutTrustReference, feedback.rejectedPlansRef]
            .compactMap { $0 }
            .map(FoundationArtifactTypeProjection.legacyReference)
        let record = XcircuiteRunActionRecord(
            actionID: "waiver-edit-proposal-verification-\(UUID().uuidString)",
            runID: runID,
            stageID: item.stageID,
            actor: XcircuiteRunActionActor(kind: .human, identifier: reviewer),
            actionKind: RunReviewWaiverEditVerification.actionKind,
            status: .succeeded,
            inputs: [
                fileReference(from: item.artifact),
                try FoundationArtifactTypeProjection.legacyReference(targetReference),
            ],
            outputs: [
                try FoundationArtifactTypeProjection.legacyReference(verificationReference),
                try FoundationArtifactTypeProjection.legacyReference(feedback.candidatePlanRef),
                try FoundationArtifactTypeProjection.legacyReference(feedback.planVerificationRef),
            ] + supplementaryLegacyReferences,
            metadata: metadata
        )
        try store.appendRunAction(record, inProjectAt: projectRoot)
        return record
    }

    public func waiverEditVerificationContext(
        runID: String,
        projectRoot: URL
    ) throws -> RunReviewWaiverEditVerificationContext {
        try waiverEditVerificationContext(
            review: loadRun(runID: runID, projectRoot: projectRoot),
            projectRoot: projectRoot
        )
    }

    public func waiverEditVerificationContext(
        review: RunReview,
        projectRoot: URL
    ) throws -> RunReviewWaiverEditVerificationContext {
        guard let designSpecArtifact = latestDesignSpecArtifact(in: review.bundle.artifacts) else {
            throw RunReviewServiceError.waiverEditVerificationDesignSpecNotFound(runID: review.runID)
        }
        guard let layoutArtifact = latestLayoutDocumentArtifact(in: review.bundle.artifacts) else {
            throw RunReviewServiceError.waiverEditVerificationLayoutDocumentNotFound(runID: review.runID)
        }

        let designSpecURL = try existingVerificationInputURL(for: designSpecArtifact, projectRoot: projectRoot)
        let layoutURL = try existingVerificationInputURL(for: layoutArtifact, projectRoot: projectRoot)
        let designUnitArtifact = latestDesignUnitArtifact(in: review.bundle.artifacts)
        let designUnitURL = try designUnitArtifact.map {
            try existingVerificationInputURL(for: $0, projectRoot: projectRoot)
        }

        return RunReviewWaiverEditVerificationContext(
            designSpecArtifact: designSpecArtifact,
            layoutDocumentArtifact: layoutArtifact,
            designUnitArtifact: designUnitArtifact,
            designSpecURL: designSpecURL,
            layoutDocumentURL: layoutURL,
            designUnitURL: designUnitURL
        )
    }

    /// `technologyPackagePath` is required by the downstream verification
    /// contract: the layout technology must be explicit — there is no
    /// silent process fallback.
    public func runPostWaiverEditVerification(
        runID: String,
        waiverReviewID: String,
        proposalID: String,
        reviewer: String,
        note: String = "",
        technologyPackagePath: String? = nil,
        projectRoot: URL
    ) async throws -> DesignFlowCommandResult {
        let context = try waiverEditVerificationContext(runID: runID, projectRoot: projectRoot)
        return try await DesignFlowService().execute(DesignFlowCommand(
            kind: .runPostWaiverEditVerification,
            designSpecPath: context.designSpecURL.path(percentEncoded: false),
            projectRootPath: projectRoot.path(percentEncoded: false),
            runID: runID,
            technologyPackagePath: technologyPackagePath,
            layoutDocumentPath: context.layoutDocumentURL.path(percentEncoded: false),
            designUnitPath: context.designUnitURL?.path(percentEncoded: false),
            approvalReviewer: reviewer,
            approvalNote: note,
            waiverReviewID: waiverReviewID,
            waiverProposalID: proposalID
        ))
    }

    /// `technologyPackagePath` is required by the downstream verification
    /// contract: the layout technology must be explicit — there is no
    /// silent process fallback.
    public func applyWaiverEditProposalAndRunPostVerification(
        runID: String,
        waiverReviewID: String,
        proposalID: String,
        reviewer: String,
        note: String = "",
        technologyPackagePath: String? = nil,
        projectRoot: URL
    ) async throws -> DesignFlowCommandResult {
        let context = try waiverEditVerificationContext(runID: runID, projectRoot: projectRoot)
        return try await DesignFlowService().execute(DesignFlowCommand(
            kind: .applyWaiverEditProposalAndRunPostVerification,
            designSpecPath: context.designSpecURL.path(percentEncoded: false),
            projectRootPath: projectRoot.path(percentEncoded: false),
            runID: runID,
            technologyPackagePath: technologyPackagePath,
            layoutDocumentPath: context.layoutDocumentURL.path(percentEncoded: false),
            designUnitPath: context.designUnitURL?.path(percentEncoded: false),
            approvalReviewer: reviewer,
            approvalNote: note,
            waiverReviewID: waiverReviewID,
            waiverProposalID: proposalID
        ))
    }

    func waiverReview(
        bundle: FlowRunReviewBundle,
        actions: [XcircuiteRunActionRecord],
        projectRoot: URL
    ) -> RunReviewWaiverSummary {
        let decisions = waiverDecisionsByReviewID(from: actions)
        let editProposalSelections = waiverEditProposalSelectionsByReviewID(from: actions)
        let editApplications = waiverEditApplicationsByReviewID(from: actions)
        let editVerifications = waiverEditVerificationsByReviewID(from: actions)
        var items: [RunReviewWaiverItem] = []
        var decodeIssues: [RunReviewArtifactDecodeIssue] = []

        for artifact in bundle.artifacts where artifact.format == .json {
            switch waiverArtifactKind(for: artifact) {
            case .drc:
                appendWaiverItem(
                    artifact: artifact,
                    projectRoot: projectRoot,
                    decisions: decisions,
                    editProposalSelections: editProposalSelections,
                    editApplications: editApplications,
                    editVerifications: editVerifications,
                    decodeIssues: &decodeIssues,
                    items: &items,
                    makeItem: drcWaiverItem
                )
            case .lvs:
                appendWaiverItem(
                    artifact: artifact,
                    projectRoot: projectRoot,
                    decisions: decisions,
                    editProposalSelections: editProposalSelections,
                    editApplications: editApplications,
                    editVerifications: editVerifications,
                    decodeIssues: &decodeIssues,
                    items: &items,
                    makeItem: lvsWaiverItem
                )
            case .none:
                continue
            }
        }

        return RunReviewWaiverSummary(
            items: items.sorted { left, right in
                if left.domain != right.domain {
                    return left.domain < right.domain
                }
                return left.artifact.path < right.artifact.path
            },
            decodeIssues: decodeIssues
        )
    }

    private func appendWaiverItem<Document: Decodable>(
        artifact: FlowRunReviewArtifact,
        projectRoot: URL,
        decisions: [String: RunReviewWaiverDecision],
        editProposalSelections: [String: [RunReviewWaiverEditProposalSelection]],
        editApplications: [String: [RunReviewWaiverEditApplication]],
        editVerifications: [String: [RunReviewWaiverEditVerification]],
        decodeIssues: inout [RunReviewArtifactDecodeIssue],
        items: inout [RunReviewWaiverItem],
        makeItem: (
            Document,
            FlowRunReviewArtifact,
            RunReviewWaiverDecision?,
            [RunReviewWaiverEditProposalSelection],
            [RunReviewWaiverEditApplication],
            [RunReviewWaiverEditVerification]
        ) -> RunReviewWaiverItem?
    ) {
        do {
            try validateWaiverArtifactIntegrity(artifact)
            let data = try Data(contentsOf: waiverArtifactURL(for: artifact, projectRoot: projectRoot))
            let document = try JSONDecoder().decode(Document.self, from: data)
            let reviewID = waiverReviewID(domain: waiverDomain(for: artifact), artifact: artifact)
            if let item = makeItem(
                document,
                artifact,
                decisions[reviewID],
                editProposalSelections[reviewID] ?? [],
                editApplications[reviewID] ?? [],
                editVerifications[reviewID] ?? []
            ) {
                items.append(item)
            }
        } catch {
            decodeIssues.append(
                RunReviewArtifactDecodeIssue(
                    artifactRole: artifact.role,
                    artifactPath: artifact.path,
                    message: error.localizedDescription
                )
            )
        }
    }

    private func validateWaiverArtifactIntegrity(_ artifact: FlowRunReviewArtifact) throws {
        guard let integrity = artifact.integrity else {
            throw RunReviewServiceError.waiverArtifactIntegrityUnverified(
                path: artifact.path,
                status: "missing",
                message: "Artifact integrity was not recorded."
            )
        }
        guard integrity.status == .verified else {
            throw RunReviewServiceError.waiverArtifactIntegrityUnverified(
                path: artifact.path,
                status: integrity.status.rawValue,
                message: integrity.message
            )
        }
    }

    private func drcWaiverItem(
        document: DRCWaiverReviewDocument,
        artifact: FlowRunReviewArtifact,
        decision: RunReviewWaiverDecision?,
        editProposalSelections: [RunReviewWaiverEditProposalSelection],
        editApplications: [RunReviewWaiverEditApplication],
        editVerifications: [RunReviewWaiverEditVerification]
    ) -> RunReviewWaiverItem? {
        let summary = document.summary
        guard summary.waivedViolationCount > 0
                || !summary.unusedWaiverIDs.isEmpty
                || !summary.waiverSources.isEmpty
                || !summary.editProposals.isEmpty else {
            return nil
        }
        let buckets = summary.violationBuckets
            .filter { $0.waivedCount > 0 }
            .map {
                RunReviewWaivedBucket(
                    label: $0.ruleID ?? $0.kind ?? $0.layer ?? "drc-waiver",
                    count: $0.waivedCount,
                    message: [$0.kind, $0.layer].compactMap { $0 }.joined(separator: " ")
                )
            }
        return RunReviewWaiverItem(
            waiverReviewID: waiverReviewID(domain: "DRC", artifact: artifact),
            domain: "DRC",
            stageID: artifact.stageID,
            artifact: artifact,
            status: waiverStatus(defaultStatus: "needs-review", decision: decision),
            waivedCount: summary.waivedViolationCount,
            unusedWaiverIDs: summary.unusedWaiverIDs,
            waivedBuckets: buckets,
            sourceReferences: summary.waiverSources.map(\.reviewSourceReference),
            editProposals: summary.editProposals.map(\.reviewEditProposal),
            editProposalSelections: editProposalSelections,
            editApplications: editApplications,
            editVerifications: editVerifications,
            latestDecision: decision
        )
    }

    private func lvsWaiverItem(
        document: LVSWaiverReviewDocument,
        artifact: FlowRunReviewArtifact,
        decision: RunReviewWaiverDecision?,
        editProposalSelections: [RunReviewWaiverEditProposalSelection],
        editApplications: [RunReviewWaiverEditApplication],
        editVerifications: [RunReviewWaiverEditVerification]
    ) -> RunReviewWaiverItem? {
        let summary = document.summary
        guard summary.waivedMismatchCount > 0
                || !summary.unusedWaiverIDs.isEmpty
                || !summary.waiverSources.isEmpty
                || !summary.editProposals.isEmpty else {
            return nil
        }
        let buckets = summary.mismatchBuckets
            .filter { $0.waivedCount > 0 }
            .map {
                RunReviewWaivedBucket(
                    label: $0.ruleID ?? $0.category ?? $0.componentSignature ?? "lvs-waiver",
                    count: $0.waivedCount,
                    message: [$0.category, $0.componentSignature].compactMap { $0 }.joined(separator: " ")
                )
            }
        return RunReviewWaiverItem(
            waiverReviewID: waiverReviewID(domain: "LVS", artifact: artifact),
            domain: "LVS",
            stageID: artifact.stageID,
            artifact: artifact,
            status: waiverStatus(defaultStatus: "needs-review", decision: decision),
            waivedCount: summary.waivedMismatchCount,
            unusedWaiverIDs: summary.unusedWaiverIDs,
            waivedBuckets: buckets,
            sourceReferences: summary.waiverSources.map(\.reviewSourceReference),
            editProposals: summary.editProposals.map(\.reviewEditProposal),
            editProposalSelections: editProposalSelections,
            editApplications: editApplications,
            editVerifications: editVerifications,
            latestDecision: decision
        )
    }


    private func waiverArtifactKind(for artifact: FlowRunReviewArtifact) -> WaiverArtifactKind? {
        let artifactID = artifact.artifactID ?? ""
        let path = artifact.path.lowercased()
        if artifactID == "drc-summary" || path.hasSuffix("drc-summary.json") {
            return .drc
        }
        if artifactID == "lvs-summary" || path.hasSuffix("lvs-summary.json") {
            return .lvs
        }
        return nil
    }

    private func waiverDomain(for artifact: FlowRunReviewArtifact) -> String {
        switch waiverArtifactKind(for: artifact) {
        case .drc:
            "DRC"
        case .lvs:
            "LVS"
        case .none:
            "Unknown"
        }
    }

    private func waiverReviewID(domain: String, artifact: FlowRunReviewArtifact) -> String {
        "\(domain.lowercased())-waiver:\(artifact.path)"
    }

    private func waiverStatus(
        defaultStatus: String,
        decision: RunReviewWaiverDecision?
    ) -> String {
        guard let decision else {
            return defaultStatus
        }
        return decision.decision.rawValue
    }

    private func fileReference(from artifact: FlowRunReviewArtifact) -> XcircuiteFileReference {
        XcircuiteFileReference(
            artifactID: artifact.artifactID,
            path: artifact.path,
            kind: artifact.kind,
            format: artifact.format,
            sha256: artifact.sha256,
            byteCount: artifact.byteCount
        )
    }

    private func projectFileReference(
        url: URL,
        projectRoot: URL,
        artifactID: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat
    ) throws -> ArtifactReference {
        let path = try projectRelativePath(for: url, projectRoot: projectRoot)
        let hasher = XcircuiteHasher()
        let legacy = XcircuiteFileReference(
            artifactID: artifactID,
            path: path,
            kind: kind,
            format: format,
            sha256: try hasher.sha256(fileAt: url),
            byteCount: try hasher.byteCount(fileAt: url)
        )
        guard let reference = FoundationArtifactTypeProjection.reference(legacy) else {
            throw RunReviewServiceError.artifactReferenceProjectionFailed(
                path: path,
                message: "Generated verification artifact has invalid integrity metadata."
            )
        }
        return reference
    }

    private func recordWaiverEditPlanningFeedback(
        runID: String,
        waiverReviewID: String,
        proposalID: String,
        application: RunReviewWaiverEditApplication,
        targetReference: ArtifactReference,
        verificationReport: DesignFlowVerificationReport,
        verificationReference: ArtifactReference,
        layoutTrustReference: ArtifactReference?,
        projectRoot: URL
    ) throws -> WaiverEditPlanningFeedback {
        let safeProposalID = safeIdentifierComponent(proposalID)
        let planID = "\(runID)-waiver-edit-\(safeProposalID)"
        let problemID = "\(runID)-waiver-edit-problem-\(safeProposalID)"
        let basePath = "\(XcircuiteWorkspace.directoryName)/runs/\(runID)/planning/waiver-edit-feedback/\(safeProposalID)"
        let candidatePlanPath = "\(basePath)/candidate-plan.json"
        let planVerificationPath = "\(basePath)/plan-verification.json"
        let gateIDs = [
            "post-waiver-edit-drc",
            "post-waiver-edit-lvs",
            "post-waiver-edit-layout-trust",
            "post-waiver-edit-ready-for-pex",
        ]
        let stepID = "apply-waiver-edit-\(safeProposalID)"
        let candidatePlan = XcircuiteCandidatePlan(
            planID: planID,
            problemID: problemID,
            runID: runID,
            strategy: "waiver-edit-post-verification-feedback",
            executionReadiness: "executed",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "waiver-review",
                kind: "waiver-review",
                metadata: [
                    "waiverReviewID": .string(waiverReviewID),
                    "proposalID": .string(proposalID),
                    "applicationActionID": .string(application.actionRecordID),
                ]
            ),
            steps: [
                XcircuiteCandidatePlanStep(
                    stepID: stepID,
                    order: 1,
                    actionID: application.actionRecordID,
                    domainID: "waiver-review",
                    operationID: RunReviewWaiverEditApplication.actionKind,
                    maturity: "usable",
                    readiness: "executed",
                    sourceObjectiveIDs: [waiverReviewID],
                    requiredInputRefs: ["waiver-review", "waiver-edit-proposal"],
                    missingInputRefs: [],
                    verificationGates: gateIDs,
                    reason: "Capture post-waiver-edit verification feedback for future planning iterations.",
                    parameterHints: [
                        "proposalID": .string(proposalID),
                        "targetPath": .string(application.targetPath),
                        "operation": .string(application.operation),
                    ],
                    blockers: []
                ),
            ],
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "post-waiver-edit-drc",
                    required: true,
                    description: "DRC must pass after waiver source edit."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "post-waiver-edit-lvs",
                    required: true,
                    description: "LVS must pass after waiver source edit."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "post-waiver-edit-layout-trust",
                    required: true,
                    description: "Layout trust must pass after waiver source edit."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "post-waiver-edit-ready-for-pex",
                    required: true,
                    description: "The design must remain ready for PEX after waiver source edit."
                ),
            ],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
        let candidatePlanRef = try writePlanningFeedbackArtifact(
            candidatePlan,
            path: candidatePlanPath,
            artifactID: "post-waiver-edit-candidate-plan-\(safeProposalID)",
            runID: runID,
            projectRoot: projectRoot
        )

        let gateResults = waiverEditVerificationGateResults(verificationReport, sourceStepID: stepID)
        let diagnostics = gateResults.flatMap(\.diagnostics)
        let failedGateIDs = gateResults
            .filter { $0.status == "failed" }
            .map(\.gateID)
        let accepted = verificationReport.readyForPEX && failedGateIDs.isEmpty
        let artifactRefs = [targetReference, verificationReference] + [layoutTrustReference].compactMap { $0 }
        let legacyArtifactRefs = try artifactRefs.map(FoundationArtifactTypeProjection.legacyReference)
        let legacyCandidatePlanRef = try FoundationArtifactTypeProjection.legacyReference(candidatePlanRef)
        let planVerification = XcircuitePlanVerification(
            problemID: problemID,
            planID: planID,
            runID: runID,
            verificationMode: "post-waiver-edit",
            candidatePlanRef: legacyCandidatePlanRef,
            stepResults: [
                XcircuitePlanVerificationStepResult(
                    stepID: stepID,
                    order: 1,
                    actionID: application.actionRecordID,
                    domainID: "waiver-review",
                    operationID: RunReviewWaiverEditApplication.actionKind,
                    status: accepted ? "passed" : "failed",
                    gateIDs: gateIDs,
                    diagnostics: diagnostics,
                    producedArtifactRefs: legacyArtifactRefs
                ),
            ],
            gateResults: gateResults,
            artifactRefs: legacyArtifactRefs,
            diagnostics: diagnostics,
            accepted: accepted,
            nextActions: accepted ? [] : failedGateIDs.map { "repair-verification-gate:\($0)" }
        )
        let planVerificationRef = try writePlanningFeedbackArtifact(
            planVerification,
            path: planVerificationPath,
            artifactID: "post-waiver-edit-plan-verification-\(safeProposalID)",
            runID: runID,
            projectRoot: projectRoot
        )

        guard !accepted else {
            return WaiverEditPlanningFeedback(
                status: "accepted-no-rejected-plan",
                candidatePlanRef: candidatePlanRef,
                planVerificationRef: planVerificationRef,
                rejectedPlansRef: nil
            )
        }

        let rejectedRecord = XcircuiteRejectedPlanRecord(
            rejectionID: "\(planID)-rejected",
            runID: runID,
            problemID: problemID,
            planID: planID,
            verificationMode: "post-waiver-edit",
            status: "rejected",
            sourceParameterCandidateIDs: [],
            failedStepIDs: [stepID],
            failedGateIDs: failedGateIDs,
            candidatePlanRef: legacyCandidatePlanRef,
            planVerificationRef: try FoundationArtifactTypeProjection.legacyReference(planVerificationRef),
            artifactRefs: legacyArtifactRefs,
            diagnostics: diagnostics,
            nextActions: failedGateIDs.map { "repair-verification-gate:\($0)" }
        )
        let rejectedPlansLegacyRef = try XcircuitePlanningArtifactStore(storage: store).appendRejectedPlan(
            rejectedRecord,
            runID: runID,
            projectRoot: projectRoot
        )
        guard let rejectedPlansRef = FoundationArtifactTypeProjection.reference(rejectedPlansLegacyRef) else {
            throw RunReviewServiceError.artifactReferenceProjectionFailed(
                path: rejectedPlansLegacyRef.path,
                message: "Rejected-plan artifact has invalid integrity metadata."
            )
        }
        return WaiverEditPlanningFeedback(
            status: "rejected-plan-recorded",
            candidatePlanRef: candidatePlanRef,
            planVerificationRef: planVerificationRef,
            rejectedPlansRef: rejectedPlansRef
        )
    }

    private func writePlanningFeedbackArtifact<T: Encodable>(
        _ value: T,
        path: String,
        artifactID: String,
        runID: String,
        projectRoot: URL
    ) throws -> ArtifactReference {
        let url = projectRoot.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try store.writeJSON(value, to: url, forProjectAt: projectRoot)
        let legacyReference = try store.fileReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot,
            producedByRunID: runID
        )
        try store.upsertRunArtifact(legacyReference, runID: runID, inProjectAt: projectRoot)
        guard let reference = FoundationArtifactTypeProjection.reference(legacyReference) else {
            throw RunReviewServiceError.artifactReferenceProjectionFailed(
                path: path,
                message: "Planning feedback artifact has invalid integrity metadata."
            )
        }
        return reference
    }

    private func waiverEditVerificationGateResults(
        _ report: DesignFlowVerificationReport,
        sourceStepID: String
    ) -> [XcircuitePlanVerificationGateResult] {
        [
            XcircuitePlanVerificationGateResult(
                gateID: "post-waiver-edit-drc",
                required: true,
                status: report.drc.passed ? "passed" : "failed",
                sourceStepIDs: [sourceStepID],
                diagnostics: report.drc.passed ? [] : [
                    XcircuitePlanVerificationDiagnostic(
                        severity: "error",
                        code: "DRC_POST_WAIVER_EDIT_FAILED",
                        message: "DRC failed after waiver source edit with \(report.drc.violationCount) violation(s).",
                        gateID: "post-waiver-edit-drc"
                    ),
                ]
            ),
            XcircuitePlanVerificationGateResult(
                gateID: "post-waiver-edit-lvs",
                required: true,
                status: report.lvs.passed ? "passed" : "failed",
                sourceStepIDs: [sourceStepID],
                diagnostics: report.lvs.passed ? [] : [
                    XcircuitePlanVerificationDiagnostic(
                        severity: "error",
                        code: "LVS_POST_WAIVER_EDIT_FAILED",
                        message: "LVS failed after waiver source edit.",
                        gateID: "post-waiver-edit-lvs"
                    ),
                ]
            ),
            XcircuitePlanVerificationGateResult(
                gateID: "post-waiver-edit-layout-trust",
                required: true,
                status: (report.layoutTrust?.passed ?? true) ? "passed" : "failed",
                sourceStepIDs: [sourceStepID],
                diagnostics: (report.layoutTrust?.passed ?? true) ? [] : [
                    XcircuitePlanVerificationDiagnostic(
                        severity: "error",
                        code: "LAYOUT_TRUST_POST_WAIVER_EDIT_FAILED",
                        message: "Layout trust failed after waiver source edit.",
                        gateID: "post-waiver-edit-layout-trust"
                    ),
                ]
            ),
            XcircuitePlanVerificationGateResult(
                gateID: "post-waiver-edit-ready-for-pex",
                required: true,
                status: report.readyForPEX ? "passed" : "failed",
                sourceStepIDs: [sourceStepID],
                diagnostics: report.readyForPEX ? [] : [
                    XcircuitePlanVerificationDiagnostic(
                        severity: "error",
                        code: "POST_WAIVER_EDIT_READY_FOR_PEX_FAILED",
                        message: "The design is not ready for PEX after waiver source edit.",
                        gateID: "post-waiver-edit-ready-for-pex"
                    ),
                ]
            ),
        ]
    }

    private func safeIdentifierComponent(_ value: String) -> String {
        let hyphen: UnicodeScalar = "-"
        let underscore: UnicodeScalar = "_"
        let scalars = value.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == hyphen || scalar == underscore {
                return String(scalar)
            }
            return "-"
        }
        let component = scalars.joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return component.isEmpty ? "proposal" : component
    }

    private func waiverEditTargetReference(
        application: RunReviewWaiverEditApplication,
        projectRoot: URL
    ) throws -> ArtifactReference {
        let targetURL = try waiverEditTargetURL(path: application.targetPath, projectRoot: projectRoot)
        let hasher = XcircuiteHasher()
        let legacy = XcircuiteFileReference(
            path: application.targetPath,
            kind: .other,
            format: fileFormat(for: application.targetPath),
            sha256: hasher.sha256(data: try Data(contentsOf: targetURL)),
            byteCount: try hasher.byteCount(fileAt: targetURL)
        )
        guard let reference = FoundationArtifactTypeProjection.reference(legacy) else {
            throw RunReviewServiceError.artifactReferenceProjectionFailed(
                path: application.targetPath,
                message: "Waiver edit target has invalid integrity metadata."
            )
        }
        return reference
    }

    private func projectRelativePath(for url: URL, projectRoot: URL) throws -> String {
        let rootPath = normalizedPath(projectRoot.standardizedFileURL.path(percentEncoded: false))
        let path = normalizedPath(url.standardizedFileURL.path(percentEncoded: false))
        if let relative = relativePath(path: path, rootPath: rootPath) {
            return relative
        }

        let resolvedRootPath = normalizedPath(
            projectRoot.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        )
        let resolvedPath = normalizedPath(
            url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        )
        if let relative = relativePath(path: resolvedPath, rootPath: resolvedRootPath) {
            return relative
        }

        throw RunReviewServiceError.waiverEditVerificationArtifactEscapesProject(
            path: url.path(percentEncoded: false)
        )
    }

    private func relativePath(path: String, rootPath: String) -> String? {
        guard path != rootPath, path.hasPrefix(rootPath + "/") else {
            return nil
        }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func normalizedPath(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else {
            return path
        }
        return String(path.dropLast())
    }

    private func sourceReferenceMetadataValue(
        _ source: RunReviewWaiverSourceReference
    ) -> XcircuiteJSONValue {
        var value: [String: XcircuiteJSONValue] = [
            "waiverID": .string(source.waiverID),
            "path": .string(source.path),
            "reason": .string(source.reason),
        ]
        if let lineStart = source.lineStart {
            value["lineStart"] = .number(Double(lineStart))
        }
        if let lineEnd = source.lineEnd {
            value["lineEnd"] = .number(Double(lineEnd))
        }
        if let ruleID = source.ruleID {
            value["ruleID"] = .string(ruleID)
        }
        if let diagnosticID = source.diagnosticID {
            value["diagnosticID"] = .string(diagnosticID)
        }
        return .object(value)
    }

    private func applyEdit(
        proposal: RunReviewWaiverEditProposal,
        projectRoot: URL
    ) throws -> AppliedWaiverEdit {
        let targetURL = try waiverEditTargetURL(path: proposal.targetPath, projectRoot: projectRoot)
        let beforeData = try Data(contentsOf: targetURL)
        let afterData: Data
        switch proposal.operation {
        case "remove-json-object":
            afterData = try removingWaiverObject(proposal: proposal, from: beforeData)
        case "replace-file":
            guard let replacementText = proposal.replacementText else {
                throw RunReviewServiceError.waiverEditMissingReplacementText(proposalID: proposal.proposalID)
            }
            afterData = Data(replacementText.utf8)
        default:
            throw RunReviewServiceError.waiverEditUnsupportedOperation(operation: proposal.operation)
        }
        guard afterData != beforeData else {
            throw RunReviewServiceError.waiverEditNoChange(proposalID: proposal.proposalID)
        }

        let hasher = XcircuiteHasher()
        let beforeLegacyReference = XcircuiteFileReference(
            path: proposal.targetPath,
            kind: .other,
            format: fileFormat(for: proposal.targetPath),
            sha256: hasher.sha256(data: beforeData),
            byteCount: Int64(beforeData.count)
        )
        try afterData.write(to: targetURL, options: .atomic)
        let afterLegacyReference = XcircuiteFileReference(
            path: proposal.targetPath,
            kind: .other,
            format: fileFormat(for: proposal.targetPath),
            sha256: hasher.sha256(data: afterData),
            byteCount: Int64(afterData.count)
        )
        guard let beforeReference = FoundationArtifactTypeProjection.reference(beforeLegacyReference),
              let afterReference = FoundationArtifactTypeProjection.reference(afterLegacyReference) else {
            throw RunReviewServiceError.artifactReferenceProjectionFailed(
                path: proposal.targetPath,
                message: "Waiver edit artifact has invalid integrity metadata."
            )
        }
        return AppliedWaiverEdit(beforeReference: beforeReference, afterReference: afterReference)
    }

    private func waiverEditTargetURL(path: String, projectRoot: URL) throws -> URL {
        let reference = XcircuiteFileReference(
            path: path,
            kind: .other,
            format: fileFormat(for: path)
        )
        let verifier = XcircuiteFileReferenceVerifier()
        guard let targetURL = verifier.resolvedURL(for: reference, projectRoot: projectRoot) else {
            throw RunReviewServiceError.unsafeWaiverEditTargetPath(path: path)
        }
        let targetPath = targetURL.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetPath, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw RunReviewServiceError.waiverEditTargetMissing(path: path)
        }
        guard verifier.resolvedURL(for: reference, projectRoot: projectRoot) != nil else {
            throw RunReviewServiceError.unsafeWaiverEditTargetPath(path: path)
        }
        return targetURL
    }

    private func removingWaiverObject(
        proposal: RunReviewWaiverEditProposal,
        from data: Data
    ) throws -> Data {
        guard let waiverID = proposal.waiverID else {
            throw RunReviewServiceError.waiverEditMissingWaiverID(proposalID: proposal.proposalID)
        }
        let value = try JSONDecoder().decode(XcircuiteJSONValue.self, from: data)
        var removed = false
        let edited = removeWaiverObject(withID: waiverID, from: value, removed: &removed)
        guard removed else {
            throw RunReviewServiceError.waiverEditNoChange(proposalID: proposal.proposalID)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(edited)
    }

    private func removeWaiverObject(
        withID waiverID: String,
        from value: XcircuiteJSONValue,
        removed: inout Bool
    ) -> XcircuiteJSONValue {
        switch value {
        case .array(let values):
            return .array(values.compactMap { child in
                if isWaiverObject(child, waiverID: waiverID) {
                    removed = true
                    return nil
                }
                return removeWaiverObject(withID: waiverID, from: child, removed: &removed)
            })
        case .object(let object):
            var edited = object
            if edited.removeValue(forKey: waiverID) != nil {
                removed = true
            }
            for key in Array(edited.keys) {
                if let child = edited[key] {
                    edited[key] = removeWaiverObject(withID: waiverID, from: child, removed: &removed)
                }
            }
            return .object(edited)
        case .null, .bool, .number, .string:
            return value
        }
    }

    private func isWaiverObject(
        _ value: XcircuiteJSONValue,
        waiverID: String
    ) -> Bool {
        guard case .object(let object) = value else {
            return false
        }
        return object["waiverID"] == .string(waiverID)
            || object["id"] == .string(waiverID)
    }

    private func fileFormat(for path: String) -> XcircuiteFileFormat {
        path.lowercased().hasSuffix(".json") ? .json : .text
    }

    private func waiverArtifactURL(for artifact: FlowRunReviewArtifact, projectRoot: URL) -> URL {
        if artifact.path.hasPrefix("/") {
            URL(filePath: artifact.path)
        } else {
            projectRoot.appending(path: artifact.path)
        }
    }

    private func latestDesignSpecArtifact(
        in artifacts: [FlowRunReviewArtifact]
    ) -> FlowRunReviewArtifact? {
        artifacts.last {
            $0.format == .json
                && ($0.artifactID == "design-spec" || $0.path.hasSuffix("design-spec.json"))
        }
    }

    private func latestLayoutDocumentArtifact(
        in artifacts: [FlowRunReviewArtifact]
    ) -> FlowRunReviewArtifact? {
        artifacts.last {
            $0.kind == .layout
                && $0.format == .json
                && (
                    $0.artifactID == "layout-document"
                        || $0.artifactID == "drc-layout"
                        || $0.artifactID?.hasSuffix("-layout") == true
                        || $0.path.hasSuffix("layout-document.json")
                )
        }
    }

    private func latestDesignUnitArtifact(
        in artifacts: [FlowRunReviewArtifact]
    ) -> FlowRunReviewArtifact? {
        artifacts.last {
            $0.format == .json
                && ($0.artifactID == "design-unit" || $0.path.hasSuffix("design-unit.json"))
        }
    }

    private func existingVerificationInputURL(
        for artifact: FlowRunReviewArtifact,
        projectRoot: URL
    ) throws -> URL {
        let url = waiverArtifactURL(for: artifact, projectRoot: projectRoot)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw RunReviewServiceError.waiverEditVerificationInputMissing(path: artifact.path)
        }
        return url
    }
}
