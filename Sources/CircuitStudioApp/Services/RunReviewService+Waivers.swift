import DesignFlowKernel
import Foundation
import CircuiteFoundation
import CircuiteFoundationCrypto
import Xcircuite

extension RunReviewService {
    public func decideWaiverReview(
        runID: String,
        waiverReviewID: String,
        decision: RunReviewWaiverDecisionValue,
        reviewer: String,
        note: String = "",
        projectRoot: URL
    ) async throws -> FlowRunActionRecord {
        let store = try workspaceStore(projectRoot: projectRoot)
        let loader = configuredLedgerLoader(store: store)
        let reviewLoader = configuredReviewLedgerLoader(store: store)
        let bundler = configuredReviewBundler(store: store, loader: reviewLoader)
        let ledger = try await loader.loadRunLedger(runID: runID)
        let bundle = try await bundler.makeReviewBundle(
            runID: runID,
            workspaceID: try await workspaceID(store: store)
        )
        let summary = try await waiverReview(
            bundle: bundle,
            actions: ledger.actions,
            artifactReader: store
        )
        guard let item = summary.items.first(where: { $0.waiverReviewID == waiverReviewID }) else {
            throw RunReviewServiceError.waiverReviewNotFound(waiverReviewID: waiverReviewID)
        }

        let record = FlowRunActionRecord(
            actionID: "waiver-review-\(UUID().uuidString)",
            runID: runID,
            stageID: item.stageID,
            actor: FlowRunActor(kind: .human, identifier: reviewer),
            actionKind: FlowRunReviewDecisionKind.waiver.rawValue,
            status: .succeeded,
            inputs: [fileReference(from: item.artifact)],
            context: FlowRunActionContext(
                reviewDecision: FlowRunActionContext.ReviewDecision(
                    kind: .waiver,
                    decision: decision.rawValue,
                    targetID: item.waiverReviewID,
                    targetPath: item.artifact.binding.circuitStudioPresentationPath,
                    reason: note
                )
            )
        )
        try await store.appendRunAction(record)
        return record
    }

