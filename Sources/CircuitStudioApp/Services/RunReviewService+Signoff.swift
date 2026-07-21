import DesignFlowKernel
import Foundation
import CircuiteFoundation
import ReleaseCore
import SignoffEngine
import TapeoutEngine
import Xcircuite

extension RunReviewService {
    func signoffReview(
        bundle: FlowRunReviewBundle,
        actions: [FlowRunActionRecord],
        projectRoot: URL
    ) throws -> RunReviewSignoffSummary {
        var cards: [RunReviewSignoffCard] = []
        var decodeIssues: [RunReviewArtifactDecodeIssue] = []

        for artifact in bundle.artifacts where artifact.reference.locator.format == .json {
            switch signoffArtifactKind(for: artifact) {
            case .drc:
                appendDecodedCard(
                    artifact: artifact,
                    allArtifacts: bundle.artifacts,
                    projectRoot: projectRoot,
                    decodeIssues: &decodeIssues,
                    cards: &cards,
                    makeCard: drcCard
                )
            case .lvs:
                appendDecodedCard(
                    artifact: artifact,
                    allArtifacts: bundle.artifacts,
                    projectRoot: projectRoot,
                    decodeIssues: &decodeIssues,
                    cards: &cards,
                    makeCard: lvsCard
                )
            case .pex:
                appendDecodedCard(
                    artifact: artifact,
                    allArtifacts: bundle.artifacts,
                    projectRoot: projectRoot,
                    decodeIssues: &decodeIssues,
                    cards: &cards,
                    makeCard: pexCard
                )
            case .generatedLayoutSignoffCorpus:
                appendDecodedCard(
                    artifact: artifact,
                    allArtifacts: bundle.artifacts,
                    projectRoot: projectRoot,
                    decodeIssues: &decodeIssues,
                    cards: &cards,
                    makeCard: generatedLayoutSignoffCorpusCard
                )
            case .retainedSignoffReport:
                appendDecodedCard(
                    artifact: artifact,
                    allArtifacts: bundle.artifacts,
                    projectRoot: projectRoot,
                    decodeIssues: &decodeIssues,
                    cards: &cards,
                    makeCard: retainedSignoffReportCard
                )
            case .simulationMetric:
                appendDecodedCard(
                    artifact: artifact,
                    allArtifacts: bundle.artifacts,
                    projectRoot: projectRoot,
                    decodeIssues: &decodeIssues,
                    cards: &cards,
                    makeCard: simulationMetricCard
                )
            case .simulationMeasurement:
                appendDecodedCard(
                    artifact: artifact,
                    allArtifacts: bundle.artifacts,
                    projectRoot: projectRoot,
                    decodeIssues: &decodeIssues,
                    cards: &cards,
                    makeCard: simulationMeasurementCard
                )
            case .postLayoutComparison:
                appendDecodedCard(
                    artifact: artifact,
                    allArtifacts: bundle.artifacts,
                    projectRoot: projectRoot,
                    decodeIssues: &decodeIssues,
                    cards: &cards,
                    makeCard: postLayoutComparisonCard
                )
            case .signoffBundle:
                appendReleaseSignoffBundleCards(
                    artifact: artifact,
                    allArtifacts: bundle.artifacts,
                    projectRoot: projectRoot,
                    decodeIssues: &decodeIssues,
                    cards: &cards
                )
            case .releaseAuthorization:
                appendReleaseAuthorizationCard(
                    artifact: artifact,
                    allArtifacts: bundle.artifacts,
                    projectRoot: projectRoot,
                    decodeIssues: &decodeIssues,
                    cards: &cards
                )
            case .tapeoutResult:
                appendTapeoutCard(
                    artifact: artifact,
                    allArtifacts: bundle.artifacts,
                    projectRoot: projectRoot,
                    decodeIssues: &decodeIssues,
                    cards: &cards
                )
            case .foundryHandoff:
                appendFoundryHandoffCard(
                    artifact: artifact,
                    allArtifacts: bundle.artifacts,
                    projectRoot: projectRoot,
                    decodeIssues: &decodeIssues,
                    cards: &cards
                )
            case .none:
                continue
            }
        }

        return RunReviewSignoffSummary(
            cards: cards.sorted { left, right in
                if left.domain != right.domain {
                    return signoffDomainRank(left.domain) < signoffDomainRank(right.domain)
                }
                return left.artifact.reference.locator.location.value < right.artifact.reference.locator.location.value
            },
            repairCandidateCycles: try signoffRepairCandidateCycles(
                from: actions,
                projectRoot: projectRoot
            ),
            decodeIssues: decodeIssues
        )
    }

    private func signoffRepairCandidateCycles(
        from actions: [FlowRunActionRecord],
        projectRoot: URL
    ) throws -> [RunReviewSignoffRepairCandidateCycleHistoryItem] {
        var cycles: [RunReviewSignoffRepairCandidateCycleHistoryItem] = []
        for action in actions where action.actionKind == "review.runSignoffRepairCandidateCycle" {
            guard let artifact = action.outputs.first(where: {
                $0.artifactID.hasPrefix("signoff-repair-candidate-cycle-")
            }) else {
                continue
            }
            let artifactURL = projectRoot.appending(path: artifact.locator.location.value)
            cycles.append(
                try JSONDecoder().decode(
                    RunReviewSignoffRepairCandidateCycleHistoryItem.self,
                    from: Data(contentsOf: artifactURL)
                )
            )
        }
        return cycles.sorted { left, right in
            if left.cycleIndex != right.cycleIndex {
                return left.cycleIndex < right.cycleIndex
            }
            return left.createdAt < right.createdAt
        }
    }

    private func appendDecodedCard<Document: Decodable>(
        artifact: FlowRunReviewArtifact,
        allArtifacts: [FlowRunReviewArtifact],
        projectRoot: URL,
        decodeIssues: inout [RunReviewArtifactDecodeIssue],
        cards: inout [RunReviewSignoffCard],
        makeCard: (Document, FlowRunReviewArtifact) -> RunReviewSignoffCard
    ) {
        do {
            try validateSignoffArtifactIntegrity(artifact, projectRoot: projectRoot)
            let data = try Data(contentsOf: artifactURL(for: artifact, projectRoot: projectRoot))
            let document = try JSONDecoder().decode(Document.self, from: data)
            let artifactKind = signoffArtifactKind(for: artifact)
            var card = makeCard(document, artifact)
            let relatedArtifacts = relatedArtifacts(
                for: artifact,
                artifactKind: artifactKind,
                allArtifacts: allArtifacts
            )
            let evaluationProjection = artifactEvaluationProjection(
                for: artifact,
                relatedArtifacts: relatedArtifacts,
                projectRoot: projectRoot,
                decodeIssues: &decodeIssues
            )
            card = RunReviewSignoffCard(
                domain: card.domain,
                title: card.title,
                status: card.status,
                passed: card.passed,
                stageID: card.stageID,
                artifact: card.artifact,
                relatedArtifacts: relatedArtifacts,
                primaryMetrics: card.primaryMetrics,
                detailSections: card.detailSections + evaluationProjection.detailSections,
                evaluationEvidence: card.evaluationEvidence + evaluationProjection.evidence,
                issues: card.issues.map { issue in
                    issue.withEvidenceArtifacts(
                        issueEvidenceArtifacts(
                            primary: artifact,
                            relatedArtifacts: relatedArtifacts
                        )
                    )
                }
            )
            cards.append(card)
        } catch {
            decodeIssues.append(
                RunReviewArtifactDecodeIssue(
                    artifactRole: artifact.purpose.rawValue,
                    artifactPath: artifact.reference.locator.location.value,
                    message: error.localizedDescription
                )
            )
        }
    }

    private func appendReleaseSignoffBundleCards(
        artifact: FlowRunReviewArtifact,
        allArtifacts: [FlowRunReviewArtifact],
        projectRoot: URL,
        decodeIssues: inout [RunReviewArtifactDecodeIssue],
        cards: inout [RunReviewSignoffCard]
    ) {
        do {
            let data = try verifiedSignoffArtifactData(artifact, projectRoot: projectRoot)
            try requireProducer(
                artifact.reference,
                kind: .engine,
                identifier: "native.release.signoff",
                version: "2.0.0",
                document: "signoff bundle"
            )
            let bundle = try SignoffBundle.decodeCanonical(from: data)
            let recomputedEvidenceDigest = try CanonicalSignoffEvidenceDigester()
                .digest(bundle.evidenceRecords)
            guard recomputedEvidenceDigest.caseInsensitiveCompare(bundle.evidenceDigest) == .orderedSame else {
                throw RunReviewReleaseDocumentError.invalidContent(
                    document: "signoff bundle",
                    reason: "The canonical evidence digest does not match the typed evidence records."
                )
            }
            for evidenceArtifact in bundle.evidenceArtifacts {
                _ = try requireRetainedArtifact(
                    evidenceArtifact,
                    allArtifacts: allArtifacts,
                    projectRoot: projectRoot,
                    document: "signoff evidence"
                )
            }
            let related = relatedArtifacts(
                for: artifact,
                artifactKind: .signoffBundle,
                allArtifacts: allArtifacts
            )
            cards.append(signoffBundleOverviewCard(bundle, artifact: artifact, relatedArtifacts: related))
            cards.append(contentsOf: bundle.axisResults.map {
                signoffAxisCard($0, bundle: bundle, artifact: artifact, relatedArtifacts: related)
            })
        } catch {
            appendReleaseDecodeIssue(error, artifact: artifact, decodeIssues: &decodeIssues)
        }
    }

