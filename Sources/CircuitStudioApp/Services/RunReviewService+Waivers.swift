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
    ) async throws -> FlowRunActionRecord {
        let store = try workspaceStore(projectRoot: projectRoot)
        let loader = configuredLedgerLoader(store: store)
        let bundler = configuredReviewBundler(store: store, loader: loader)
        let ledger = try await loader.loadRunLedger(runID: runID)
        let bundle = try await bundler.makeReviewBundle(runID: runID, projectRoot: projectRoot)
        let summary = try waiverReview(
            bundle: bundle,
            actions: ledger.actions,
            projectRoot: projectRoot
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
            inputs: [try fileReference(from: item.artifact)],
            context: FlowRunActionContext(
                reviewDecision: FlowRunActionContext.ReviewDecision(
                    kind: .waiver,
                    decision: decision.rawValue,
                    targetID: item.waiverReviewID,
                    targetPath: item.artifact.path,
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
        let bundler = configuredReviewBundler(store: store, loader: loader)
        let ledger = try await loader.loadRunLedger(runID: runID)
        let bundle = try await bundler.makeReviewBundle(runID: runID, projectRoot: projectRoot)
        let summary = try waiverReview(
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

        let record = FlowRunActionRecord(
            actionID: "waiver-edit-proposal-selection-\(UUID().uuidString)",
            runID: runID,
            stageID: item.stageID,
            actor: FlowRunActor(kind: .human, identifier: reviewer),
            actionKind: RunReviewWaiverEditProposalSelection.actionKind,
            status: .succeeded,
            inputs: [try fileReference(from: item.artifact)],
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
        let bundler = configuredReviewBundler(store: store, loader: loader)
        let ledger = try await loader.loadRunLedger(runID: runID)
        let bundle = try await bundler.makeReviewBundle(runID: runID, projectRoot: projectRoot)
        let summary = try waiverReview(
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
        let record = FlowRunActionRecord(
            actionID: "waiver-edit-proposal-application-\(UUID().uuidString)",
            runID: runID,
            stageID: item.stageID,
            actor: FlowRunActor(kind: .human, identifier: reviewer),
            actionKind: RunReviewWaiverEditApplication.actionKind,
            status: .succeeded,
            inputs: [
                try fileReference(from: item.artifact),
                appliedEdit.beforeReference,
            ],
            outputs: [appliedEdit.afterReference],
            context: FlowRunActionContext(
                reviewDecision: FlowRunActionContext.ReviewDecision(
                    kind: .waiver,
                    decision: proposal.operation,
                    targetID: item.waiverReviewID,
                    targetPath: proposal.proposalID,
                    reason: note
                )
            )
        )
        try await store.appendRunAction(record)
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
        let bundler = configuredReviewBundler(store: store, loader: loader)
        let ledger = try await loader.loadRunLedger(runID: runID)
        let bundle = try await bundler.makeReviewBundle(runID: runID, projectRoot: projectRoot)
        let summary = try waiverReview(
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
        let feedback = try await recordWaiverEditPlanningFeedback(
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

        let supplementaryReferences = [layoutTrustReference, feedback.rejectedPlansRef]
            .compactMap { $0 }
        let record = FlowRunActionRecord(
            actionID: "waiver-edit-proposal-verification-\(UUID().uuidString)",
            runID: runID,
            stageID: item.stageID,
            actor: FlowRunActor(kind: .human, identifier: reviewer),
            actionKind: RunReviewWaiverEditVerification.actionKind,
            status: .succeeded,
            inputs: [
                try fileReference(from: item.artifact),
                targetReference,
            ],
            outputs: [
                verificationReference,
                feedback.candidatePlanRef,
                feedback.planVerificationRef,
            ] + supplementaryReferences,
            context: FlowRunActionContext(
                iterationID: application.actionRecordID,
                reviewDecision: FlowRunActionContext.ReviewDecision(
                    kind: .waiver,
                    decision: feedback.status,
                    targetID: item.waiverReviewID,
                    targetPath: proposalID,
                    reason: note
                )
            )
        )
        try await store.appendRunAction(record)
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
        projectRoot: URL
    ) throws -> RunReviewWaiverSummary {
        let decisions = waiverDecisionsByReviewID(from: actions)
        let editProposalSelections = waiverEditProposalSelectionsByReviewID(from: actions)
        let editApplications = waiverEditApplicationsByReviewID(from: actions)
        let editVerifications = try waiverEditVerificationsByReviewID(
            from: actions,
            projectRoot: projectRoot
        )
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

    private func fileReference(from artifact: FlowRunReviewArtifact) throws -> ArtifactReference {
        guard let digest = artifact.sha256,
              let byteCount = artifact.byteCount,
              byteCount >= 0 else {
            throw RunReviewServiceError.invalidArtifactReference(
                path: artifact.path,
                message: "Review artifact is missing verified integrity metadata."
            )
        }
        return ArtifactReference(
            id: try artifact.artifactID.map(ArtifactID.init(rawValue:)),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: artifact.path),
                role: .input,
                kind: artifact.kind,
                format: artifact.format
            ),
            digest: try ContentDigest(algorithm: .sha256, hexadecimalValue: digest),
            byteCount: UInt64(byteCount)
        )
    }

    private func projectFileReference(
        url: URL,
        projectRoot: URL,
        artifactID: String,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactReference {
        let path = try projectRelativePath(for: url, projectRoot: projectRoot)
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let byteCount = values.fileSize, byteCount >= 0 else {
            throw RunReviewServiceError.invalidArtifactReference(
                path: path,
                message: "Generated verification artifact has no valid byte count."
            )
        }
        return ArtifactReference(
            id: try ArtifactID(rawValue: artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: kind,
                format: format
            ),
            digest: try SHA256ContentDigester().digest(fileAt: url, using: .sha256),
            byteCount: UInt64(byteCount)
        )
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
    ) async throws -> WaiverEditPlanningFeedback {
        let store = try workspaceStore(projectRoot: projectRoot)
        let safeProposalID = safeIdentifierComponent(proposalID)
        let planID = "\(runID)-waiver-edit-\(safeProposalID)"
        let problemID = "\(runID)-waiver-edit-problem-\(safeProposalID)"
        let basePath = "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/planning/waiver-edit-feedback/\(safeProposalID)"
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
        let candidatePlanRef = try await writePlanningFeedbackArtifact(
            candidatePlan,
            path: candidatePlanPath,
            artifactID: "post-waiver-edit-candidate-plan-\(safeProposalID)",
            runID: runID,
            store: store
        )

        let gateResults = waiverEditVerificationGateResults(verificationReport, sourceStepID: stepID)
        let diagnostics = gateResults.flatMap(\.diagnostics)
        let failedGateIDs = gateResults
            .filter { $0.status == "failed" }
            .map(\.gateID)
        let accepted = verificationReport.readyForPEX && failedGateIDs.isEmpty
        let artifactRefs = [targetReference, verificationReference] + [layoutTrustReference].compactMap { $0 }
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
            artifactRefs: artifactRefs,
            diagnostics: diagnostics,
            accepted: accepted,
            nextActions: accepted ? [] : failedGateIDs.map { "repair-verification-gate:\($0)" }
        )
        let planVerificationRef = try await writePlanningFeedbackArtifact(
            planVerification,
            path: planVerificationPath,
            artifactID: "post-waiver-edit-plan-verification-\(safeProposalID)",
            runID: runID,
            store: store
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
            candidatePlanRef: candidatePlanRef,
            planVerificationRef: planVerificationRef,
            artifactRefs: artifactRefs,
            diagnostics: diagnostics,
            nextActions: failedGateIDs.map { "repair-verification-gate:\($0)" }
        )
        let rejectedPlansRef = try await XcircuitePlanningArtifactStore(workspaceStore: store).appendRejectedPlan(
            rejectedRecord,
            runID: runID,
            projectRoot: projectRoot
        )
        return WaiverEditPlanningFeedback(
            status: "rejected-plan-recorded",
            candidatePlanRef: candidatePlanRef,
            planVerificationRef: planVerificationRef,
            rejectedPlansRef: rejectedPlansRef
        )
    }

    private func writePlanningFeedbackArtifact<T: Encodable & Sendable>(
        _ value: T,
        path: String,
        artifactID: String,
        runID: String,
        store: XcircuiteWorkspaceStore
    ) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return try await store.persistArtifact(
            content: data,
            id: try ArtifactID(rawValue: artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: .other,
                format: .json
            ),
            runID: runID,
            mode: .replaceable
        )
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
        let data = try Data(contentsOf: targetURL)
        return ArtifactReference(
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: application.targetPath),
                role: .input,
                kind: .other,
                format: fileFormat(for: application.targetPath)
            ),
            digest: try SHA256ContentDigester().digest(data: data, using: .sha256),
            byteCount: UInt64(data.count)
        )
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

        let beforeReference = ArtifactReference(
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: proposal.targetPath),
                role: .input,
                kind: .other,
                format: fileFormat(for: proposal.targetPath)
            ),
            digest: try SHA256ContentDigester().digest(data: beforeData, using: .sha256),
            byteCount: UInt64(beforeData.count)
        )
        try afterData.write(to: targetURL, options: .atomic)
        let afterReference = ArtifactReference(
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: proposal.targetPath),
                role: .output,
                kind: .other,
                format: fileFormat(for: proposal.targetPath)
            ),
            digest: try SHA256ContentDigester().digest(data: afterData, using: .sha256),
            byteCount: UInt64(afterData.count)
        )
        return AppliedWaiverEdit(beforeReference: beforeReference, afterReference: afterReference)
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