    public func recordWaiverEditProposalSelection(
        runID: String,
        waiverReviewID: String,
        proposalID: String,
        reviewer: String,
        note: String = "",
        projectRoot: URL
    ) async throws -> FlowRunActionRecord {
        let store = try workspaceStore(projectRoot: projectRoot)
        let loader = configuredLedgerLoader(store: store)
        let reviewLoader = configuredReviewLedgerLoader(store: store)
        let bundler = configuredReviewBundler(store: store, loader: reviewLoader)
        let ledger = try await loader.loadRunLedger(runID: runID)
        let bundle = try await bundler.makeReviewBundle(
            runID: runID,
            workspaceID: try await workspaceID(store: store)
        )
        let summary = try await waiverReview(
            bundle: bundle,
            actions: ledger.actions,
            artifactReader: store
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

        let record = FlowRunActionRecord(
            actionID: "waiver-edit-proposal-selection-\(UUID().uuidString)",
            runID: runID,
            stageID: item.stageID,
            actor: FlowRunActor(kind: .human, identifier: reviewer),
            actionKind: RunReviewWaiverEditProposalSelection.actionKind,
            status: .succeeded,
            inputs: [fileReference(from: item.artifact)],
            context: FlowRunActionContext(
                reviewDecision: FlowRunActionContext.ReviewDecision(
                    kind: .waiver,
                    decision: "selected",
                    targetID: item.waiverReviewID,
                    targetPath: proposal.proposalID,
                    reason: note
                )
            )
        )
        try await store.appendRunAction(record)
        return record
    }

    public func applyWaiverEditProposal(
        runID: String,
        waiverReviewID: String,
        proposalID: String,
        reviewer: String,
        note: String = "",
        projectRoot: URL
    ) async throws -> FlowRunActionRecord {
        let store = try workspaceStore(projectRoot: projectRoot)
        let loader = configuredLedgerLoader(store: store)
        let reviewLoader = configuredReviewLedgerLoader(store: store)
        let bundler = configuredReviewBundler(store: store, loader: reviewLoader)
        let ledger = try await loader.loadRunLedger(runID: runID)
        let bundle = try await bundler.makeReviewBundle(
            runID: runID,
            workspaceID: try await workspaceID(store: store)
        )
        let summary = try await waiverReview(
            bundle: bundle,
            actions: ledger.actions,
            artifactReader: store
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

        let appliedEdit = try prepareEdit(
            proposal: proposal,
            runID: runID,
            projectRoot: projectRoot,
            store: store
        )
        let record = FlowRunActionRecord(
            actionID: "waiver-edit-proposal-application-\(UUID().uuidString)",
            runID: runID,
            stageID: item.stageID,
            actor: FlowRunActor(kind: .human, identifier: reviewer),
            actionKind: RunReviewWaiverEditApplication.actionKind,
            status: .succeeded,
            inputs: [fileReference(from: item.artifact)],
            outputs: [
                appliedEdit.beforeReference,
                appliedEdit.afterReference,
            ],
            context: FlowRunActionContext(
                artifactEdit: FlowRunActionContext.ArtifactEdit(
                    proposalID: proposal.proposalID,
                    targetPath: proposal.targetPath,
                    operation: proposal.operation
                ),
                reviewDecision: FlowRunActionContext.ReviewDecision(
                    kind: .waiver,
                    decision: proposal.operation,
                    targetID: item.waiverReviewID,
                    targetPath: proposal.proposalID,
                    reason: note
                )
            )
        )
        _ = try await store.appendActionArtifacts(
            appliedEdit.artifacts,
            action: record,
            replacingProjectArtifactAt: appliedEdit.targetPath,
            expectedContent: appliedEdit.beforeData,
            replacementContent: appliedEdit.afterData
        )
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
    ) async throws -> FlowRunActionRecord {
        let store = try workspaceStore(projectRoot: projectRoot)
        let loader = configuredLedgerLoader(store: store)
        let reviewLoader = configuredReviewLedgerLoader(store: store)
        let bundler = configuredReviewBundler(store: store, loader: reviewLoader)
        let ledger = try await loader.loadRunLedger(runID: runID)
        let bundle = try await bundler.makeReviewBundle(
            runID: runID,
            workspaceID: try await workspaceID(store: store)
        )
        let summary = try await waiverReview(
            bundle: bundle,
            actions: ledger.actions,
            artifactReader: store
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

        let verificationSourcePath = try projectRelativePath(
            for: verificationReportURL,
            projectRoot: projectRoot
        )
        let verificationData = try Data(contentsOf: verificationReportURL, options: [.mappedIfSafe])
        let retainedVerificationReport = try JSONDecoder().decode(
            DesignFlowVerificationReport.self,
            from: verificationData
        )
        guard retainedVerificationReport == verificationReport else {
            throw RunReviewServiceError.waiverEditVerificationReportMismatch(
                path: verificationSourcePath
            )
        }
        let safeProposalID = safeIdentifierComponent(proposalID)
        let verificationArtifact = try prepareWaiverEditEvidence(
            content: verificationData,
            artifactIDPrefix: "post-waiver-edit-physical-verification",
            fileNamePrefix: "verification",
            kind: .report,
            format: .json,
            safeProposalID: safeProposalID,
            runID: runID,
            store: store
        )
        let layoutTrustArtifact: XcircuitePreparedArtifact?
        if let layoutTrustReportURL {
            _ = try projectRelativePath(for: layoutTrustReportURL, projectRoot: projectRoot)
            let layoutTrustData = try Data(contentsOf: layoutTrustReportURL, options: [.mappedIfSafe])
            layoutTrustArtifact = try prepareWaiverEditEvidence(
                content: layoutTrustData,
                artifactIDPrefix: "post-waiver-edit-layout-trust",
                fileNamePrefix: "layout-trust",
                kind: .report,
                format: .json,
                safeProposalID: safeProposalID,
                runID: runID,
                store: store
            )
        } else {
            layoutTrustArtifact = nil
        }
        let targetReference = try waiverEditTargetReference(
            application: application,
            actions: ledger.actions
        )
        let targetBinding = try exactLedgerBinding(
            for: targetReference,
            in: ledger.artifacts,
            path: application.targetPath
        )
        let feedback = try await prepareWaiverEditPlanningFeedback(
            runID: runID,
            waiverReviewID: item.waiverReviewID,
            proposalID: proposalID,
            application: application,
            targetBinding: targetBinding,
            verificationReport: verificationReport,
            verificationBinding: verificationArtifact.binding,
            layoutTrustBinding: layoutTrustArtifact?.binding,
            actions: ledger.actions,
            store: store
        )

        let supplementaryReferences = [layoutTrustArtifact?.reference]
            .compactMap { $0 }
        let record = FlowRunActionRecord(
            actionID: "waiver-edit-proposal-verification-\(UUID().uuidString)",
            runID: runID,
            stageID: item.stageID,
            actor: FlowRunActor(kind: .human, identifier: reviewer),
            actionKind: RunReviewWaiverEditVerification.actionKind,
            status: .succeeded,
            inputs: [
                fileReference(from: item.artifact),
                targetReference,
            ],
            outputs: [
                verificationArtifact.reference,
                feedback.candidatePlanRef,
                feedback.planVerificationRef,
            ] + supplementaryReferences + [feedback.rejectedPlansRef].compactMap { $0 },
            context: FlowRunActionContext(
                iterationID: application.actionRecordID,
                artifactEdit: FlowRunActionContext.ArtifactEdit(
                    proposalID: proposalID,
                    targetPath: application.targetPath,
                    operation: application.operation
                ),
                reviewDecision: FlowRunActionContext.ReviewDecision(
                    kind: .waiver,
                    decision: feedback.status,
                    targetID: item.waiverReviewID,
                    targetPath: proposalID,
                    reason: note
                )
            )
        )
        _ = try await store.appendActionArtifacts(
            [verificationArtifact] + [layoutTrustArtifact].compactMap { $0 } + feedback.artifacts,
            action: record
        )
        return record
    }

    public func waiverEditVerificationContext(
        runID: String,
        projectRoot: URL
    ) async throws -> RunReviewWaiverEditVerificationContext {
        let review = try await loadRun(runID: runID, projectRoot: projectRoot)
        return try await waiverEditVerificationContext(
            review: review,
            projectRoot: projectRoot
        )
    }

    public func waiverEditVerificationContext(
        review: RunReview,
        projectRoot: URL
    ) async throws -> RunReviewWaiverEditVerificationContext {
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
        let context = try await waiverEditVerificationContext(runID: runID, projectRoot: projectRoot)
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
        let context = try await waiverEditVerificationContext(runID: runID, projectRoot: projectRoot)
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
        actions: [FlowRunActionRecord],
        artifactReader: any XcircuiteArtifactBindingReading
    ) async throws -> RunReviewWaiverSummary {
        let decisions = waiverDecisionsByReviewID(from: actions)
        let editProposalSelections = waiverEditProposalSelectionsByReviewID(from: actions)
        let editApplications = try waiverEditApplicationsByReviewID(
            from: actions,
            artifacts: bundle.artifacts
        )
        let editVerifications = try await waiverEditVerificationsByReviewID(
            from: actions,
            artifacts: bundle.artifacts,
            artifactReader: artifactReader
        )
        var items: [RunReviewWaiverItem] = []
        var decodeIssues: [RunReviewArtifactDecodeIssue] = []

        for artifact in bundle.artifacts where artifact.binding.format == .json {
            switch waiverArtifactKind(for: artifact) {
            case .drc:
                await appendWaiverItem(
                    artifact: artifact,
                    artifactReader: artifactReader,
                    decisions: decisions,
                    editProposalSelections: editProposalSelections,
                    editApplications: editApplications,
                    editVerifications: editVerifications,
                    decodeIssues: &decodeIssues,
                    items: &items,
                    makeItem: drcWaiverItem
                )
            case .lvs:
                await appendWaiverItem(
                    artifact: artifact,
                    artifactReader: artifactReader,
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
                return left.artifact.binding.circuitStudioPresentationPath < right.artifact.binding.circuitStudioPresentationPath
            },
            decodeIssues: decodeIssues
        )
    }

    private func appendWaiverItem<Document: Decodable>(
        artifact: FlowRunReviewArtifact,
        artifactReader: any XcircuiteArtifactBindingReading,
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
    ) async {
        do {
            try validateWaiverArtifactIntegrity(artifact)
            let data = try await artifactReader.loadArtifactContent(for: artifact.binding)
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
                    artifactRole: artifact.purpose.rawValue,
                    artifactPath: artifact.binding.circuitStudioPresentationPath,
                    message: error.localizedDescription
                )
            )
        }
    }

    private func validateWaiverArtifactIntegrity(_ artifact: FlowRunReviewArtifact) throws {
        guard let integrity = artifact.integrity else {
            throw RunReviewServiceError.waiverArtifactIntegrityUnverified(
                path: artifact.binding.circuitStudioPresentationPath,
                status: "missing",
                message: "Artifact integrity was not recorded."
            )
        }
        guard integrity.status == .verified else {
            throw RunReviewServiceError.waiverArtifactIntegrityUnverified(
                path: artifact.binding.circuitStudioPresentationPath,
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
        let artifactID = artifact.binding.logicalID
        let path = artifact.binding.circuitStudioPresentationPath.lowercased()
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
        "\(domain.lowercased())-waiver:\(artifact.binding.circuitStudioPresentationPath)"
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

    private func fileReference(from artifact: FlowRunReviewArtifact) -> ArtifactReference {
        artifact.reference
    }

    private func prepareWaiverEditPlanningFeedback(
        runID: String,
        waiverReviewID: String,
        proposalID: String,
        application: RunReviewWaiverEditApplication,
        targetBinding: FlowArtifactBinding,
        verificationReport: DesignFlowVerificationReport,
        verificationBinding: FlowArtifactBinding,
        layoutTrustBinding: FlowArtifactBinding?,
        actions: [FlowRunActionRecord],
        store: XcircuiteWorkspaceStore
    ) async throws -> WaiverEditPlanningFeedback {
        let safeProposalID = safeIdentifierComponent(proposalID)
        let verificationReference = verificationBinding.reference
        let verificationToken = verificationReference.digest.hexadecimalValue
        let planID = "\(runID)-waiver-edit-\(safeProposalID)"
        let problemID = "\(runID)-waiver-edit-problem-\(safeProposalID)"
        let basePath = "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/planning/waiver-edit-feedback/\(safeProposalID)/verifications/\(verificationToken)"
        let candidatePlanPath = "\(basePath)/candidate-plan.json"
        let planVerificationPath = "\(basePath)/plan-verification.json"
        let gateIDs = [
            "post-waiver-edit-drc",
            "post-waiver-edit-lvs",
            "post-waiver-edit-layout-trust",
            "post-waiver-edit-ready-for-pex",
        ]
        let stepID = "apply-waiver-edit-\(safeProposalID)"
        let candidatePlan = XcircuitePlanningCandidateDraft(
            planID: planID,
            problemID: problemID,
            runID: runID,
            strategy: "waiver-edit-post-verification-feedback",
            executionReadiness: "executed",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "waiver-review",
                kind: "waiver-review",
                metadata: [
                    "waiverReviewID": .text(waiverReviewID),
                    "proposalID": .text(proposalID),
                    "applicationActionID": .text(application.actionRecordID),
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
                        "proposalID": .text(proposalID),
                        "targetPath": .text(application.targetPath),
                        "operation": .text(application.operation),
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
        let candidatePlanArtifact = try preparePlanningFeedbackArtifact(
            candidatePlan,
            path: candidatePlanPath,
            artifactID: "post-waiver-edit-candidate-plan-\(safeProposalID)-\(verificationToken)",
            store: store
        )
        let candidatePlanRef = candidatePlanArtifact.reference

        let gateResults = waiverEditVerificationGateResults(verificationReport, sourceStepID: stepID)
        let diagnostics = gateResults.flatMap(\.diagnostics)
        let failedGateIDs = gateResults
            .filter { $0.status == "failed" }
            .map(\.gateID)
        let accepted = verificationReport.readyForPEX && failedGateIDs.isEmpty
        let artifactBindings = [targetBinding, verificationBinding]
            + [layoutTrustBinding].compactMap { $0 }
        let artifactRefs = artifactBindings.map(\.reference)
        let planVerification = XcircuitePlanVerification(
            problemID: problemID,
            planID: planID,
            runID: runID,
            verificationMode: "post-waiver-edit",
            candidatePlanRef: candidatePlanRef,
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
                    producedArtifactRefs: artifactRefs
                ),
            ],
            gateResults: gateResults,
            artifactBindings: artifactBindings,
            diagnostics: diagnostics,
            accepted: accepted,
            nextActions: accepted ? [] : failedGateIDs.map { "repair-verification-gate:\($0)" }
        )
        let planVerificationArtifact = try preparePlanningFeedbackArtifact(
            planVerification,
            path: planVerificationPath,
            artifactID: "post-waiver-edit-plan-verification-\(safeProposalID)-\(verificationToken)",
            store: store
        )
        let planVerificationRef = planVerificationArtifact.reference

        guard !accepted else {
            return WaiverEditPlanningFeedback(
                status: "accepted-no-rejected-plan",
                candidatePlanRef: candidatePlanRef,
                planVerificationRef: planVerificationRef,
                rejectedPlansRef: nil,
                artifacts: [candidatePlanArtifact, planVerificationArtifact]
            )
        }

        let rejectedRecord = XcircuiteRejectedPlanRecord(
            rejectionID: "\(planID)-rejected-\(verificationToken)",
            runID: runID,
            problemID: problemID,
            planID: planID,
            verificationMode: "post-waiver-edit",
            status: "rejected",
            sourceParameterCandidateIDs: [],
            failedStepIDs: [stepID],
            failedGateIDs: failedGateIDs,
            candidatePlanRef: candidatePlanRef,
            planVerificationRef: planVerificationRef,
            artifactRefs: artifactRefs,
            diagnostics: diagnostics,
            nextActions: failedGateIDs.map { "repair-verification-gate:\($0)" }
        )
        let rejectedPlansArtifact = try await prepareRejectedPlanSnapshot(
            rejectedRecord,
            runID: runID,
            actions: actions,
            store: store
        )
        return WaiverEditPlanningFeedback(
            status: "rejected-plan-recorded",
            candidatePlanRef: candidatePlanRef,
            planVerificationRef: planVerificationRef,
            rejectedPlansRef: rejectedPlansArtifact.reference,
            artifacts: [
                candidatePlanArtifact,
                planVerificationArtifact,
                rejectedPlansArtifact,
            ]
        )
    }

    private func preparePlanningFeedbackArtifact<T: Encodable & Sendable>(
        _ value: T,
        path: String,
        artifactID: String,
        store: XcircuiteWorkspaceStore
    ) throws -> XcircuitePreparedArtifact {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        let reference = try ArtifactReference(
            digest: try SHA256ContentDigester().digest(data: data, using: .sha256),
            byteCount: UInt64(data.count),
            descriptor: ArtifactDescriptor(role: .output, kind: .other, format: .json)
        )
        let binding = try FlowArtifactBinding(
            logicalID: artifactID,
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: store.artifactRootID,
                relativePath: try artifactRelativePath(path)
            )
        )
        return XcircuitePreparedArtifact(binding: binding, content: data)
    }

    private func prepareRejectedPlanSnapshot(
        _ record: XcircuiteRejectedPlanRecord,
        runID: String,
        actions: [FlowRunActionRecord],
        store: XcircuiteWorkspaceStore
    ) async throws -> XcircuitePreparedArtifact {
        let priorReference = actions.reversed()
            .lazy
            .flatMap(\.outputs)
            .first {
                $0.artifactID == XcircuitePlanningArtifactStore.rejectedPlansArtifactID
            }
        var content = Data()
        if let priorReference {
            let ledger = try await store.loadRunLedger(runID: runID)
            let priorBinding = try exactLedgerBinding(
                for: priorReference,
                in: ledger.artifacts,
                path: XcircuitePlanningArtifactStore.rejectedPlansArtifactID
            )
            content = try await store.loadArtifactContent(for: priorBinding)
            let priorPath = priorBinding.circuitStudioPresentationPath
            for (index, line) in String(decoding: content, as: UTF8.self)
                .split(separator: "\n")
                .enumerated() {
                let existing: XcircuiteRejectedPlanRecord
                do {
                    existing = try JSONDecoder().decode(
                        XcircuiteRejectedPlanRecord.self,
                        from: Data(line.utf8)
                    )
                } catch {
                    throw RunReviewServiceError.invalidArtifactReference(
                        path: priorPath,
                        message: "Rejected-plan snapshot contains invalid JSON at line \(index + 1)."
                    )
                }
                guard existing.rejectionID != record.rejectionID else {
                    throw RunReviewServiceError.invalidArtifactReference(
                        path: priorPath,
                        message: "Rejected-plan snapshot contains duplicate rejection ID \(record.rejectionID)."
                    )
                }
            }
        }
        if !content.isEmpty, content.last != 0x0A {
            content.append(0x0A)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        content.append(try encoder.encode(record))
        content.append(0x0A)
        let digest = try SHA256ContentDigester().digest(data: content, using: .sha256)
        let digestToken = String(digest.hexadecimalValue.prefix(16))
        let path = "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/planning/rejected-plan-snapshots/\(digestToken).jsonl"
        let reference = try ArtifactReference(
            digest: digest,
            byteCount: UInt64(content.count),
            descriptor: ArtifactDescriptor(role: .output, kind: .other, format: .text)
        )
        let binding = try FlowArtifactBinding(
            logicalID: XcircuitePlanningArtifactStore.rejectedPlansArtifactID,
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: store.artifactRootID,
                relativePath: try artifactRelativePath(path)
            )
        )
        return XcircuitePreparedArtifact(binding: binding, content: content)
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
                status: report.layoutTrust?.passed == true ? "passed" : "failed",
                sourceStepIDs: [sourceStepID],
                diagnostics: report.layoutTrust?.passed == true ? [] : [
                    XcircuitePlanVerificationDiagnostic(
                        severity: "error",
                        code: report.layoutTrust == nil
                            ? "LAYOUT_TRUST_POST_WAIVER_EDIT_MISSING"
                            : "LAYOUT_TRUST_POST_WAIVER_EDIT_FAILED",
                        message: report.layoutTrust == nil
                            ? "Layout trust evidence is missing after waiver source edit."
                            : "Layout trust failed after waiver source edit.",
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
        actions: [FlowRunActionRecord]
    ) throws -> ArtifactReference {
        guard let applicationAction = actions.first(where: {
            $0.actionID == application.actionRecordID
                && $0.actionKind == RunReviewWaiverEditApplication.actionKind
                && $0.context.artifactEdit?.proposalID == application.proposalID
                && $0.context.artifactEdit?.targetPath == application.targetPath
                && $0.context.artifactEdit?.operation == application.operation
        }) else {
            throw RunReviewServiceError.waiverEditApplicationNotFound(
                waiverReviewID: application.waiverReviewID,
                proposalID: application.proposalID
            )
        }
        let matches = applicationAction.outputs.filter {
            $0.digest.hexadecimalValue.caseInsensitiveCompare(
                    application.afterSHA256
                ) == .orderedSame
        }
        guard matches.count == 1, let reference = matches.first else {
            throw RunReviewServiceError.invalidArtifactReference(
                path: application.targetPath,
                message: "The waiver edit action does not retain one exact output artifact reference."
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

    private func prepareEdit(
        proposal: RunReviewWaiverEditProposal,
        runID: String,
        projectRoot: URL,
        store: XcircuiteWorkspaceStore
    ) throws -> AppliedWaiverEdit {
        let targetURL = try waiverEditTargetURL(path: proposal.targetPath, projectRoot: projectRoot)
        let beforeData = try Data(contentsOf: targetURL, options: [.mappedIfSafe])
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

        let safeProposalID = safeIdentifierComponent(proposal.proposalID)
        let format = fileFormat(for: proposal.targetPath)
        let beforeArtifact = try prepareWaiverEditEvidence(
            content: beforeData,
            artifactIDPrefix: "waiver-edit-before",
            fileNamePrefix: "before",
            kind: .other,
            format: format,
            safeProposalID: safeProposalID,
            runID: runID,
            store: store
        )
        let afterArtifact = try prepareWaiverEditEvidence(
            content: afterData,
            artifactIDPrefix: "waiver-edit-after",
            fileNamePrefix: "after",
            kind: .other,
            format: format,
            safeProposalID: safeProposalID,
            runID: runID,
            store: store
        )
        return AppliedWaiverEdit(
            targetPath: proposal.targetPath,
            beforeData: beforeData,
            afterData: afterData,
            beforeReference: beforeArtifact.reference,
            afterReference: afterArtifact.reference,
            artifacts: [beforeArtifact, afterArtifact]
        )
    }

    private func prepareWaiverEditEvidence(
        content: Data,
        artifactIDPrefix: String,
        fileNamePrefix: String,
        kind: ArtifactKind,
        format: ArtifactFormat,
        safeProposalID: String,
        runID: String,
        store: XcircuiteWorkspaceStore
    ) throws -> XcircuitePreparedArtifact {
        let digest = try SHA256ContentDigester().digest(data: content, using: .sha256)
        let digestToken = String(digest.hexadecimalValue.prefix(16))
        let fileExtension = format == .json ? "json" : "data"
        let path = "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/review/waiver-edits/\(safeProposalID)/\(fileNamePrefix)-\(digestToken).\(fileExtension)"
        let logicalID = "\(artifactIDPrefix)-\(safeProposalID)-\(digestToken)"
        let reference = try ArtifactReference(
            digest: digest,
            byteCount: UInt64(content.count),
            descriptor: ArtifactDescriptor(role: .output, kind: kind, format: format)
        )
        let binding = try FlowArtifactBinding(
            logicalID: logicalID,
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: store.artifactRootID,
                relativePath: try artifactRelativePath(path)
            )
        )
        return XcircuitePreparedArtifact(binding: binding, content: content)
    }

    private func artifactRelativePath(_ path: String) throws -> ArtifactRelativePath {
        try ArtifactRelativePath(
            segments: path.split(separator: "/").map(String.init)
        )
    }

    private func exactLedgerBinding(
        for reference: ArtifactReference,
        in artifacts: [FlowArtifactBinding],
        path: String
    ) throws -> FlowArtifactBinding {
        let matches = Set(artifacts.filter { $0.reference == reference })
        guard matches.count == 1, let binding = matches.first else {
            throw RunReviewServiceError.invalidArtifactReference(
                path: path,
                message: matches.isEmpty
                    ? "Artifact availability is missing from the run ledger."
                    : "Artifact identity resolves to multiple run-ledger availability bindings."
            )
        }
        return binding
    }

    private func waiverEditTargetURL(path: String, projectRoot: URL) throws -> URL {
        let targetURL = try XcircuiteWorkspaceLayout(projectRoot: projectRoot)
            .url(forProjectRelativePath: path)
        let targetPath = targetURL.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetPath, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw RunReviewServiceError.waiverEditTargetMissing(path: path)
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
        let value = try JSONDecoder().decode(WaiverDocumentValue.self, from: data)
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
        from value: WaiverDocumentValue,
        removed: inout Bool
    ) -> WaiverDocumentValue {
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
        _ value: WaiverDocumentValue,
        waiverID: String
    ) -> Bool {
        guard case .object(let object) = value else {
            return false
        }
        return object["waiverID"] == .string(waiverID)
            || object["id"] == .string(waiverID)
    }

    private func fileFormat(for path: String) -> ArtifactFormat {
        path.lowercased().hasSuffix(".json") ? .json : .text
    }

    private func waiverArtifactURL(for artifact: FlowRunReviewArtifact, projectRoot: URL) -> URL {
        if artifact.binding.circuitStudioPresentationPath.hasPrefix("/") {
            URL(filePath: artifact.binding.circuitStudioPresentationPath)
        } else {
            projectRoot.appending(path: artifact.binding.circuitStudioPresentationPath)
        }
    }

    private func latestDesignSpecArtifact(
        in artifacts: [FlowRunReviewArtifact]
    ) -> FlowRunReviewArtifact? {
        artifacts.last {
            $0.binding.format == .json
                && ($0.binding.logicalID == "design-spec" || $0.binding.circuitStudioPresentationPath.hasSuffix("design-spec.json"))
        }
    }

    private func latestLayoutDocumentArtifact(
        in artifacts: [FlowRunReviewArtifact]
    ) -> FlowRunReviewArtifact? {
        artifacts.last {
            $0.binding.kind == .layout
                && $0.binding.format == .json
                && (
                    $0.binding.logicalID == "layout-document"
                        || $0.binding.logicalID == "drc-layout"
                        || $0.binding.logicalID.hasSuffix("-layout")
                        || $0.binding.circuitStudioPresentationPath.hasSuffix("layout-document.json")
                )
        }
    }

    private func latestDesignUnitArtifact(
        in artifacts: [FlowRunReviewArtifact]
    ) -> FlowRunReviewArtifact? {
        artifacts.last {
            $0.binding.format == .json
                && ($0.binding.logicalID == "design-unit" || $0.binding.circuitStudioPresentationPath.hasSuffix("design-unit.json"))
        }
    }

    private func existingVerificationInputURL(
        for artifact: FlowRunReviewArtifact,
        projectRoot: URL
    ) throws -> URL {
        let url = waiverArtifactURL(for: artifact, projectRoot: projectRoot)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw RunReviewServiceError.waiverEditVerificationInputMissing(path: artifact.binding.circuitStudioPresentationPath)
        }
        return url
    }
}