    private func appendReleaseAuthorizationCard(
        artifact: FlowRunReviewArtifact,
        allArtifacts: [FlowRunReviewArtifact],
        projectRoot: URL,
        decodeIssues: inout [RunReviewArtifactDecodeIssue],
        cards: inout [RunReviewSignoffCard]
    ) {
        do {
            let data = try verifiedSignoffArtifactData(artifact, projectRoot: projectRoot)
            let result = try releaseJSONDecoder().decode(ReleaseAuthorizationResult.self, from: data)
            try validateReleaseAuthorization(
                result,
                artifact: artifact,
                allArtifacts: allArtifacts,
                projectRoot: projectRoot
            )
            let related = relatedArtifacts(
                for: artifact,
                artifactKind: .releaseAuthorization,
                allArtifacts: allArtifacts
            )
            cards.append(releaseAuthorizationCard(result, artifact: artifact, relatedArtifacts: related))
        } catch {
            appendReleaseDecodeIssue(error, artifact: artifact, decodeIssues: &decodeIssues)
        }
    }

    private func appendTapeoutCard(
        artifact: FlowRunReviewArtifact,
        allArtifacts: [FlowRunReviewArtifact],
        projectRoot: URL,
        decodeIssues: inout [RunReviewArtifactDecodeIssue],
        cards: inout [RunReviewSignoffCard]
    ) {
        do {
            let data = try verifiedSignoffArtifactData(artifact, projectRoot: projectRoot)
            let result = try releaseJSONDecoder().decode(TapeoutResult.self, from: data)
            try validateTapeoutResult(
                result,
                artifact: artifact,
                allArtifacts: allArtifacts,
                projectRoot: projectRoot
            )
            let related = relatedArtifacts(
                for: artifact,
                artifactKind: .tapeoutResult,
                allArtifacts: allArtifacts
            )
            cards.append(tapeoutCard(result, artifact: artifact, relatedArtifacts: related))
        } catch {
            appendReleaseDecodeIssue(error, artifact: artifact, decodeIssues: &decodeIssues)
        }
    }

    private func appendFoundryHandoffCard(
        artifact: FlowRunReviewArtifact,
        allArtifacts: [FlowRunReviewArtifact],
        projectRoot: URL,
        decodeIssues: inout [RunReviewArtifactDecodeIssue],
        cards: inout [RunReviewSignoffCard]
    ) {
        do {
            let data = try verifiedSignoffArtifactData(artifact, projectRoot: projectRoot)
            try requireProducer(
                artifact.reference,
                kind: .engine,
                identifier: "native.release.tapeout",
                version: "2.0.0",
                document: "foundry handoff manifest"
            )
            let manifest = try FoundryHandoffManifest.decodeCanonical(from: data)
            for retainedArtifact in manifest.artifacts {
                _ = try requireRetainedArtifact(
                    retainedArtifact,
                    allArtifacts: allArtifacts,
                    projectRoot: projectRoot,
                    document: "foundry handoff evidence"
                )
            }
            let related = relatedArtifacts(
                for: artifact,
                artifactKind: .foundryHandoff,
                allArtifacts: allArtifacts
            )
            cards.append(foundryHandoffCard(manifest, artifact: artifact, relatedArtifacts: related))
        } catch {
            appendReleaseDecodeIssue(error, artifact: artifact, decodeIssues: &decodeIssues)
        }
    }

    private func verifiedSignoffArtifactData(
        _ artifact: FlowRunReviewArtifact,
        projectRoot: URL
    ) throws -> Data {
        try validateSignoffArtifactIntegrity(artifact, projectRoot: projectRoot)
        return try Data(contentsOf: artifactURL(for: artifact, projectRoot: projectRoot))
    }

    private func releaseJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func appendReleaseDecodeIssue(
        _ error: any Error,
        artifact: FlowRunReviewArtifact,
        decodeIssues: inout [RunReviewArtifactDecodeIssue]
    ) {
        decodeIssues.append(RunReviewArtifactDecodeIssue(
            artifactRole: artifact.purpose.rawValue,
            artifactPath: artifact.reference.locator.location.value,
            message: error.localizedDescription
        ))
    }

    private func requireProducer(
        _ reference: ArtifactReference,
        kind: ProducerKind,
        identifier: String,
        version: String,
        document: String
    ) throws {
        guard let producer = reference.producer,
              producer.kind == kind,
              producer.identifier == identifier,
              producer.version == version,
              isSHA256Digest(producer.build) else {
            throw RunReviewReleaseDocumentError.producerMismatch(document: document)
        }
    }

