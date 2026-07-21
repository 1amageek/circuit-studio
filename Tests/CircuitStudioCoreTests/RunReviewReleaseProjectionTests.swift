import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ReleaseCore
import SignoffEngine
import TapeoutEngine
import Testing
import ToolQualification
@testable import CircuitStudioApp

@Suite("Run review release projection", .timeLimit(.minutes(2)))
struct RunReviewReleaseProjectionTests {
    @Test @MainActor func canonicalReleaseArtifactsProduceTypedReviewCards() async throws {
        let hashes = ReleaseReviewTestHashes()
        let evidenceProducer = try ProducerIdentity(
            kind: .tool,
            identifier: "qualified-evidence-tool",
            version: "1.0.0",
            build: hashes.tool
        )
        let releaseProducer = try ProducerIdentity(
            kind: .engine,
            identifier: "native.release.signoff",
            version: "2.0.0",
            build: String(repeating: "a", count: 64)
        )
        let authorizationProducer = try ProducerIdentity(
            kind: .engine,
            identifier: "native.release.authorization",
            version: "2.0.0",
            build: String(repeating: "b", count: 64)
        )
        let tapeoutProducer = try ProducerIdentity(
            kind: .engine,
            identifier: "native.release.tapeout",
            version: "2.0.0",
            build: String(repeating: "c", count: 64)
        )
        let prefix = ".xcircuite/runs/run-signoff/stages/001-signoff/raw/release"
        let evidencePath = "\(prefix)/qualified-evidence.json"
        let bundlePath = "\(prefix)/signoff-bundle.json"
        let authorizationPath = "\(prefix)/authorization/result.json"
        let tapeoutPath = "\(prefix)/tapeout/result.json"
        let handoffPath = "\(prefix)/foundry-handoff.json"
        let xorFixture = try await ReleaseReviewXORFixture.make(
            prefix: prefix,
            layoutDigest: hashes.layout,
            evaluatedAt: Date(timeIntervalSince1970: 0)
        )
        let evidenceData = Data("{\"status\":\"passed\"}".utf8)
        let evidenceArtifact = try RunReviewTestSupport.artifactReference(
            artifactID: "qualified-release-evidence",
            path: evidencePath,
            payload: evidenceData,
            producer: evidenceProducer
        )

        let evidenceDigest = try CanonicalSignoffEvidenceDigester().digest([])
        let bundle = SignoffBundle(
            bundleID: "run-signoff-bundle",
            profileID: "production-signoff",
            designDigest: hashes.design,
            pdkDigest: xorFixture.pdkDigest,
            finalLayoutDigest: hashes.layout,
            axisResults: ReleaseSignoffAxis.allCases.map {
                SignoffAxisResult(
                    axis: $0,
                    disposition: .profileApprovedNotApplicable,
                    reason: "The production profile explicitly marks this axis as not applicable."
                )
            },
            waivers: [],
            evidenceArtifacts: [evidenceArtifact],
            toolQualificationScopes: [ToolQualificationScope(
                implementationID: "qualified-evidence-tool",
                toolVersion: "1.0.0",
                binaryDigest: hashes.tool,
                algorithmVersion: "1",
                processProfileID: "test-process",
                processProfileDigest: hashes.process,
                deckDigest: hashes.deck,
                pdkID: "test-pdk",
                pdkDigest: xorFixture.pdkDigest,
                oracle: ToolOracleQualificationScope(
                    implementationID: "independent-oracle",
                    version: "1.0.0",
                    binaryDigest: hashes.oracle
                )
            )],
            evidenceDigest: evidenceDigest,
            issuedAt: Date(timeIntervalSince1970: 0)
        )
        let bundleData = try bundle.canonicalData()
        let bundleArtifact = try RunReviewTestSupport.artifactReference(
            artifactID: "canonical-signoff-bundle",
            path: bundlePath,
            payload: bundleData,
            kind: .release,
            producer: releaseProducer
        )

        let planArtifact = try RunReviewTestSupport.artifactReference(
            artifactID: "release-plan",
            path: "\(prefix)/plan.json",
            payload: Data("{}".utf8)
        )
        let blockedDiagnostic = DesignDiagnostic(
            code: .trusted("RELEASE_BLOCKED_FOR_TEST"),
            severity: .error,
            summary: "Release authorization is intentionally blocked."
        )
        let timestamp = Date(timeIntervalSince1970: 1)
        let authorizationProvenance = try ExecutionProvenance(
            producer: authorizationProducer,
            inputs: [planArtifact],
            invocation: try .inProcess(entryPoint: "ReleaseEngine.DefaultReleaseAuthorizer.execute"),
            startedAt: timestamp,
            completedAt: timestamp
        )
        let authorization = ReleaseAuthorizationResult(
            status: .blocked,
            signoffBundle: nil,
            approval: FlowApprovalRecord(
                runID: "run-signoff",
                stageID: "release.authorization",
                verdict: .rejected,
                reviewer: "reviewer",
                reviewerKind: .human,
                createdAt: timestamp,
                evidence: FlowApprovalEvidenceBinding(
                    plan: planArtifact,
                    stageResult: bundleArtifact
                )
            ),
            diagnostics: [blockedDiagnostic],
            provenance: authorizationProvenance
        )
        let authorizationData = try releaseJSONData(authorization)
        let authorizationArtifact = try RunReviewTestSupport.artifactReference(
            artifactID: "release-authorization-result",
            path: authorizationPath,
            payload: authorizationData,
            producer: authorizationProducer
        )

        let tapeoutProvenance = try ExecutionProvenance(
            producer: tapeoutProducer,
            inputs: [bundleArtifact],
            invocation: try .inProcess(entryPoint: "TapeoutEngine.DefaultTapeoutPackaging.execute"),
            startedAt: timestamp,
            completedAt: timestamp
        )
        let tapeout = TapeoutResult(
            schemaVersion: TapeoutRequest.currentSchemaVersion,
            runID: "run-signoff",
            status: .blocked,
            diagnostics: [blockedDiagnostic],
            artifacts: [],
            metadata: tapeoutProvenance,
            payload: TapeoutPayload(handoffArtifact: nil, checksum: nil)
        )
        let tapeoutData = try releaseJSONData(tapeout)
        let tapeoutArtifact = try RunReviewTestSupport.artifactReference(
            artifactID: "release-tapeout-result",
            path: tapeoutPath,
            payload: tapeoutData,
            producer: tapeoutProducer
        )

        let unsignedHandoff = FoundryHandoffManifest(
            releaseID: "run-signoff-tapeout",
            foundryID: "test-foundry",
            signoffBundleArtifactDigest: bundleArtifact.digest.hexadecimalValue,
            designDigest: hashes.design,
            pdkDigest: xorFixture.pdkDigest,
            layoutDigest: hashes.layout,
            artifacts: [evidenceArtifact] + xorFixture.retainedArtifacts,
            evidenceIDs: ["qualified-release-evidence"],
            layoutXORResult: xorFixture.result,
            generatedAt: Date(timeIntervalSince1970: 0),
            manifestDigest: hashes.empty
        )
        let handoff = FoundryHandoffManifest(
            releaseID: unsignedHandoff.releaseID,
            foundryID: unsignedHandoff.foundryID,
            signoffBundleArtifactDigest: unsignedHandoff.signoffBundleArtifactDigest,
            designDigest: unsignedHandoff.designDigest,
            pdkDigest: unsignedHandoff.pdkDigest,
            layoutDigest: unsignedHandoff.layoutDigest,
            artifacts: unsignedHandoff.artifacts,
            evidenceIDs: unsignedHandoff.evidenceIDs,
            layoutXORResult: unsignedHandoff.layoutXORResult,
            generatedAt: unsignedHandoff.generatedAt,
            manifestDigest: try unsignedHandoff.computedManifestDigest()
        )
        let handoffData = try handoff.canonicalData()
        let handoffArtifact = try RunReviewTestSupport.artifactReference(
            artifactID: "foundry-handoff-manifest",
            path: handoffPath,
            payload: handoffData,
            kind: .release,
            producer: tapeoutProducer
        )

        let fixture = try await RunReviewSignoffFixture.make(
            additionalArtifacts: [
                evidenceArtifact,
                bundleArtifact,
                authorizationArtifact,
                tapeoutArtifact,
                handoffArtifact,
            ] + xorFixture.retainedArtifacts,
            additionalArtifactPayloads: xorFixture.artifactPayloads.merging([
                evidencePath: evidenceData,
                bundlePath: bundleData,
                authorizationPath: authorizationData,
                tapeoutPath: tapeoutData,
                handoffPath: handoffData,
            ]) { _, releasePayload in releasePayload }
        )
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        #expect(fixture.review.signoff.decodeIssues.isEmpty)
        let releaseAxisCards = fixture.review.signoff.cards.filter {
            $0.domain.hasPrefix("Release / ")
        }
        #expect(releaseAxisCards.count == ReleaseSignoffAxis.allCases.count)
        #expect(Set(releaseAxisCards.map { $0.id }).count == ReleaseSignoffAxis.allCases.count)
        #expect(Set(releaseAxisCards.map { $0.status }) == [ReleaseAxisDisposition.profileApprovedNotApplicable.rawValue])
        #expect(releaseAxisCards.allSatisfy { $0.passed == true })

        let bundleCard = try #require(fixture.review.signoff.cards.first {
            $0.title == "Release Signoff Bundle"
        })
        #expect(bundleCard.passed == true)
        #expect(bundleCard.primaryMetrics.contains { $0.label == "Axes" && $0.value == "25" })
        #expect(bundleCard.detailSections.contains { $0.title == "Artifact Lineage" })

        let authorizationCard = try #require(fixture.review.signoff.cards.first {
            $0.domain == "Release Authorization"
        })
        #expect(authorizationCard.passed == false)
        #expect(authorizationCard.issues.map { $0.label } == ["RELEASE_BLOCKED_FOR_TEST"])

        let tapeoutCard = try #require(fixture.review.signoff.cards.first {
            $0.domain == "Tapeout"
        })
        #expect(tapeoutCard.passed == false)
        #expect(tapeoutCard.status == ReleaseExecutionStatus.blocked.rawValue)

        let handoffCard = try #require(fixture.review.signoff.cards.first {
            $0.domain == "Tapeout Handoff"
        })
        #expect(handoffCard.passed == true)
        #expect(handoffCard.primaryMetrics.contains { $0.label == "Foundry" && $0.value == "test-foundry" })

        let drilldown = fixture.service.interactiveSignoffDrilldown(from: fixture.review)
        #expect(drilldown.section(for: .release)?.items.count == ReleaseSignoffAxis.allCases.count + 1)
        #expect(drilldown.section(for: .authorization)?.items.count == 1)
        #expect(drilldown.section(for: .tapeout)?.items.count == 2)
        let releaseItemIDs = drilldown.section(for: .release)?.items.map { $0.itemID } ?? []
        #expect(Set(releaseItemIDs).count == releaseItemIDs.count)
    }

    @Test @MainActor func unsupportedReleaseSchemaIsReportedInsteadOfPassing() async throws {
        let path = ".xcircuite/runs/run-signoff/stages/001-signoff/raw/release/authorization/result.json"
        let payload = Data("{\"schemaVersion\":999}".utf8)
        let producer = try ProducerIdentity(
            kind: .engine,
            identifier: "native.release.authorization",
            version: "2.0.0",
            build: String(repeating: "b", count: 64)
        )
        let artifact = try RunReviewTestSupport.artifactReference(
            artifactID: "release-authorization-result",
            path: path,
            payload: payload,
            producer: producer
        )
        let fixture = try await RunReviewSignoffFixture.make(
            additionalArtifacts: [artifact],
            additionalArtifactPayloads: [path: payload]
        )
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        #expect(!fixture.review.signoff.cards.contains { $0.domain == "Release Authorization" })
        #expect(fixture.review.signoff.decodeIssues.contains { $0.artifactPath == path })
    }

    private func releaseJSONData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
}

private struct ReleaseReviewTestHashes {
    let design = String(repeating: "1", count: 64)
    let pdk = String(repeating: "2", count: 64)
    let layout = String(repeating: "3", count: 64)
    let tool = String(repeating: "4", count: 64)
    let process = String(repeating: "5", count: 64)
    let deck = String(repeating: "6", count: 64)
    let oracle = String(repeating: "7", count: 64)
    let empty = String(repeating: "0", count: 64)
}
