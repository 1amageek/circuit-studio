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
        artifactReader: any XcircuiteArtifactBindingReading
    ) async throws -> RunReviewSignoffSummary {
        var cards: [RunReviewSignoffCard] = []
        var decodeIssues: [RunReviewArtifactDecodeIssue] = []
        let artifactIndex = RunReviewSignoffArtifactIndex(artifacts: bundle.artifacts)
        let actionDomainCatalog = try await signoffActionDomainCatalog(
            bundle: bundle,
            artifactReader: artifactReader
        )

        for artifact in bundle.artifacts where artifact.binding.format == .json {
            switch signoffArtifactKind(for: artifact) {
            case .drc:
                await appendDecodedCard(
                    artifact: artifact,
                    artifactIndex: artifactIndex,
                    artifactReader: artifactReader,
                    decodeIssues: &decodeIssues,
                    cards: &cards,
                    makeCard: {
                        drcCard(
                            document: $0,
                            artifact: $1,
                            actionDomainCatalog: actionDomainCatalog
                        )
                    }
                )
            case .lvs:
                await appendDecodedCard(
                    artifact: artifact,
                    artifactIndex: artifactIndex,
                    artifactReader: artifactReader,
                    decodeIssues: &decodeIssues,
                    cards: &cards,
                    makeCard: {
                        lvsCard(
                            document: $0,
                            artifact: $1,
                            actionDomainCatalog: actionDomainCatalog
                        )
                    }
                )
            case .pex:
                await appendDecodedCard(
                    artifact: artifact,
                    artifactIndex: artifactIndex,
                    artifactReader: artifactReader,
                    decodeIssues: &decodeIssues,
                    cards: &cards,
                    makeCard: {
                        pexCard(
                            document: $0,
                            artifact: $1,
                            actionDomainCatalog: actionDomainCatalog
                        )
                    }
                )
            case .generatedLayoutSignoffCorpus:
                await appendDecodedCard(
                    artifact: artifact,
                    artifactIndex: artifactIndex,
                    artifactReader: artifactReader,
                    decodeIssues: &decodeIssues,
                    cards: &cards,
                    makeCard: generatedLayoutSignoffCorpusCard
                )
            case .retainedSignoffReport:
                await appendDecodedCard(
                    artifact: artifact,
                    artifactIndex: artifactIndex,
                    artifactReader: artifactReader,
                    decodeIssues: &decodeIssues,
                    cards: &cards,
                    makeCard: retainedSignoffReportCard
                )
            case .simulationMetric:
                await appendDecodedCard(
                    artifact: artifact,
                    artifactIndex: artifactIndex,
                    artifactReader: artifactReader,
                    decodeIssues: &decodeIssues,
                    cards: &cards,
                    makeCard: {
                        simulationMetricCard(
                            document: $0,
                            artifact: $1,
                            actionDomainCatalog: actionDomainCatalog
                        )
                    }
                )
            case .simulationMeasurement:
                await appendDecodedCard(
                    artifact: artifact,
                    artifactIndex: artifactIndex,
                    artifactReader: artifactReader,
                    decodeIssues: &decodeIssues,
                    cards: &cards,
                    makeCard: simulationMeasurementCard
                )
            case .postLayoutComparison:
                await appendDecodedCard(
                    artifact: artifact,
                    artifactIndex: artifactIndex,
                    artifactReader: artifactReader,
                    decodeIssues: &decodeIssues,
                    cards: &cards,
                    makeCard: {
                        postLayoutComparisonCard(
                            document: $0,
                            artifact: $1,
                            actionDomainCatalog: actionDomainCatalog
                        )
                    }
                )
            case .signoffBundle:
                await appendReleaseSignoffBundleCards(
                    artifact: artifact,
                    allArtifacts: bundle.artifacts,
                    artifactIndex: artifactIndex,
                    artifactReader: artifactReader,
                    decodeIssues: &decodeIssues,
                    cards: &cards
                )
            case .releaseAuthorization:
                await appendReleaseAuthorizationCard(
                    artifact: artifact,
                    allArtifacts: bundle.artifacts,
                    artifactIndex: artifactIndex,
                    artifactReader: artifactReader,
                    decodeIssues: &decodeIssues,
                    cards: &cards
                )
            case .tapeoutResult:
                await appendTapeoutCard(
                    artifact: artifact,
                    allArtifacts: bundle.artifacts,
                    artifactIndex: artifactIndex,
                    artifactReader: artifactReader,
                    decodeIssues: &decodeIssues,
                    cards: &cards
                )
            case .foundryHandoff:
                await appendFoundryHandoffCard(
                    artifact: artifact,
                    allArtifacts: bundle.artifacts,
                    artifactIndex: artifactIndex,
                    artifactReader: artifactReader,
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
                return left.artifact.binding.circuitStudioPresentationPath < right.artifact.binding.circuitStudioPresentationPath
            },
            repairCandidateCycles: try await signoffRepairCandidateCycles(
                from: actions,
                artifacts: bundle.artifacts,
                artifactReader: artifactReader
            ),
            decodeIssues: decodeIssues
        )
    }

    private func signoffActionDomainCatalog(
        bundle: FlowRunReviewBundle,
        artifactReader: any XcircuiteArtifactBindingReading
    ) async throws -> RunReviewActionDomainCatalog {
        let retainedSnapshots = bundle.artifacts.filter {
            $0.purpose == .planningActionDomain
                || $0.binding.logicalID == XcircuitePlanningArtifactStore.actionDomainArtifactID
        }
        guard retainedSnapshots.count <= 1 else {
            throw RunReviewServiceError.invalidActionDomainSnapshot(
                runID: bundle.runID,
                message: "Multiple planning action-domain snapshots are retained."
            )
        }
        guard let retainedSnapshot = retainedSnapshots.first else {
            return .empty
        }

        let data = try await verifiedSignoffArtifactData(
            retainedSnapshot,
            artifactReader: artifactReader
        )
        let snapshot = try JSONDecoder().decode(
            XcircuitePlanningActionDomainSnapshot.self,
            from: data
        )
        guard snapshot.schemaVersion == 1 else {
            throw RunReviewServiceError.invalidActionDomainSnapshot(
                runID: bundle.runID,
                message: "Expected schema version 1, found \(snapshot.schemaVersion)."
            )
        }
        guard snapshot.runID == bundle.runID else {
            throw RunReviewServiceError.invalidActionDomainSnapshot(
                runID: bundle.runID,
                message: "Snapshot run ID \(snapshot.runID) does not match the review bundle."
            )
        }
        return RunReviewActionDomainCatalog(snapshot: snapshot)
    }

    private func signoffRepairCandidateCycles(
        from actions: [FlowRunActionRecord],
        artifacts: [FlowRunReviewArtifact],
        artifactReader: any XcircuiteArtifactBindingReading
    ) async throws -> [RunReviewSignoffRepairCandidateCycleHistoryItem] {
        var cycles: [RunReviewSignoffRepairCandidateCycleHistoryItem] = []
        for action in actions where action.actionKind == "review.runSignoffRepairCandidateCycle" {
            let outputReferences = Set(action.outputs)
            let matches = artifacts.filter {
                $0.binding.logicalID.hasPrefix("signoff-repair-candidate-cycle-")
                    && outputReferences.contains($0.reference)
            }
            guard !matches.isEmpty else {
                continue
            }
            guard matches.count == 1, let artifact = matches.first else {
                throw RunReviewServiceError.invalidArtifactReference(
                    path: action.actionID,
                    message: "Candidate-cycle action output resolves to multiple review artifact bindings."
                )
            }
            let data = try await verifiedSignoffArtifactData(
                artifact,
                artifactReader: artifactReader
            )
            cycles.append(
                try JSONDecoder().decode(
                    RunReviewSignoffRepairCandidateCycleHistoryItem.self,
                    from: data
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
        artifactIndex: RunReviewSignoffArtifactIndex,
        artifactReader: any XcircuiteArtifactBindingReading,
        decodeIssues: inout [RunReviewArtifactDecodeIssue],
        cards: inout [RunReviewSignoffCard],
        makeCard: (Document, FlowRunReviewArtifact) -> RunReviewSignoffCard
    ) async {
        do {
            let data = try await verifiedSignoffArtifactData(
                artifact,
                artifactReader: artifactReader
            )
            let document = try JSONDecoder().decode(Document.self, from: data)
            let artifactKind = signoffArtifactKind(for: artifact)
            var card = makeCard(document, artifact)
            let relatedArtifacts = artifactIndex.relatedArtifacts(
                for: artifact,
                artifactKind: artifactKind
            )
            let evaluationProjection = await artifactEvaluationProjection(
                for: artifact,
                relatedArtifacts: relatedArtifacts,
                artifactReader: artifactReader,
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
                    artifactPath: artifact.binding.circuitStudioPresentationPath,
                    message: error.localizedDescription
                )
            )
        }
    }

    private func appendReleaseSignoffBundleCards(
        artifact: FlowRunReviewArtifact,
        allArtifacts: [FlowRunReviewArtifact],
        artifactIndex: RunReviewSignoffArtifactIndex,
        artifactReader: any XcircuiteArtifactBindingReading,
        decodeIssues: inout [RunReviewArtifactDecodeIssue],
        cards: inout [RunReviewSignoffCard]
    ) async {
        do {
            let data = try await verifiedSignoffArtifactData(
                artifact,
                artifactReader: artifactReader
            )
            try requireProducer(
                artifact.binding,
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
                _ = try await requireRetainedArtifact(
                    evidenceArtifact,
                    allArtifacts: allArtifacts,
                    artifactReader: artifactReader,
                    document: "signoff evidence"
                )
            }
            let related = artifactIndex.relatedArtifacts(
                for: artifact,
                artifactKind: .signoffBundle
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
        artifactIndex: RunReviewSignoffArtifactIndex,
        artifactReader: any XcircuiteArtifactBindingReading,
        decodeIssues: inout [RunReviewArtifactDecodeIssue],
        cards: inout [RunReviewSignoffCard]
    ) async {
        do {
            let data = try await verifiedSignoffArtifactData(
                artifact,
                artifactReader: artifactReader
            )
            let result = try releaseJSONDecoder().decode(ReleaseAuthorizationResult.self, from: data)
            try await validateReleaseAuthorization(
                result,
                artifact: artifact,
                allArtifacts: allArtifacts,
                artifactReader: artifactReader
            )
            let related = artifactIndex.relatedArtifacts(
                for: artifact,
                artifactKind: .releaseAuthorization
            )
            cards.append(releaseAuthorizationCard(result, artifact: artifact, relatedArtifacts: related))
        } catch {
            appendReleaseDecodeIssue(error, artifact: artifact, decodeIssues: &decodeIssues)
        }
    }

    private func appendTapeoutCard(
        artifact: FlowRunReviewArtifact,
        allArtifacts: [FlowRunReviewArtifact],
        artifactIndex: RunReviewSignoffArtifactIndex,
        artifactReader: any XcircuiteArtifactBindingReading,
        decodeIssues: inout [RunReviewArtifactDecodeIssue],
        cards: inout [RunReviewSignoffCard]
    ) async {
        do {
            let data = try await verifiedSignoffArtifactData(
                artifact,
                artifactReader: artifactReader
            )
            let result = try releaseJSONDecoder().decode(TapeoutResult.self, from: data)
            try await validateTapeoutResult(
                result,
                artifact: artifact,
                allArtifacts: allArtifacts,
                artifactReader: artifactReader
            )
            let related = artifactIndex.relatedArtifacts(
                for: artifact,
                artifactKind: .tapeoutResult
            )
            cards.append(tapeoutCard(result, artifact: artifact, relatedArtifacts: related))
        } catch {
            appendReleaseDecodeIssue(error, artifact: artifact, decodeIssues: &decodeIssues)
        }
    }

    private func appendFoundryHandoffCard(
        artifact: FlowRunReviewArtifact,
        allArtifacts: [FlowRunReviewArtifact],
        artifactIndex: RunReviewSignoffArtifactIndex,
        artifactReader: any XcircuiteArtifactBindingReading,
        decodeIssues: inout [RunReviewArtifactDecodeIssue],
        cards: inout [RunReviewSignoffCard]
    ) async {
        do {
            let data = try await verifiedSignoffArtifactData(
                artifact,
                artifactReader: artifactReader
            )
            try requireProducer(
                artifact.binding,
                kind: .engine,
                identifier: "native.release.tapeout",
                version: "2.0.0",
                document: "foundry handoff manifest"
            )
            let manifest = try FoundryHandoffManifest.decodeCanonical(from: data)
            for retainedArtifact in manifest.artifacts {
                _ = try await requireRetainedArtifact(
                    retainedArtifact,
                    allArtifacts: allArtifacts,
                    artifactReader: artifactReader,
                    document: "foundry handoff evidence"
                )
            }
            let related = artifactIndex.relatedArtifacts(
                for: artifact,
                artifactKind: .foundryHandoff
            )
            cards.append(foundryHandoffCard(manifest, artifact: artifact, relatedArtifacts: related))
        } catch {
            appendReleaseDecodeIssue(error, artifact: artifact, decodeIssues: &decodeIssues)
        }
    }

    private func verifiedSignoffArtifactData(
        _ artifact: FlowRunReviewArtifact,
        artifactReader: any XcircuiteArtifactBindingReading
    ) async throws -> Data {
        try validateRecordedSignoffArtifactIntegrity(artifact)
        return try await artifactReader.loadArtifactContent(for: artifact.binding)
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
            artifactPath: artifact.binding.circuitStudioPresentationPath,
            message: error.localizedDescription
        ))
    }

    private func requireProducer(
        _ binding: FlowArtifactBinding,
        kind: ProducerKind,
        identifier: String,
        version: String,
        document: String
    ) throws {
        guard let producer = binding.producer,
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
        artifactReader: any XcircuiteArtifactBindingReading
    ) async throws {
        guard result.schemaVersion == ReleaseAuthorizationResult.currentSchemaVersion else {
            throw RunReviewReleaseDocumentError.unsupportedSchema(
                document: "release authorization",
                actual: result.schemaVersion,
                expected: ReleaseAuthorizationResult.currentSchemaVersion
            )
        }
        try requireProducer(
            artifact.binding,
            kind: .engine,
            identifier: "native.release.authorization",
            version: "2.0.0",
            document: "release authorization"
        )
        guard artifact.binding.producer == result.evidence.provenance.producer,
              result.evidence.artifacts == result.artifacts else {
            throw RunReviewReleaseDocumentError.producerMismatch(document: "release authorization")
        }
        switch result.status {
        case .authorized:
            guard let bundleReference = result.signoffBundle,
                  result.artifactBindings == [bundleReference.artifact],
                  result.approval.verdict == .approved,
                  result.approval.reviewerKind == .human,
                  !result.approval.reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  releaseBinding(
                    bundleReference.artifact,
                    matches: result.approval.evidence.stageResult
                  ),
                  !result.diagnostics.contains(where: { $0.severity == .error }) else {
                throw RunReviewReleaseDocumentError.invalidContent(
                    document: "release authorization",
                    reason: "An authorized result must retain an exact signoff bundle and identified human approval without error diagnostics."
                )
            }
            let retainedBundle = try await requireRetainedArtifact(
                bundleReference.artifact,
                allArtifacts: allArtifacts,
                artifactReader: artifactReader,
                document: "release authorization signoff bundle"
            )
            try requireProducer(
                retainedBundle.binding,
                kind: .engine,
                identifier: "native.release.signoff",
                version: "2.0.0",
                document: "release authorization signoff bundle"
            )
            let bundle = try SignoffBundle.decodeCanonical(
                from: try await verifiedSignoffArtifactData(
                    retainedBundle,
                    artifactReader: artifactReader
                )
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
        artifactReader: any XcircuiteArtifactBindingReading
    ) async throws {
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
            artifact.binding,
            kind: .engine,
            identifier: "native.release.tapeout",
            version: "2.0.0",
            document: "tapeout result"
        )
        guard artifact.binding.producer == result.provenance.producer else {
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
                  let handoffBinding = result.payload.handoffBinding,
                  result.payload.checksum == handoff.manifestDigest,
                  result.payload.layoutDigest == handoff.layoutDigest,
                  result.payload.pdkDigest == handoff.pdkDigest,
                  result.artifactBindings.contains(handoffBinding),
                  Set(handoff.artifacts).isSubset(of: Set(result.artifacts)),
                  handoff.isSelfConsistent,
                  let streamOut = result.payload.streamOut,
                  streamOut.schemaVersion == StreamOutManifest.currentSchemaVersion,
                  result.artifactBindings.contains(streamOut.streamedArtifact),
                  result.payload.xorResult?.isTapeoutQualified(
                    at: Date(timeIntervalSince1970: result.provenance.completedAt.secondsSinceUnixEpoch)
                  ) == true,
                  !result.diagnostics.contains(where: { $0.severity == .error }) else {
                throw RunReviewReleaseDocumentError.invalidContent(
                    document: "tapeout result",
                    reason: "A completed result must retain qualified stream-out, XOR, and self-consistent handoff evidence."
                )
            }
            let retainedHandoff = try await requireRetainedArtifact(
                handoffBinding,
                allArtifacts: allArtifacts,
                artifactReader: artifactReader,
                document: "tapeout handoff manifest"
            )
            try requireProducer(
                retainedHandoff.binding,
                kind: .engine,
                identifier: "native.release.tapeout",
                version: "2.0.0",
                document: "tapeout handoff manifest"
            )
            let persistedHandoff = try FoundryHandoffManifest.decodeCanonical(
                from: try await verifiedSignoffArtifactData(
                    retainedHandoff,
                    artifactReader: artifactReader
                )
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
        artifactReader: any XcircuiteArtifactBindingReading,
        document: String
    ) async throws -> FlowRunReviewArtifact {
        guard let retained = allArtifacts.first(where: { $0.reference == reference }) else {
            throw RunReviewReleaseDocumentError.invalidContent(
                document: document,
                reason: "The exact referenced artifact is not retained in the run ledger."
            )
        }
        _ = try await verifiedSignoffArtifactData(
            retained,
            artifactReader: artifactReader
        )
        return retained
    }

    private func requireRetainedArtifact(
        _ binding: ReleaseArtifactBinding,
        allArtifacts: [FlowRunReviewArtifact],
        artifactReader: any XcircuiteArtifactBindingReading,
        document: String
    ) async throws -> FlowRunReviewArtifact {
        let matches = allArtifacts.filter {
            releaseBinding(binding, matches: $0.binding)
        }
        guard matches.count == 1, let retained = matches.first else {
            throw RunReviewReleaseDocumentError.invalidContent(
                document: document,
                reason: matches.isEmpty
                    ? "The exact artifact binding is not retained in the run ledger."
                    : "The exact artifact binding resolves to multiple retained artifacts."
            )
        }
        _ = try await verifiedSignoffArtifactData(
            retained,
            artifactReader: artifactReader
        )
        return retained
    }

    private func releaseBinding(
        _ release: ReleaseArtifactBinding,
        matches flow: FlowArtifactBinding
    ) -> Bool {
        release.logicalID == flow.logicalID
            && release.reference == flow.reference
            && release.availability == flow.availability
    }

    private func validateRecordedSignoffArtifactIntegrity(
        _ artifact: FlowRunReviewArtifact
    ) throws {
        guard let integrity = artifact.integrity else {
            throw RunReviewServiceError.signoffArtifactIntegrityUnverified(
                path: artifact.binding.circuitStudioPresentationPath,
                status: "missing",
                message: "No recorded artifact integrity state is available."
            )
        }
        guard integrity.status == .verified else {
            throw RunReviewServiceError.signoffArtifactIntegrityUnverified(
                path: artifact.binding.circuitStudioPresentationPath,
                status: integrity.status.rawValue,
                message: integrity.message
            )
        }
    }

    private func drcCard(
        document: DRCReviewDocument,
        artifact: FlowRunReviewArtifact,
        actionDomainCatalog: RunReviewActionDomainCatalog
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
                    repairActionHints: drcRepairActionHints(
                        bucket,
                        actionDomainCatalog: actionDomainCatalog
                    ),
                    detailRows: drcIssueDetailRows(bucket)
                )
            }
        )
    }

    private func lvsCard(
        document: LVSReviewDocument,
        artifact: FlowRunReviewArtifact,
        actionDomainCatalog: RunReviewActionDomainCatalog
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
                    repairActionHints: lvsRepairActionHints(
                        bucket,
                        actionDomainCatalog: actionDomainCatalog
                    ),
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
        artifact: FlowRunReviewArtifact,
        actionDomainCatalog: RunReviewActionDomainCatalog
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
                        diagnostic: diagnostic,
                        actionDomainCatalog: actionDomainCatalog
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
                    repairActionHints: pexNetRepairActionHints(
                        corner: corner,
                        net: net,
                        actionDomainCatalog: actionDomainCatalog
                    ),
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
        artifact: FlowRunReviewArtifact,
        actionDomainCatalog: RunReviewActionDomainCatalog
    ) -> RunReviewSignoffCard {
        let failedVerdicts = document.verdicts.filter { !isPassingStatus($0.status) }
        let diagnosticIssues = document.diagnostics
            .filter { $0.severity.lowercased() != "info" }
            .map {
                RunReviewSignoffIssue(
                    severity: $0.severity,
                    label: $0.code,
                    message: $0.message,
                    repairActionHints: simulationRepairActionHints(
                        reason: $0.message,
                        actionDomainCatalog: actionDomainCatalog
                    ),
                    detailRows: simulationDiagnosticDetailRows($0)
                )
            }
        let verdictIssues = failedVerdicts.map { verdict in
            RunReviewSignoffIssue(
                severity: "error",
                label: verdict.name,
                message: "value=\(optionalFormatted(verdict.value)) target=\(formatted(verdict.target)) tolerance=\(formatted(verdict.tolerance))",
                repairActionHints: simulationRepairActionHints(
                    reason: "Improve simulation metric \(verdict.name) toward target \(formatted(verdict.target)).",
                    actionDomainCatalog: actionDomainCatalog
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
        artifact: FlowRunReviewArtifact,
        actionDomainCatalog: RunReviewActionDomainCatalog
    ) -> RunReviewSignoffCard {
        let issues = document.gateViolations.map {
            RunReviewSignoffIssue(
                severity: "error",
                label: "gate",
                message: $0,
                repairActionHints: postLayoutRepairActionHints(
                    reason: $0,
                    actionDomainCatalog: actionDomainCatalog
                )
            )
        } + document.diagnostics.map {
            RunReviewSignoffIssue(
                severity: "warning",
                label: "diagnostic",
                message: $0,
                repairActionHints: postLayoutRepairActionHints(
                    reason: $0,
                    actionDomainCatalog: actionDomainCatalog
                )
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
        _ bucket: DRCReviewBucket,
        actionDomainCatalog: RunReviewActionDomainCatalog
    ) -> [RunReviewSignoffRepairActionHint] {
        let operationID = drcLayoutOperationID(for: bucket)
        return actionDomainCatalog.repairHint(
            domainID: "layout-edit",
            operationID: operationID,
            reason: "Route \(drcBucketLabel(bucket)) through the registered planning and candidate runtime."
        ).map { [$0] } ?? []
    }

    private func lvsRepairActionHints(
        _ bucket: LVSReviewBucket,
        actionDomainCatalog: RunReviewActionDomainCatalog
    ) -> [RunReviewSignoffRepairActionHint] {
        var hints: [RunReviewSignoffRepairActionHint] = []
        if isLVSPortMismatch(bucket) {
            if let hint = actionDomainCatalog.repairHint(
                domainID: "layout-edit",
                operationID: "layout.add-label",
                reason: "Create or correct layout labels so extracted ports can match the schematic."
            ) {
                hints.append(hint)
            }
            if let hint = actionDomainCatalog.repairHint(
                domainID: "layout-edit",
                operationID: "layout.add-net",
                reason: "Create a missing layout net before labeling or reconnecting LVS-visible ports."
            ) {
                hints.append(hint)
            }
        }
        if requiresLVSPolicyRepair(bucket) {
            if let hint = actionDomainCatalog.repairHint(
                domainID: "lvs-signoff",
                operationID: "lvs.policy-repair",
                reason: "Review an auditable model or terminal equivalence policy update."
            ) {
                hints.append(hint)
            }
        }
        if isLVSParameterMismatch(bucket) {
            if let hint = actionDomainCatalog.repairHint(
                domainID: "simulation-analysis",
                operationID: "simulation.set-netlist-parameters",
                reason: "Edit schematic or extracted netlist parameters and verify the LVS metric again."
            ) {
                hints.append(hint)
            }
        }
        if hints.isEmpty {
            if let hint = actionDomainCatalog.repairHint(
                domainID: "layout-edit",
                operationID: "layout-command-replay",
                reason: "Generate a replayable layout edit after resolving the mismatch geometry."
            ) {
                hints.append(hint)
            }
        }
        return hints
    }

    private func pexRepairActionHints(
        corner: PEXReviewCorner,
        diagnostic: PEXReviewDiagnostic,
        actionDomainCatalog: RunReviewActionDomainCatalog
    ) -> [RunReviewSignoffRepairActionHint] {
        [
            actionDomainCatalog.repairHint(
                domainID: "pex-extraction",
                operationID: "pex.metric-recovery-objective",
                reason: "Recover PEX evidence for \(corner.cornerID) after \(diagnostic.code)."
            ),
            actionDomainCatalog.repairHint(
                domainID: "layout-edit",
                operationID: "layout-command-replay",
                reason: "Replay layout edits after resolving the extracted parasitic hotspot."
            ),
        ].compactMap { $0 }
    }

    private func pexNetRepairActionHints(
        corner: PEXReviewCorner,
        net: PEXReviewNet,
        actionDomainCatalog: RunReviewActionDomainCatalog
    ) -> [RunReviewSignoffRepairActionHint] {
        actionDomainCatalog.repairHint(
            domainID: "pex-extraction",
            operationID: "pex.metric-recovery-objective",
            reason: "Investigate \(net.name) in \(corner.cornerID) as a parasitic hotspot."
        ).map { [$0] } ?? []
    }

    private func simulationRepairActionHints(
        reason: String,
        actionDomainCatalog: RunReviewActionDomainCatalog
    ) -> [RunReviewSignoffRepairActionHint] {
        actionDomainCatalog.repairHint(
            domainID: "simulation-analysis",
            operationID: "simulation.metric-improvement-objective",
            reason: reason
        ).map { [$0] } ?? []
    }

    private func postLayoutRepairActionHints(
        reason: String,
        actionDomainCatalog: RunReviewActionDomainCatalog
    ) -> [RunReviewSignoffRepairActionHint] {
        actionDomainCatalog.repairHint(
            domainID: "pex-extraction",
            operationID: "pex.metric-recovery-objective",
            reason: reason
        ).map { [$0] } ?? []
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
                releaseArtifactLineageSection(artifact.binding),
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
                releaseArtifactLineageSection(artifact.binding),
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
                            ("Handoff artifact", result.payload.handoffBinding?.materializationDescription),
                            ("Streamed artifact", result.payload.streamOut?.streamedArtifact.materializationDescription),
                        ])
                    )]
                ),
                releaseArtifactLineageSection(artifact.binding),
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
                releaseArtifactLineageSection(artifact.binding),
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
        _ binding: FlowArtifactBinding
    ) -> RunReviewSignoffDetailSection {
        let reference = binding.reference
        return RunReviewSignoffDetailSection(
            title: "Artifact Lineage",
            rows: [RunReviewSignoffDetailRow(
                label: binding.logicalID,
                metrics: compactMetrics([
                    ("Path", binding.path),
                    ("SHA-256", reference.digest.hexadecimalValue),
                    ("Bytes", String(reference.byteCount)),
                    ("Producer kind", binding.producer?.kind.rawValue),
                    ("Producer", binding.producer?.identifier),
                    ("Version", binding.producer?.version),
                    ("Build", binding.producer?.build),
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
        let artifactID = artifact.binding.logicalID
        let path = artifact.binding.circuitStudioPresentationPath.lowercased()
        if artifactID == "release-authorization-result"
            || path.contains("release.authorization") && path.hasSuffix("result.json") {
            return .releaseAuthorization
        }
        if artifactID == "release-tapeout-result"
            || path.contains("release.tapeout") && path.hasSuffix("result.json") {
            return .tapeoutResult
        }
        if artifact.binding.kind == .release,
           artifact.binding.producer?.identifier == "native.release.signoff" {
            return .signoffBundle
        }
        if artifact.binding.kind == .release,
           artifact.binding.producer?.identifier == "native.release.tapeout" {
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
        if artifact.binding.kind == .measurement && path.hasSuffix("measurements.json") {
            return .simulationMeasurement
        }
        if artifactID == "post-layout-comparison" || path.hasSuffix("comparison-report.json") {
            return .postLayoutComparison
        }
        return nil
    }

    private func issueEvidenceArtifacts(
        primary: FlowRunReviewArtifact,
        relatedArtifacts: [FlowRunReviewArtifact]
    ) -> [FlowRunReviewArtifact] {
        var seenPaths = Set<String>()
        return ([primary] + relatedArtifacts).filter { artifact in
            seenPaths.insert(artifact.binding.circuitStudioPresentationPath).inserted
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

}