    private func isSHA256Digest(_ value: String?) -> Bool {
        guard let value, value.utf8.count == 64 else {
            return false
        }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) ||
                (65...70).contains(byte) ||
                (97...102).contains(byte)
        }
    }

    private func validateReleaseAuthorization(
        _ result: ReleaseAuthorizationResult,
        artifact: FlowRunReviewArtifact,
        allArtifacts: [FlowRunReviewArtifact],
        projectRoot: URL
    ) throws {
        guard result.schemaVersion == ReleaseAuthorizationResult.currentSchemaVersion else {
            throw RunReviewReleaseDocumentError.unsupportedSchema(
                document: "release authorization",
                actual: result.schemaVersion,
                expected: ReleaseAuthorizationResult.currentSchemaVersion
            )
        }
        try requireProducer(
            artifact.reference,
            kind: .engine,
            identifier: "native.release.authorization",
            version: "2.0.0",
            document: "release authorization"
        )
        guard artifact.reference.producer == result.evidence.provenance.producer,
              result.evidence.artifacts == result.artifacts else {
            throw RunReviewReleaseDocumentError.producerMismatch(document: "release authorization")
        }
        switch result.status {
        case .authorized:
            guard let bundleReference = result.signoffBundle,
                  result.artifacts == [bundleReference.artifact],
                  result.approval.verdict == .approved,
                  result.approval.reviewerKind == .human,
                  !result.approval.reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  result.approval.evidence.stageResult == bundleReference.artifact,
                  !result.diagnostics.contains(where: { $0.severity == .error }) else {
                throw RunReviewReleaseDocumentError.invalidContent(
                    document: "release authorization",
                    reason: "An authorized result must retain an exact signoff bundle and identified human approval without error diagnostics."
                )
            }
            let retainedBundle = try requireRetainedArtifact(
                bundleReference.artifact,
                allArtifacts: allArtifacts,
                projectRoot: projectRoot,
                document: "release authorization signoff bundle"
            )
            try requireProducer(
                retainedBundle.reference,
                kind: .engine,
                identifier: "native.release.signoff",
                version: "2.0.0",
                document: "release authorization signoff bundle"
            )
            let bundle = try SignoffBundle.decodeCanonical(
                from: try Data(contentsOf: artifactURL(for: retainedBundle, projectRoot: projectRoot))
            )
            guard bundle.designDigest == bundleReference.designDigest,
                  bundle.pdkDigest == bundleReference.pdkDigest,
                  bundle.finalLayoutDigest == bundleReference.finalLayoutDigest else {
                throw RunReviewReleaseDocumentError.invalidContent(
                    document: "release authorization",
                    reason: "The retained canonical signoff bundle does not match the authorization binding."
                )
            }
        case .blocked:
            guard result.signoffBundle == nil,
                  result.artifacts.isEmpty,
                  result.diagnostics.contains(where: { $0.severity == .error }) else {
                throw RunReviewReleaseDocumentError.invalidContent(
                    document: "release authorization",
                    reason: "A blocked result must not expose an authorized bundle and must explain the blocking error."
                )
            }
        }
    }

    private func validateTapeoutResult(
        _ result: TapeoutResult,
        artifact: FlowRunReviewArtifact,
        allArtifacts: [FlowRunReviewArtifact],
        projectRoot: URL
    ) throws {
        guard result.schemaVersion == TapeoutRequest.currentSchemaVersion else {
            throw RunReviewReleaseDocumentError.unsupportedSchema(
                document: "tapeout result",
                actual: result.schemaVersion,
                expected: TapeoutRequest.currentSchemaVersion
            )
        }
        guard result.payload.schemaVersion == TapeoutPayload.currentSchemaVersion else {
            throw RunReviewReleaseDocumentError.unsupportedSchema(
                document: "tapeout payload",
                actual: result.payload.schemaVersion,
                expected: TapeoutPayload.currentSchemaVersion
            )
        }
        try requireProducer(
            artifact.reference,
            kind: .engine,
            identifier: "native.release.tapeout",
            version: "2.0.0",
            document: "tapeout result"
        )
        guard artifact.reference.producer == result.provenance.producer else {
            throw RunReviewReleaseDocumentError.producerMismatch(document: "tapeout result")
        }
        guard result.artifacts.count == Set(result.artifacts).count else {
            throw RunReviewReleaseDocumentError.invalidContent(
                document: "tapeout result",
                reason: "Tapeout artifacts must have unique canonical identities."
            )
        }
        switch result.status {
        case .completed:
            guard result.payload.completed,
                  let handoff = result.payload.handoff,
                  let handoffArtifact = result.payload.handoffArtifact,
                  result.payload.checksum == handoff.manifestDigest,
                  result.payload.layoutDigest == handoff.layoutDigest,
                  result.payload.pdkDigest == handoff.pdkDigest,
                  result.artifacts.contains(handoffArtifact),
                  Set(handoff.artifacts).isSubset(of: Set(result.artifacts)),
                  handoff.isSelfConsistent,
                  let streamOut = result.payload.streamOut,
                  streamOut.schemaVersion == StreamOutManifest.currentSchemaVersion,
                  result.artifacts.contains(streamOut.streamedArtifact),
                  result.payload.xorResult?.isTapeoutQualified(at: result.provenance.completedAt) == true,
                  !result.diagnostics.contains(where: { $0.severity == .error }) else {
                throw RunReviewReleaseDocumentError.invalidContent(
                    document: "tapeout result",
                    reason: "A completed result must retain qualified stream-out, XOR, and self-consistent handoff evidence."
                )
            }
            let retainedHandoff = try requireRetainedArtifact(
                handoffArtifact,
                allArtifacts: allArtifacts,
                projectRoot: projectRoot,
                document: "tapeout handoff manifest"
            )
            try requireProducer(
                retainedHandoff.reference,
                kind: .engine,
                identifier: "native.release.tapeout",
                version: "2.0.0",
                document: "tapeout handoff manifest"
            )
            let persistedHandoff = try FoundryHandoffManifest.decodeCanonical(
                from: try Data(contentsOf: artifactURL(for: retainedHandoff, projectRoot: projectRoot))
            )
            guard persistedHandoff == handoff else {
                throw RunReviewReleaseDocumentError.invalidContent(
                    document: "tapeout result",
                    reason: "The retained handoff manifest differs from the typed tapeout payload."
                )
            }
        case .failed, .blocked, .cancelled:
            guard !result.payload.completed,
                  result.payload.handoff == nil,
                  result.payload.handoffArtifact == nil else {
                throw RunReviewReleaseDocumentError.invalidContent(
                    document: "tapeout result",
                    reason: "An incomplete result must not expose completed handoff state."
                )
            }
        }
    }

    private func requireRetainedArtifact(
        _ reference: ArtifactReference,
        allArtifacts: [FlowRunReviewArtifact],
        projectRoot: URL,
        document: String
    ) throws -> FlowRunReviewArtifact {
        guard let retained = allArtifacts.first(where: { $0.reference == reference }) else {
            throw RunReviewReleaseDocumentError.invalidContent(
                document: document,
                reason: "The exact referenced artifact is not retained in the run ledger."
            )
        }
        try validateSignoffArtifactIntegrity(retained, projectRoot: projectRoot)
        return retained
    }

    private func validateSignoffArtifactIntegrity(
        _ artifact: FlowRunReviewArtifact,
        projectRoot: URL
    ) throws {
        guard let integrity = artifact.integrity else {
            throw RunReviewServiceError.signoffArtifactIntegrityUnverified(
                path: artifact.reference.locator.location.value,
                status: "missing",
                message: "No recorded artifact integrity state is available."
            )
        }
        guard integrity.status == .verified else {
            throw RunReviewServiceError.signoffArtifactIntegrityUnverified(
                path: artifact.reference.locator.location.value,
                status: integrity.status.rawValue,
                message: integrity.message
            )
        }
        let currentIntegrity = LocalArtifactVerifier().verify(
            artifact.reference,
            relativeTo: projectRoot
        )
        guard currentIntegrity.isVerified else {
            throw RunReviewServiceError.signoffArtifactIntegrityUnverified(
                path: artifact.reference.locator.location.value,
                status: currentIntegrity.issues.first?.code.rawValue ?? "integrity-failure",
                message: currentIntegrity.issues.map(\.code.rawValue).joined(separator: ", ")
            )
        }
    }

    private func drcCard(
        document: DRCReviewDocument,
        artifact: FlowRunReviewArtifact
    ) -> RunReviewSignoffCard {
        let summary = document.summary
        let activeBuckets = summary.violationBuckets
            .filter { $0.activeCount > 0 }
            .sorted { $0.activeCount > $1.activeCount }
        return RunReviewSignoffCard(
            domain: "DRC",
            title: "DRC Summary",
            status: summary.status,
            passed: summary.passed,
            stageID: artifact.stageID,
            artifact: artifact,
            primaryMetrics: [
                RunReviewSignoffMetric(label: "Active", value: "\(summary.activeViolationCount)"),
                RunReviewSignoffMetric(label: "Waived", value: "\(summary.waivedViolationCount)"),
                RunReviewSignoffMetric(label: "Tool", value: summary.toolName),
                RunReviewSignoffMetric(label: "Top", value: summary.topCell),
            ],
            detailSections: sourceDetailSections(
                title: "DRC Sources",
                reportURL: document.reportURL,
                manifestURL: document.manifestURL
            ) + drcDetailSections(summary),
            issues: activeBuckets.prefix(5).map { bucket in
                RunReviewSignoffIssue(
                    severity: "error",
                    label: drcBucketLabel(bucket),
                    count: bucket.activeCount,
                    message: drcBucketMessage(bucket),
                    suggestedFixes: bucket.suggestedFixes,
                    repairActionHints: drcRepairActionHints(bucket),
                    detailRows: drcIssueDetailRows(bucket)
                )
            }
        )
    }

    private func lvsCard(
        document: LVSReviewDocument,
        artifact: FlowRunReviewArtifact
    ) -> RunReviewSignoffCard {
        let summary = document.summary
        let projection = LVSSignoffProjection(document: document)
        let activeBuckets = summary.mismatchBuckets
            .filter { $0.activeCount > 0 }
            .sorted { $0.activeCount > $1.activeCount }
        return RunReviewSignoffCard(
            domain: "LVS",
            title: "LVS Summary",
            status: projection.status,
            passed: projection.passed,
            stageID: artifact.stageID,
            artifact: artifact,
            primaryMetrics: [
                RunReviewSignoffMetric(label: "Active", value: "\(summary.activeMismatchCount)"),
                RunReviewSignoffMetric(label: "Waived", value: "\(summary.waivedMismatchCount)"),
                RunReviewSignoffMetric(label: "Execution", value: projection.executionStatus),
                RunReviewSignoffMetric(label: "Verdict", value: projection.verdict),
                RunReviewSignoffMetric(label: "Readiness", value: projection.readiness),
                RunReviewSignoffMetric(label: "Tool", value: summary.toolName),
                RunReviewSignoffMetric(label: "Top", value: summary.topCell),
            ],
            detailSections: sourceDetailSections(
                title: "LVS Sources",
                reportURL: document.reportURL,
                manifestURL: document.manifestURL,
                extraMetrics: compactMetrics([
                    ("Layout input", summary.layoutInputKind),
                    ("Extracted", summary.extractedLayoutNetlistURL.map(sourceURLValue)),
                ])
            ) + lvsContractDetailSections(projection) + lvsDetailSections(summary),
            issues: projection.blockingReasons.map { reason in
                RunReviewSignoffIssue(
                    severity: "error",
                    label: reason.code,
                    message: reason.message,
                    suggestedFixes: ["resolve-lvs-readiness-block"],
                    detailRows: [
                        RunReviewSignoffDetailRow(
                            label: "Readiness Block",
                            metrics: compactMetrics([
                                ("Code", reason.code),
                                ("Evidence", joinedList(reason.evidenceReferences)),
                            ])
                        ),
                    ]
                )
            } + activeBuckets.prefix(5).map { bucket in
                RunReviewSignoffIssue(
                    severity: "error",
                    label: lvsBucketLabel(bucket),
                    count: bucket.activeCount,
                    message: lvsBucketMessage(bucket),
                    suggestedFixes: bucket.suggestedFixes,
                    repairActionHints: lvsRepairActionHints(bucket),
                    detailRows: lvsIssueDetailRows(bucket)
                )
            }
        )
    }

    private func lvsContractDetailSections(
        _ projection: LVSSignoffProjection
    ) -> [RunReviewSignoffDetailSection] {
        [
            RunReviewSignoffDetailSection(
                title: "LVS v2 Contract",
                rows: [
                    RunReviewSignoffDetailRow(
                        label: "Authoritative Result",
                        metrics: [
                            RunReviewSignoffMetric(label: "Execution", value: projection.executionStatus),
                            RunReviewSignoffMetric(label: "Verdict", value: projection.verdict),
                            RunReviewSignoffMetric(label: "Readiness", value: projection.readiness),
                            RunReviewSignoffMetric(label: "Blocking reasons", value: "\(projection.blockingReasons.count)"),
                        ]
                    ),
                ]
            ),
        ]
    }

    private func pexCard(
        document: PEXReviewDocument,
        artifact: FlowRunReviewArtifact
    ) -> RunReviewSignoffCard {
        let summary = document.summary
        let failedCorners = summary.corners.filter { !isPassingStatus($0.status) }
        let diagnostics = summary.corners.flatMap { corner in
            corner.diagnostics.map { diagnostic in
                RunReviewSignoffIssue(
                    severity: diagnostic.severity,
                    label: "\(corner.cornerID):\(diagnostic.code)",
                    message: diagnostic.message,
                    repairActionHints: pexRepairActionHints(
                        corner: corner,
                        diagnostic: diagnostic
                    ),
                    detailRows: pexDiagnosticDetailRows(
                        corner: corner,
                        diagnostic: diagnostic
                    )
                )
            }
        }
        let topNetIssues = summary.corners.flatMap { corner in
            corner.topNets.prefix(3).map { net in
                RunReviewSignoffIssue(
                    severity: "info",
                    label: "\(corner.cornerID):\(net.name)",
                    message: "C=\(formatted(net.groundCapF + net.couplingCapF))F R=\(formatted(net.resistanceOhm))ohm nodes=\(net.nodeCount)",
                    repairActionHints: pexNetRepairActionHints(corner: corner, net: net),
                    detailRows: pexTopNetDetailRows(corner: corner, net: net)
                )
            }
        }
        return RunReviewSignoffCard(
            domain: "PEX",
            title: "PEX Summary",
            status: summary.status,
            passed: failedCorners.isEmpty && isPassingStatus(summary.status),
            stageID: artifact.stageID,
            artifact: artifact,
            primaryMetrics: [
                RunReviewSignoffMetric(label: "Corners", value: "\(summary.corners.count)"),
                RunReviewSignoffMetric(label: "Failed", value: "\(failedCorners.count)"),
                RunReviewSignoffMetric(label: "Nets", value: "\(summary.corners.map(\.netCount).reduce(0, +))"),
                RunReviewSignoffMetric(label: "Elements", value: "\(summary.corners.map(\.elementCount).reduce(0, +))"),
            ],
            detailSections: sourceDetailSections(
                title: "PEX Sources",
                manifestURL: document.manifestURL
            ) + pexDetailSections(summary),
            issues: Array((diagnostics + topNetIssues).prefix(6))
        )
    }

    private func simulationMetricCard(
        document: XcircuiteSimulationMetricReport,
        artifact: FlowRunReviewArtifact
    ) -> RunReviewSignoffCard {
        let failedVerdicts = document.verdicts.filter { !isPassingStatus($0.status) }
        let diagnosticIssues = document.diagnostics
            .filter { $0.severity.lowercased() != "info" }
            .map {
                RunReviewSignoffIssue(
                    severity: $0.severity,
                    label: $0.code,
                    message: $0.message,
                    repairActionHints: simulationRepairActionHints(reason: $0.message),
                    detailRows: simulationDiagnosticDetailRows($0)
                )
            }
        let verdictIssues = failedVerdicts.map { verdict in
            RunReviewSignoffIssue(
                severity: "error",
                label: verdict.name,
                message: "value=\(optionalFormatted(verdict.value)) target=\(formatted(verdict.target)) tolerance=\(formatted(verdict.tolerance))",
                repairActionHints: simulationRepairActionHints(
                    reason: "Improve simulation metric \(verdict.name) toward target \(formatted(verdict.target))."
                ),
                detailRows: simulationVerdictDetailRows(verdict)
            )
        }
        return RunReviewSignoffCard(
            domain: "Simulation",
            title: document.analysisLabel ?? "Simulation Metrics",
            status: document.status,
            passed: failedVerdicts.isEmpty && isPassingStatus(document.status),
            stageID: artifact.stageID,
            artifact: artifact,
            primaryMetrics: [
                RunReviewSignoffMetric(label: "Measurements", value: "\(document.measurements.count)"),
                RunReviewSignoffMetric(label: "Verdicts", value: "\(document.verdicts.count)"),
                RunReviewSignoffMetric(label: "Failures", value: "\(failedVerdicts.count)"),
                RunReviewSignoffMetric(label: "Source", value: document.source),
            ],
            issues: Array((verdictIssues + diagnosticIssues).prefix(6))
        )
    }

    private func simulationMeasurementCard(
        document: [SimulationMeasurementValue],
        artifact: FlowRunReviewArtifact
    ) -> RunReviewSignoffCard {
        RunReviewSignoffCard(
            domain: "Simulation",
            title: "Simulation Measurements",
            status: "measured",
            passed: nil,
            stageID: artifact.stageID,
            artifact: artifact,
            primaryMetrics: [
                RunReviewSignoffMetric(label: "Measurements", value: "\(document.count)"),
            ] + document.prefix(4).map {
                RunReviewSignoffMetric(label: $0.name, value: "\(formatted($0.value)) \($0.unit)")
            }
        )
    }

    private func postLayoutComparisonCard(
        document: PostLayoutComparisonReport,
        artifact: FlowRunReviewArtifact
    ) -> RunReviewSignoffCard {
        let issues = document.gateViolations.map {
            RunReviewSignoffIssue(
                severity: "error",
                label: "gate",
                message: $0,
                repairActionHints: postLayoutRepairActionHints(reason: $0)
            )
        } + document.diagnostics.map {
            RunReviewSignoffIssue(
                severity: "warning",
                label: "diagnostic",
                message: $0,
                repairActionHints: postLayoutRepairActionHints(reason: $0)
            )
        }
        return RunReviewSignoffCard(
            domain: "Post-layout",
            title: "Post-layout Comparison",
            status: document.gateStatus,
            passed: document.gateViolations.isEmpty && isPassingStatus(document.gateStatus),
            stageID: artifact.stageID,
            artifact: artifact,
            primaryMetrics: [
                RunReviewSignoffMetric(label: "Compared", value: "\(document.comparedVariables.count) variables"),
                RunReviewSignoffMetric(label: "Points", value: "\(document.comparedPointCount)"),
                RunReviewSignoffMetric(label: "Max abs", value: formatted(document.maxAbsoluteDelta)),
                RunReviewSignoffMetric(label: "Max rel", value: formatted(document.maxRelativeDelta)),
            ],
            detailSections: postLayoutComparisonDetailSections(document),
            issues: Array(issues.prefix(6))
        )
    }

    private func postLayoutComparisonDetailSections(
        _ document: PostLayoutComparisonReport
    ) -> [RunReviewSignoffDetailSection] {
        let variableRows = document.comparedVariables.prefix(8).map { variable in
            RunReviewSignoffDetailRow(
                label: variable.variableName,
                metrics: [
                    RunReviewSignoffMetric(label: "Points", value: "\(variable.pointCount)"),
                    RunReviewSignoffMetric(label: "Max abs", value: formatted(variable.maxAbsoluteDelta)),
                    RunReviewSignoffMetric(label: "Max rel", value: formatted(variable.maxRelativeDelta)),
                ]
            )
        }
        guard !variableRows.isEmpty else {
            return []
        }
        return [
            RunReviewSignoffDetailSection(
                title: "Compared Variables",
                rows: variableRows
            ),
        ]
    }

    private func sourceDetailSections(
        title: String,
        reportURL: URL? = nil,
        manifestURL: URL? = nil,
        extraMetrics: [RunReviewSignoffMetric] = []
    ) -> [RunReviewSignoffDetailSection] {
        let metrics = compactMetrics([
            ("Report", reportURL.map(sourceURLValue)),
            ("Manifest", manifestURL.map(sourceURLValue)),
        ]) + extraMetrics
        guard !metrics.isEmpty else {
            return []
        }
        return [
            RunReviewSignoffDetailSection(
                title: title,
                rows: [
                    RunReviewSignoffDetailRow(
                        label: "Source Artifacts",
                        metrics: metrics
                    ),
                ]
            ),
        ]
    }

    private func drcDetailSections(
        _ summary: DRCReviewSummary
    ) -> [RunReviewSignoffDetailSection] {
        let rows = summary.violationBuckets.prefix(12).map { bucket in
            RunReviewSignoffDetailRow(
                label: drcBucketLabel(bucket),
                metrics: compactMetrics([
                    ("Kind", bucket.kind),
                    ("Layer", bucket.layer),
                    ("Active", "\(bucket.activeCount)"),
                    ("Waived", bucket.waivedCount.map(String.init)),
                    ("Measured", bucket.maxMeasured.map(formatted)),
                    ("Required", bucket.required.map(formatted)),
                    ("Region", bucket.representativeRegion.map(regionLabel)),
                    ("Shapes", joinedList(bucket.relatedShapeIDs)),
                    ("Nets", joinedList(bucket.relatedNetIDs)),
                    ("Fixes", bucket.suggestedFixes.isEmpty ? nil : bucket.suggestedFixes.joined(separator: ", ")),
                ])
            )
        }
        guard !rows.isEmpty else {
            return []
        }
        return [
            RunReviewSignoffDetailSection(
                title: "Violation Buckets",
                rows: rows
            ),
        ]
    }

    private func lvsDetailSections(
        _ summary: LVSReviewSummary
    ) -> [RunReviewSignoffDetailSection] {
        let rows = summary.mismatchBuckets.prefix(12).map { bucket in
            RunReviewSignoffDetailRow(
                label: lvsBucketLabel(bucket),
                metrics: compactMetrics([
                    ("Category", bucket.category),
                    ("Component", bucket.componentSignature),
                    ("Parameter", bucket.parameterName),
                    ("Layout", bucket.layoutModel),
                    ("Schematic", bucket.schematicModel),
                    ("Active", "\(bucket.activeCount)"),
                    ("Waived", bucket.waivedCount.map(String.init)),
                    ("Layout count", bucket.layoutCount.map(String.init)),
                    ("Schematic count", bucket.schematicCount.map(String.init)),
                    ("Layout ports", joinedList(bucket.layoutPorts)),
                    ("Schematic ports", joinedList(bucket.schematicPorts)),
                    ("Fixes", bucket.suggestedFixes.isEmpty ? nil : bucket.suggestedFixes.joined(separator: ", ")),
                ])
            )
        }
        guard !rows.isEmpty else {
            return []
        }
        return [
            RunReviewSignoffDetailSection(
                title: "Mismatch Buckets",
                rows: rows
            ),
        ]
    }

    private func pexDetailSections(
        _ summary: PEXReviewSummary
    ) -> [RunReviewSignoffDetailSection] {
        var sections: [RunReviewSignoffDetailSection] = []
        let cornerRows = summary.corners.prefix(12).map { corner in
            RunReviewSignoffDetailRow(
                label: corner.cornerID,
                metrics: compactMetrics([
                    ("Status", corner.status),
                    ("Nets", "\(corner.netCount)"),
                    ("Elements", "\(corner.elementCount)"),
                    ("Top nets", "\(corner.topNets.count)"),
                    ("Diagnostics", "\(corner.diagnostics.count)"),
                ])
            )
        }
        if !cornerRows.isEmpty {
            sections.append(RunReviewSignoffDetailSection(title: "Corners", rows: cornerRows))
        }

        let diagnosticRows = summary.corners.flatMap { corner in
            corner.diagnostics.map { diagnostic in
                RunReviewSignoffDetailRow(
                    label: "\(corner.cornerID):\(diagnostic.code)",
                    metrics: compactMetrics([
                        ("Corner", corner.cornerID),
                        ("Severity", diagnostic.severity),
                        ("Status", corner.status),
                        ("Message", diagnostic.message),
                    ])
                )
            }
        }
        if !diagnosticRows.isEmpty {
            sections.append(
                RunReviewSignoffDetailSection(
                    title: "PEX Diagnostics",
                    rows: Array(diagnosticRows.prefix(12))
                )
            )
        }

        let topNetRows = summary.corners.flatMap { corner in
            corner.topNets.map { net in
                RunReviewSignoffDetailRow(
                    label: "\(corner.cornerID):\(net.name)",
                    metrics: compactMetrics([
                        ("Corner", corner.cornerID),
                        ("Ground C", "\(formatted(net.groundCapF))F"),
                        ("Coupling C", "\(formatted(net.couplingCapF))F"),
                        ("Resistance", "\(formatted(net.resistanceOhm))ohm"),
                        ("Nodes", "\(net.nodeCount)"),
                    ])
                )
            }
        }
        if !topNetRows.isEmpty {
            sections.append(
                RunReviewSignoffDetailSection(
                    title: "Top Nets",
                    rows: Array(topNetRows.prefix(12))
                )
            )
        }
        return sections
    }

    private func drcIssueDetailRows(_ bucket: DRCReviewBucket) -> [RunReviewSignoffDetailRow] {
        [
            RunReviewSignoffDetailRow(
                label: "Violation",
                metrics: compactMetrics([
                    ("Rule", bucket.ruleID),
                    ("Kind", bucket.kind),
                    ("Layer", bucket.layer),
                    ("Active", "\(bucket.activeCount)"),
                    ("Waived", bucket.waivedCount.map(String.init)),
                    ("Measured", bucket.maxMeasured.map(formatted)),
                    ("Required", bucket.required.map(formatted)),
                    ("Region", bucket.representativeRegion.map(regionLabel)),
                    ("Shapes", joinedList(bucket.relatedShapeIDs)),
                    ("Nets", joinedList(bucket.relatedNetIDs)),
                ])
            ),
        ]
    }

    private func lvsIssueDetailRows(_ bucket: LVSReviewBucket) -> [RunReviewSignoffDetailRow] {
        [
            RunReviewSignoffDetailRow(
                label: "Mismatch",
                metrics: compactMetrics([
                    ("Rule", bucket.ruleID),
                    ("Category", bucket.category),
                    ("Component", bucket.componentSignature),
                    ("Parameter", bucket.parameterName),
                    ("Layout", bucket.layoutModel),
                    ("Schematic", bucket.schematicModel),
                    ("Active", "\(bucket.activeCount)"),
                    ("Waived", bucket.waivedCount.map(String.init)),
                    ("Layout count", bucket.layoutCount.map(String.init)),
                    ("Schematic count", bucket.schematicCount.map(String.init)),
                    ("Layout ports", joinedList(bucket.layoutPorts)),
                    ("Schematic ports", joinedList(bucket.schematicPorts)),
                ])
            ),
        ]
    }

    private func pexDiagnosticDetailRows(
        corner: PEXReviewCorner,
        diagnostic: PEXReviewDiagnostic
    ) -> [RunReviewSignoffDetailRow] {
        [
            RunReviewSignoffDetailRow(
                label: "Diagnostic",
                metrics: compactMetrics([
                    ("Corner", corner.cornerID),
                    ("Code", diagnostic.code),
                    ("Severity", diagnostic.severity),
                    ("Status", corner.status),
                ])
            ),
        ]
    }

    private func pexTopNetDetailRows(
        corner: PEXReviewCorner,
        net: PEXReviewNet
    ) -> [RunReviewSignoffDetailRow] {
        [
            RunReviewSignoffDetailRow(
                label: "Top Net",
                metrics: compactMetrics([
                    ("Corner", corner.cornerID),
                    ("Net", net.name),
                    ("Ground C", "\(formatted(net.groundCapF))F"),
                    ("Coupling C", "\(formatted(net.couplingCapF))F"),
                    ("Resistance", "\(formatted(net.resistanceOhm))ohm"),
                    ("Nodes", "\(net.nodeCount)"),
                ])
            ),
        ]
    }

    private func simulationDiagnosticDetailRows(
        _ diagnostic: XcircuiteSimulationMetricReport.Diagnostic
    ) -> [RunReviewSignoffDetailRow] {
        [
            RunReviewSignoffDetailRow(
                label: "Diagnostic",
                metrics: compactMetrics([
                    ("Code", diagnostic.code),
                    ("Severity", diagnostic.severity),
                ])
            ),
        ]
    }

    private func simulationVerdictDetailRows(
        _ verdict: XcircuiteSimulationMetricReport.MeasurementVerdict
    ) -> [RunReviewSignoffDetailRow] {
        [
            RunReviewSignoffDetailRow(
                label: "Verdict",
                metrics: compactMetrics([
                    ("Metric", verdict.name),
                    ("Status", verdict.status),
                    ("Value", verdict.value.map(formatted)),
                    ("Target", formatted(verdict.target)),
                    ("Tolerance", formatted(verdict.tolerance)),
                ])
            ),
        ]
    }

    private func drcRepairActionHints(
        _ bucket: DRCReviewBucket
    ) -> [RunReviewSignoffRepairActionHint] {
        let operationID = drcLayoutOperationID(for: bucket)
        return [
            RunReviewSignoffRepairActionHint(
                domainID: "layout-edit",
                operationID: operationID,
                maturity: operationID == "layout-command-replay" ? "planned" : "implemented",
                reason: "Generate a DRC repair candidate for \(drcBucketLabel(bucket)) through the planning problem builder.",
                requiredInputRefs: ["layout-ref"],
                verificationGates: ["artifact-integrity", "native-drc", "native-lvs"]
            ),
        ]
    }

    private func lvsRepairActionHints(
        _ bucket: LVSReviewBucket
    ) -> [RunReviewSignoffRepairActionHint] {
        var hints: [RunReviewSignoffRepairActionHint] = []
        if isLVSPortMismatch(bucket) {
            hints.append(
                RunReviewSignoffRepairActionHint(
                    domainID: "layout-edit",
                    operationID: "layout.add-label",
                    maturity: "implemented",
                    reason: "Create or correct layout labels so extracted ports can match the schematic.",
                    requiredInputRefs: ["layout-ref"],
                    verificationGates: ["artifact-integrity", "native-lvs", "native-drc"]
                )
            )
            hints.append(
                RunReviewSignoffRepairActionHint(
                    domainID: "layout-edit",
                    operationID: "layout.add-net",
                    maturity: "implemented",
                    reason: "Create a missing layout net before labeling or reconnecting LVS-visible ports.",
                    requiredInputRefs: ["layout-ref"],
                    verificationGates: ["artifact-integrity", "native-lvs", "native-drc"]
                )
            )
        }
        if requiresLVSPolicyRepair(bucket) {
            hints.append(
                RunReviewSignoffRepairActionHint(
                    domainID: "lvs-signoff",
                    operationID: "lvs.policy-repair",
                    maturity: "implemented",
                    reason: "Review an auditable model or terminal equivalence policy update.",
                    requiredInputRefs: ["lvs-summary", "schematic-netlist-ref"],
                    verificationGates: ["approval-gate", "native-lvs", "artifact-integrity"]
                )
            )
        }
        if isLVSParameterMismatch(bucket) {
            hints.append(
                RunReviewSignoffRepairActionHint(
                    domainID: "simulation-analysis",
                    operationID: "simulation.set-netlist-parameters",
                    maturity: "implemented",
                    reason: "Edit schematic or extracted netlist parameters and verify the LVS metric again.",
                    requiredInputRefs: ["layout-netlist-ref", "schematic-netlist-ref"],
                    verificationGates: ["artifact-integrity", "native-lvs"]
                )
            )
        }
        if hints.isEmpty {
            hints.append(
                RunReviewSignoffRepairActionHint(
                    domainID: "layout-edit",
                    operationID: "layout-command-replay",
                    maturity: "planned",
                    reason: "Generate a replayable layout edit after resolving the mismatch geometry.",
                    requiredInputRefs: ["layout-ref"],
                    verificationGates: ["artifact-integrity", "native-lvs", "native-drc"]
                )
            )
        }
        return hints
    }

    private func pexRepairActionHints(
        corner: PEXReviewCorner,
        diagnostic: PEXReviewDiagnostic
    ) -> [RunReviewSignoffRepairActionHint] {
        [
            RunReviewSignoffRepairActionHint(
                domainID: "pex-signoff",
                operationID: "pex.metric-recovery-objective",
                maturity: "planned",
                reason: "Recover PEX evidence for \(corner.cornerID) after \(diagnostic.code).",
                requiredInputRefs: ["pex-summary", "source-netlist-ref", "pex-technology-ref"],
                verificationGates: ["artifact-integrity", "pex-summary-gate"]
            ),
            RunReviewSignoffRepairActionHint(
                domainID: "layout-edit",
                operationID: "layout-command-replay",
                maturity: "implemented",
                reason: "Replay layout edits after resolving the extracted parasitic hotspot.",
                requiredInputRefs: ["layout-ref", "source-netlist-ref", "pex-technology-ref"],
                verificationGates: ["artifact-integrity", "native-drc", "native-lvs", "pex-summary-gate"]
            ),
        ]
    }

    private func pexNetRepairActionHints(
        corner: PEXReviewCorner,
        net: PEXReviewNet
    ) -> [RunReviewSignoffRepairActionHint] {
        [
            RunReviewSignoffRepairActionHint(
                domainID: "pex-signoff",
                operationID: "pex.metric-recovery-objective",
                maturity: "planned",
                reason: "Investigate \(net.name) in \(corner.cornerID) as a parasitic hotspot.",
                requiredInputRefs: ["pex-summary", "source-netlist-ref", "pex-technology-ref"],
                verificationGates: ["artifact-integrity", "pex-summary-gate"]
            ),
        ]
    }

    private func simulationRepairActionHints(
        reason: String
    ) -> [RunReviewSignoffRepairActionHint] {
        [
            RunReviewSignoffRepairActionHint(
                domainID: "simulation-analysis",
                operationID: "simulation.metric-improvement-objective",
                maturity: "planned",
                reason: reason,
                requiredInputRefs: ["post-layout-metric-report", "source-netlist-ref"],
                verificationGates: ["schema-validation", "simulation-metric-gate"]
            ),
        ]
    }

    private func postLayoutRepairActionHints(
        reason: String
    ) -> [RunReviewSignoffRepairActionHint] {
        [
            RunReviewSignoffRepairActionHint(
                domainID: "pex-signoff",
                operationID: "pex.metric-recovery-objective",
                maturity: "planned",
                reason: reason,
                requiredInputRefs: ["pex-summary", "post-layout-comparison", "source-netlist-ref"],
                verificationGates: ["artifact-integrity", "pex-summary-gate", "simulation-metric-gate"]
            ),
        ]
    }

    private func sourceURLValue(_ url: URL) -> String {
        if url.isFileURL {
            return url.path(percentEncoded: false)
        }
        return url.absoluteString
    }

    private func regionLabel(_ region: DRCReviewRegion) -> String {
        "x=\(formatted(region.x)) y=\(formatted(region.y)) w=\(formatted(region.width)) h=\(formatted(region.height))"
    }

    private func joinedList(_ values: [String]?) -> String? {
        guard let values, !values.isEmpty else {
            return nil
        }
        return values.prefix(6).joined(separator: ", ")
    }

    private func drcLayoutOperationID(for bucket: DRCReviewBucket) -> String {
        let normalized = [
            bucket.kind,
            bucket.ruleID,
            bucket.suggestedFixes.joined(separator: " "),
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
        if normalized.contains("cut") || normalized.contains("via") {
            return "layout.add-via"
        }
        if (normalized.contains("notch") || normalized.contains("fill"))
            && bucket.representativeRegion != nil {
            return "layout.add-rect"
        }
        if normalized.contains("density") && normalized.contains("remove") {
            return "layout.delete-shape"
        }
        if normalized.contains("width")
            || normalized.contains("area")
            || normalized.contains("enclosure")
            || normalized.contains("extension") {
            if !(bucket.relatedShapeIDs ?? []).isEmpty {
                return "layout.resize-shape"
            }
            return "layout.add-rect"
        }
        if !(bucket.relatedShapeIDs ?? []).isEmpty {
            return "layout.translate-shape"
        }
        return "layout-command-replay"
    }

    private func isLVSPortMismatch(_ bucket: LVSReviewBucket) -> Bool {
        let normalized = [
            bucket.ruleID,
            bucket.category,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
        return normalized.contains("port")
            || (bucket.layoutPorts ?? []) != (bucket.schematicPorts ?? [])
    }

    private func requiresLVSPolicyRepair(_ bucket: LVSReviewBucket) -> Bool {
        let normalized = [
            bucket.ruleID,
            bucket.category,
            bucket.componentSignature,
            bucket.parameterName,
            bucket.layoutModel,
            bucket.schematicModel,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
        return normalized.contains("model")
            || normalized.contains("terminal")
            || normalized.contains("equivalence")
    }

    private func isLVSParameterMismatch(_ bucket: LVSReviewBucket) -> Bool {
        let normalized = [
            bucket.ruleID,
            bucket.category,
            bucket.parameterName,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
        return normalized.contains("parameter")
            || bucket.parameterName != nil
    }

    private func compactMetrics(
        _ pairs: [(label: String, value: String?)]
    ) -> [RunReviewSignoffMetric] {
        pairs.compactMap { pair in
            guard let value = pair.value, !value.isEmpty else {
                return nil
            }
            return RunReviewSignoffMetric(label: pair.label, value: value)
        }
    }

    private func signoffBundleOverviewCard(
        _ bundle: SignoffBundle,
        artifact: FlowRunReviewArtifact,
        relatedArtifacts: [FlowRunReviewArtifact]
    ) -> RunReviewSignoffCard {
        let eligibleCount = bundle.axisResults.filter(\.disposition.isReleaseEligible).count
        let waivedCount = bundle.axisResults.filter { $0.disposition == .waived }.count
        return RunReviewSignoffCard(
            domain: "Release",
            title: "Release Signoff Bundle",
            status: bundle.isReleaseReady ? "release-ready" : "blocked",
            passed: bundle.isReleaseReady,
            stageID: artifact.stageID,
            artifact: artifact,
            relatedArtifacts: relatedArtifacts,
            primaryMetrics: [
                RunReviewSignoffMetric(label: "Axes", value: "\(bundle.axisResults.count)"),
                RunReviewSignoffMetric(label: "Eligible", value: "\(eligibleCount)"),
                RunReviewSignoffMetric(label: "Waived", value: "\(waivedCount)"),
                RunReviewSignoffMetric(label: "Evidence", value: "\(bundle.evidenceRecords.count)"),
            ],
            detailSections: [
                RunReviewSignoffDetailSection(
                    title: "Release Binding",
                    rows: [RunReviewSignoffDetailRow(
                        label: bundle.bundleID,
                        metrics: [
                            RunReviewSignoffMetric(label: "Profile", value: bundle.profileID),
                            RunReviewSignoffMetric(label: "Design SHA-256", value: bundle.designDigest),
                            RunReviewSignoffMetric(label: "PDK SHA-256", value: bundle.pdkDigest),
                            RunReviewSignoffMetric(label: "Layout SHA-256", value: bundle.finalLayoutDigest),
                            RunReviewSignoffMetric(label: "Evidence SHA-256", value: bundle.evidenceDigest),
                        ]
                    )]
                ),
                releaseArtifactLineageSection(artifact.reference),
            ]
        )
    }

    private func signoffAxisCard(
        _ result: SignoffAxisResult,
        bundle: SignoffBundle,
        artifact: FlowRunReviewArtifact,
        relatedArtifacts: [FlowRunReviewArtifact]
    ) -> RunReviewSignoffCard {
        let issue: RunReviewSignoffIssue?
        switch result.disposition {
        case .failed, .blocked:
            issue = RunReviewSignoffIssue(
                severity: "error",
                label: result.axis.rawValue,
                message: result.reason,
                suggestedFixes: [],
                detailRows: [RunReviewSignoffDetailRow(
                    label: "Evidence",
                    metrics: compactMetrics([
                        ("Evidence IDs", result.evidenceIDs.joined(separator: ", ")),
                        ("Diagnostic codes", result.diagnosticCodes.joined(separator: ", ")),
                    ])
                )],
                evidenceArtifacts: [artifact] + relatedArtifacts
            )
        case .waived:
            issue = RunReviewSignoffIssue(
                severity: "warning",
                label: result.waiverID ?? result.axis.rawValue,
                message: result.reason,
                evidenceArtifacts: [artifact] + relatedArtifacts
            )
        case .passed, .profileApprovedNotApplicable:
            issue = nil
        }
        return RunReviewSignoffCard(
            domain: "Release / \(releaseAxisTitle(result.axis))",
            title: "\(releaseAxisTitle(result.axis)) Signoff",
            status: result.disposition.rawValue,
            passed: result.disposition.isReleaseEligible,
            stageID: artifact.stageID,
            artifact: artifact,
            relatedArtifacts: relatedArtifacts,
            primaryMetrics: [
                RunReviewSignoffMetric(label: "Disposition", value: result.disposition.rawValue),
                RunReviewSignoffMetric(label: "Evidence", value: "\(result.evidenceIDs.count)"),
                RunReviewSignoffMetric(label: "Diagnostics", value: "\(result.diagnosticCodes.count)"),
            ],
            detailSections: [RunReviewSignoffDetailSection(
                title: "Axis Decision",
                rows: [RunReviewSignoffDetailRow(
                    label: result.axis.rawValue,
                    metrics: compactMetrics([
                        ("Reason", result.reason),
                        ("Evidence IDs", result.evidenceIDs.joined(separator: ", ")),
                        ("Diagnostic codes", result.diagnosticCodes.joined(separator: ", ")),
                        ("Waiver", result.waiverID),
                        ("Bundle", bundle.bundleID),
                    ])
                )]
            )],
            issues: issue.map { [$0] } ?? []
        )
    }

    private func releaseAuthorizationCard(
        _ result: ReleaseAuthorizationResult,
        artifact: FlowRunReviewArtifact,
        relatedArtifacts: [FlowRunReviewArtifact]
    ) -> RunReviewSignoffCard {
        let authorized = result.status == .authorized
        return RunReviewSignoffCard(
            domain: "Release Authorization",
            title: "Human Release Authorization",
            status: result.status.rawValue,
            passed: authorized,
            stageID: artifact.stageID,
            artifact: artifact,
            relatedArtifacts: relatedArtifacts,
            primaryMetrics: [
                RunReviewSignoffMetric(label: "Reviewer", value: result.approval.reviewer),
                RunReviewSignoffMetric(label: "Reviewer kind", value: result.approval.reviewerKind.rawValue),
                RunReviewSignoffMetric(label: "Verdict", value: result.approval.verdict.rawValue),
                RunReviewSignoffMetric(label: "Diagnostics", value: "\(result.diagnostics.count)"),
            ],
            detailSections: [
                RunReviewSignoffDetailSection(
                    title: "Approval Binding",
                    rows: [RunReviewSignoffDetailRow(
                        label: result.approval.stageID,
                        metrics: [
                            RunReviewSignoffMetric(label: "Run", value: result.approval.runID),
                            RunReviewSignoffMetric(label: "Plan", value: result.approval.evidence.plan.path),
                            RunReviewSignoffMetric(label: "Stage result", value: result.approval.evidence.stageResult.path),
                            RunReviewSignoffMetric(label: "Note", value: result.approval.note),
                        ]
                    )]
                ),
                releaseArtifactLineageSection(artifact.reference),
            ],
            issues: releaseDiagnosticIssues(result.diagnostics, evidenceArtifacts: [artifact] + relatedArtifacts)
        )
    }

    private func tapeoutCard(
        _ result: TapeoutResult,
        artifact: FlowRunReviewArtifact,
        relatedArtifacts: [FlowRunReviewArtifact]
    ) -> RunReviewSignoffCard {
        let completed = result.status == .completed && result.payload.completed
        return RunReviewSignoffCard(
            domain: "Tapeout",
            title: "Tapeout Packaging",
            status: result.status.rawValue,
            passed: completed,
            stageID: artifact.stageID,
            artifact: artifact,
            relatedArtifacts: relatedArtifacts,
            primaryMetrics: [
                RunReviewSignoffMetric(label: "Completed", value: completed ? "yes" : "no"),
                RunReviewSignoffMetric(label: "XOR", value: result.payload.xorResult?.status.rawValue ?? "unavailable"),
                RunReviewSignoffMetric(label: "Method", value: result.payload.xorResult?.method.rawValue ?? "unavailable"),
                RunReviewSignoffMetric(label: "Artifacts", value: "\(result.artifacts.count)"),
            ],
            detailSections: [
                RunReviewSignoffDetailSection(
                    title: "Tapeout Binding",
                    rows: [RunReviewSignoffDetailRow(
                        label: result.runID,
                        metrics: compactMetrics([
                            ("Layout SHA-256", result.payload.layoutDigest),
                            ("PDK SHA-256", result.payload.pdkDigest),
                            ("Handoff SHA-256", result.payload.checksum),
                            ("Handoff artifact", result.payload.handoffArtifact?.path),
                            ("Streamed artifact", result.payload.streamOut?.streamedArtifact.path),
                        ])
                    )]
                ),
                releaseArtifactLineageSection(artifact.reference),
            ],
            issues: releaseDiagnosticIssues(result.diagnostics, evidenceArtifacts: [artifact] + relatedArtifacts)
        )
    }

    private func foundryHandoffCard(
        _ manifest: FoundryHandoffManifest,
        artifact: FlowRunReviewArtifact,
        relatedArtifacts: [FlowRunReviewArtifact]
    ) -> RunReviewSignoffCard {
        RunReviewSignoffCard(
            domain: "Tapeout Handoff",
            title: "Foundry Handoff Manifest",
            status: "verified",
            passed: true,
            stageID: artifact.stageID,
            artifact: artifact,
            relatedArtifacts: relatedArtifacts,
            primaryMetrics: [
                RunReviewSignoffMetric(label: "Foundry", value: manifest.foundryID),
                RunReviewSignoffMetric(label: "Artifacts", value: "\(manifest.artifacts.count)"),
                RunReviewSignoffMetric(label: "Evidence", value: "\(manifest.evidenceIDs.count)"),
            ],
            detailSections: [
                RunReviewSignoffDetailSection(
                    title: "Foundry Binding",
                    rows: [RunReviewSignoffDetailRow(
                        label: manifest.releaseID,
                        metrics: [
                            RunReviewSignoffMetric(label: "Manifest SHA-256", value: manifest.manifestDigest),
                            RunReviewSignoffMetric(label: "Signoff SHA-256", value: manifest.signoffBundleArtifactDigest),
                            RunReviewSignoffMetric(label: "Design SHA-256", value: manifest.designDigest),
                            RunReviewSignoffMetric(label: "PDK SHA-256", value: manifest.pdkDigest),
                            RunReviewSignoffMetric(label: "Layout SHA-256", value: manifest.layoutDigest),
                        ]
                    )]
                ),
                releaseArtifactLineageSection(artifact.reference),
            ]
        )
    }

    private func releaseDiagnosticIssues(
        _ diagnostics: [DesignDiagnostic],
        evidenceArtifacts: [FlowRunReviewArtifact]
    ) -> [RunReviewSignoffIssue] {
        diagnostics.map { diagnostic in
            RunReviewSignoffIssue(
                severity: releaseDiagnosticSeverity(diagnostic.severity),
                label: diagnostic.code.rawValue,
                message: diagnostic.summary,
                suggestedFixes: diagnostic.suggestedActions.map(\.summary),
                evidenceArtifacts: evidenceArtifacts
            )
        }
    }

    private func releaseDiagnosticSeverity(_ severity: DiagnosticSeverity) -> String {
        switch severity {
        case .information: "information"
        case .warning: "warning"
        case .error: "error"
        }
    }

    private func releaseArtifactLineageSection(
        _ reference: ArtifactReference
    ) -> RunReviewSignoffDetailSection {
        RunReviewSignoffDetailSection(
            title: "Artifact Lineage",
            rows: [RunReviewSignoffDetailRow(
                label: reference.id.rawValue,
                metrics: compactMetrics([
                    ("Path", reference.path),
                    ("SHA-256", reference.digest.hexadecimalValue),
                    ("Bytes", String(reference.byteCount)),
                    ("Producer kind", reference.producer?.kind.rawValue),
                    ("Producer", reference.producer?.identifier),
                    ("Version", reference.producer?.version),
                    ("Build", reference.producer?.build),
                ])
            )]
        )
    }

    private func releaseAxisTitle(_ axis: ReleaseSignoffAxis) -> String {
        switch axis {
        case .simulation: "Simulation"
        case .logicSynthesisEquivalence: "Logic Synthesis Equivalence"
        case .rtlLint: "RTL Lint"
        case .clockDomainCrossing: "Clock Domain Crossing"
        case .resetDomainCrossing: "Reset Domain Crossing"
        case .formalProof: "Formal Proof"
        case .scanInsertion: "Scan Insertion"
        case .automaticTestPatternGeneration: "Automatic Test Pattern Generation"
        case .builtInSelfTest: "Built-In Self-Test"
        case .powerIntent: "Power Intent"
        case .timing: "Timing"
        case .crosstalkNoise: "Crosstalk Noise"
        case .electromigration: "Electromigration"
        case .irDrop: "IR Drop"
        case .drc: "DRC"
        case .lvs: "LVS"
        case .pex: "PEX"
        case .antenna: "Antenna"
        case .density: "Density"
        case .metalFill: "Metal Fill"
        case .erc: "ERC"
        case .esd: "ESD"
        case .latchUp: "Latch-Up"
        case .aging: "Aging"
        case .designForManufacturability: "Design for Manufacturability"
        }
    }

    private func signoffArtifactKind(for artifact: FlowRunReviewArtifact) -> SignoffArtifactKind? {
        let artifactID = artifact.reference.id.rawValue
        let path = artifact.reference.locator.location.value.lowercased()
        if artifactID == "release-authorization-result"
            || path.contains("release.authorization") && path.hasSuffix("result.json") {
            return .releaseAuthorization
        }
        if artifactID == "release-tapeout-result"
            || path.contains("release.tapeout") && path.hasSuffix("result.json") {
            return .tapeoutResult
        }
        if artifact.reference.locator.kind == .release,
           artifact.reference.producer?.identifier == "native.release.signoff" {
            return .signoffBundle
        }
        if artifact.reference.locator.kind == .release,
           artifact.reference.producer?.identifier == "native.release.tapeout" {
            return .foundryHandoff
        }
        if artifactID == "drc-summary" || path.hasSuffix("drc-summary.json") {
            return .drc
        }
        if artifactID == "lvs-summary" || path.hasSuffix("lvs-summary.json") {
            return .lvs
        }
        if artifactID == "pex-summary" || path.hasSuffix("pex-summary.json") {
            return .pex
        }
        if artifactID == "generated-layout-signoff-corpus-report"
            || artifactID == "generated-layout-signoff-ready-oracle-corpus-report"
            || (
                path.contains("generated-layout-signoff")
                    && (
                        path.hasSuffix("corpus-report.json")
                            || path.hasSuffix("corpus-report-ready-oracle-evidence.json")
                    )
            ) {
            return .generatedLayoutSignoffCorpus
        }
        if artifactID == "retained-signoff-report"
            || path.hasSuffix("retained-signoff-report.json")
            || path.contains("retained-signoff-report")
            || path.hasSuffix("signoff-retained-report-v2.json") {
            return .retainedSignoffReport
        }
        if artifactID == "planning-simulation-summary" || path.hasSuffix("simulation-summary.json") {
            return .simulationMetric
        }
        if artifact.reference.locator.kind == .measurement && path.hasSuffix("measurements.json") {
            return .simulationMeasurement
        }
        if artifactID == "post-layout-comparison" || path.hasSuffix("comparison-report.json") {
            return .postLayoutComparison
        }
        return nil
    }

    private func relatedArtifacts(
        for artifact: FlowRunReviewArtifact,
        artifactKind: SignoffArtifactKind?,
        allArtifacts: [FlowRunReviewArtifact]
    ) -> [FlowRunReviewArtifact] {
        var seenPaths = Set<String>()
        return allArtifacts
            .filter { candidate in
                candidate.reference.locator.location.value != artifact.reference.locator.location.value
                    && seenPaths.insert(candidate.reference.locator.location.value).inserted
                    && isRelatedArtifact(candidate, to: artifact, artifactKind: artifactKind)
            }
            .sorted { left, right in
                if left.purpose != right.purpose {
                    return left.purpose.rawValue < right.purpose.rawValue
                }
                return left.reference.locator.location.value < right.reference.locator.location.value
            }
    }

    private func issueEvidenceArtifacts(
        primary: FlowRunReviewArtifact,
        relatedArtifacts: [FlowRunReviewArtifact]
    ) -> [FlowRunReviewArtifact] {
        var seenPaths = Set<String>()
        return ([primary] + relatedArtifacts).filter { artifact in
            seenPaths.insert(artifact.reference.locator.location.value).inserted
        }
    }

    private func isRelatedArtifact(
        _ candidate: FlowRunReviewArtifact,
        to artifact: FlowRunReviewArtifact,
        artifactKind: SignoffArtifactKind?
    ) -> Bool {
        if candidate.stageID == artifact.stageID && candidate.purpose == .stageResult {
            return true
        }
        guard let artifactKind else {
            return false
        }
        let searchable = [
            candidate.reference.id.rawValue,
            candidate.purpose.rawValue,
            candidate.reference.locator.location.value,
            candidate.reference.locator.kind.rawValue,
            candidate.reference.locator.format.rawValue,
        ]
        .map { $0.lowercased() }
        .joined(separator: " ")

        switch artifactKind {
        case .drc:
            return searchable.contains("drc")
        case .lvs:
            return searchable.contains("lvs")
        case .pex:
            return searchable.contains("pex") || searchable.contains("spef")
        case .generatedLayoutSignoffCorpus:
            return searchable.contains("generated-layout-signoff")
                || searchable.contains("oracle")
                || searchable.contains("corpus")
                || searchable.contains("retained-signoff")
        case .retainedSignoffReport:
            return searchable.contains("retained-signoff")
                || searchable.contains("oracle")
                || searchable.contains("generated-layout-signoff")
        case .simulationMetric, .simulationMeasurement:
            return searchable.contains("simulation")
                || searchable.contains("measurement")
                || searchable.contains("waveform")
        case .postLayoutComparison:
            return searchable.contains("comparison")
                || searchable.contains("pre-layout")
                || searchable.contains("post-layout")
                || searchable.contains("waveform")
        case .signoffBundle:
            return searchable.contains("signoff")
                || searchable.contains("evidence")
                || searchable.contains("qualification")
                || searchable.contains("waiver")
        case .releaseAuthorization:
            return searchable.contains("authorization")
                || searchable.contains("approval")
                || searchable.contains("signoff")
        case .tapeoutResult, .foundryHandoff:
            return searchable.contains("tapeout")
                || searchable.contains("handoff")
                || searchable.contains("stream")
                || searchable.contains("xor")
                || searchable.contains("authorization")
                || searchable.contains("signoff")
        }
    }

    private func signoffDomainRank(_ domain: String) -> Int {
        switch domain {
        case "DRC": return 0
        case "LVS": return 1
        case "PEX": return 2
        case "Oracle": return 3
        case "Simulation": return 4
        case "Post-layout": return 5
        case "Release": return 10
        case "Release Authorization": return 50
        case "Tapeout": return 51
        case "Tapeout Handoff": return 52
        case let value where value.hasPrefix("Release / "):
            let title = String(value.dropFirst("Release / ".count))
            return 20 + (ReleaseSignoffAxis.allCases.firstIndex {
                releaseAxisTitle($0) == title
            } ?? ReleaseSignoffAxis.allCases.count)
        default: return 10
        }
    }

    private func drcBucketMessage(_ bucket: DRCReviewBucket) -> String {
        [
            bucket.kind,
            bucket.layer,
            bucket.maxMeasured.map { "measured=\(formatted($0))" },
            bucket.required.map { "required=\(formatted($0))" },
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private func drcBucketLabel(_ bucket: DRCReviewBucket) -> String {
        bucket.ruleID ?? bucket.kind ?? bucket.layer ?? "drc-violation"
    }

    private func lvsBucketMessage(_ bucket: LVSReviewBucket) -> String {
        [
            bucket.category,
            bucket.componentSignature,
            bucket.parameterName.map { "parameter=\($0)" },
            bucket.layoutModel.map { "layout=\($0)" },
            bucket.schematicModel.map { "schematic=\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private func lvsBucketLabel(_ bucket: LVSReviewBucket) -> String {
        bucket.ruleID ?? bucket.category ?? bucket.componentSignature ?? "lvs-mismatch"
    }

    private func artifactURL(for artifact: FlowRunReviewArtifact, projectRoot: URL) -> URL {
        if artifact.reference.locator.location.value.hasPrefix("/") {
            URL(filePath: artifact.reference.locator.location.value)
        } else {
            projectRoot.appending(path: artifact.reference.locator.location.value)
        }
    }

}
