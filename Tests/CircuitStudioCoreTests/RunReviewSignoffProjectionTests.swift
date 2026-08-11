import Foundation
import Testing
import CircuiteFoundation
import DesignFlowKernel
import ToolQualification
import Xcircuite
@testable import CircuitStudioApp
@testable import CircuitStudioCore

@Suite("Run review signoff projection", .timeLimit(.minutes(2)))
struct RunReviewSignoffProjectionTests {
    @Test func signoffArtifactIndexMaterializesSearchMetadataOnce() throws {
        let artifactCount = 1_200
        let artifacts = try (0..<artifactCount).map { index in
            let domain = switch index % 4 {
            case 0: "drc"
            case 1: "lvs"
            case 2: "pex"
            default: "simulation"
            }
            return FlowRunReviewArtifact(
                binding: try RunReviewTestSupport.artifactBinding(
                    artifactID: "\(domain)-artifact-\(index)",
                    path: ".xcircuite/runs/performance/\(domain)-artifact-\(index).json"
                ),
                purpose: index % 11 == 0 ? .stageResult : .stageSummary,
                stageID: index % 11 == 0 ? "shared-stage" : "\(domain)-stage"
            )
        }
        let primary = try #require(artifacts.first)
        let index = RunReviewSignoffArtifactIndex(artifacts: artifacts)

        #expect(index.indexedArtifactCount == artifactCount)
        for _ in 0..<100 {
            let related = index.relatedArtifacts(for: primary, artifactKind: .drc)
            #expect(!related.contains(primary))
            #expect(related.allSatisfy {
                $0.binding.logicalID.contains("drc")
                    || $0.stageID == primary.stageID && $0.purpose == .stageResult
            })
        }
    }

    @Test @MainActor func retainedActionDomainSnapshotDrivesRepairMetadata() async throws {
        let runID = "run-signoff"
        let snapshotPath = ".xcircuite/runs/\(runID)/planning/action-domain-snapshot.json"
        let snapshot = XcircuitePlanningActionDomainSnapshot(
            runID: runID,
            generatedAt: "2026-07-26T00:00:00Z",
            domains: [
                XcircuiteActionDomain(
                    domainID: "layout-edit",
                    ownerPackages: ["semiconductor-layout"],
                    operations: [
                        XcircuiteActionDomainOperation(
                            operationID: "layout.resize-shape",
                            maturity: .implemented,
                            inputRefs: ["retained-document-ref", "retained-shape-ref"],
                            preconditions: ["retained-shape-exists"],
                            effects: ["retained-shape-updated"],
                            producedArtifacts: ["retained-layout-document"],
                            verificationGates: ["retained-integrity-gate"],
                            reversible: true,
                            readinessState: .behaviorallyVerified,
                            registrationKind: .mutation,
                            handlerVersion: "retained-v2",
                            handlerIdentity: "retained.layout.resize-shape",
                            candidateMutationExecutable: true
                        ),
                    ]
                ),
            ]
        )
        let snapshotData = try JSONEncoder().encode(snapshot)
        let snapshotBinding = try RunReviewTestSupport.artifactBinding(
            artifactID: "planning-action-domain-snapshot",
            path: snapshotPath,
            payload: snapshotData,
            kind: .other,
            format: .json
        )
        let fixture = try await RunReviewSignoffFixture.make(
            additionalArtifacts: [snapshotBinding],
            additionalArtifactPayloads: [snapshotPath: snapshotData]
        )
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        let drc = try #require(fixture.review.signoff.cards.first { $0.domain == "DRC" })
        let repairAction = try #require(drc.issues.first?.repairActionHints.first)
        #expect(repairAction.domainID == "layout-edit")
        #expect(repairAction.operationID == "layout.resize-shape")
        #expect(repairAction.readinessState == .behaviorallyVerified)
        #expect(repairAction.requiredInputRefs == ["retained-document-ref", "retained-shape-ref"])
        #expect(repairAction.verificationGates == ["retained-integrity-gate"])
    }

    @Test func repairHintsRequireExecutableCandidateMutationRegistration() throws {
        let catalog = RunReviewActionDomainCatalog(snapshot: XcircuitePlanningActionDomainSnapshot(
            runID: "run-signoff",
            generatedAt: "2026-07-26T00:00:00Z",
            domains: [
                XcircuiteActionDomain(
                    domainID: "layout-edit",
                    ownerPackages: ["semiconductor-layout"],
                    operations: [
                        XcircuiteActionDomainOperation(
                            operationID: "layout.unregistered-edit",
                            maturity: .planned,
                            inputRefs: [],
                            preconditions: [],
                            effects: [],
                            producedArtifacts: [],
                            verificationGates: [],
                            reversible: true,
                            readinessState: .declared,
                            candidateMutationExecutable: false
                        ),
                        XcircuiteActionDomainOperation(
                            operationID: "layout.stage-only",
                            maturity: .implemented,
                            inputRefs: [],
                            preconditions: [],
                            effects: [],
                            producedArtifacts: [],
                            verificationGates: [],
                            reversible: true,
                            readinessState: .registered,
                            registrationKind: .stage,
                            handlerVersion: "stage-v1",
                            handlerIdentity: "stage.layout-only",
                            candidateMutationExecutable: false
                        ),
                        XcircuiteActionDomainOperation(
                            operationID: "layout.registered-edit",
                            maturity: .planned,
                            inputRefs: ["layout-ref"],
                            preconditions: [],
                            effects: ["layout-updated"],
                            producedArtifacts: ["layout-candidate"],
                            verificationGates: ["native-drc"],
                            reversible: true,
                            readinessState: .registered,
                            registrationKind: .mutation,
                            handlerVersion: "mutation-v1",
                            handlerIdentity: "mutation.layout-edit",
                            candidateMutationExecutable: true
                        ),
                    ]
                ),
            ]
        ))

        #expect(catalog.repairHint(
            domainID: "layout-edit",
            operationID: "layout.unregistered-edit",
            reason: "unregistered"
        ) == nil)
        #expect(catalog.repairHint(
            domainID: "layout-edit",
            operationID: "layout.stage-only",
            reason: "stage-only"
        ) == nil)
        let executableHint = try #require(catalog.repairHint(
            domainID: "layout-edit",
            operationID: "layout.registered-edit",
            reason: "registered"
        ))
        #expect(executableHint.readinessState == .registered)
        #expect(executableHint.requiredInputRefs == ["layout-ref"])
        #expect(executableHint.verificationGates == ["native-drc"])
    }

    @Test @MainActor func missingActionDomainSnapshotProducesNoRepairHints() async throws {
        let fixture = try await RunReviewSignoffFixture.make(
            includeDefaultActionDomainSnapshot: false
        )
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        #expect(fixture.review.signoff.cards
            .flatMap(\.issues)
            .allSatisfy { $0.repairActionHints.isEmpty })
    }

    @Test @MainActor func signoffArtifactsAreVisibleInTheReview() async throws {
        let fixture = try await RunReviewSignoffFixture.make()
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }
        let root = fixture.root
        let runID = fixture.runID
        let rawPrefix = fixture.rawPrefix
        let stageResultPath = fixture.stageResultPath
        let drcPath = fixture.drcPath
        let drcLogPath = fixture.drcLogPath
        let drcEnvelopePath = fixture.drcEnvelopePath
        let lvsPath = fixture.lvsPath
        let lvsLogPath = fixture.lvsLogPath
        let pexPath = fixture.pexPath
        let simulationSummaryPath = fixture.simulationSummaryPath
        let preLayoutWaveformPath = fixture.preLayoutWaveformPath
        let postLayoutWaveformPath = fixture.postLayoutWaveformPath
        let comparisonPath = fixture.comparisonPath
        let designSpecPath = fixture.designSpecPath
        let layoutDocumentPath = fixture.layoutDocumentPath
        let designUnitPath = fixture.designUnitPath
        let generatedLayoutCorpusPath = fixture.generatedLayoutCorpusPath
        let retainedSignoffReportPath = fixture.retainedSignoffReportPath
        let drcOracleLaneReportPath = fixture.drcOracleLaneReportPath
        let waiverSourcePath = fixture.waiverSourcePath
        let service = fixture.service
        let review = fixture.review
        let verificationContext = try await service.waiverEditVerificationContext(
            review: review,
            projectRoot: root
        )
        #expect(verificationContext.designSpecArtifact.binding.circuitStudioPresentationPath == designSpecPath)
        #expect(verificationContext.layoutDocumentArtifact.binding.circuitStudioPresentationPath == layoutDocumentPath)
        #expect(verificationContext.designUnitArtifact?.binding.circuitStudioPresentationPath == designUnitPath)
        #expect(review.signoff.decodeIssues.isEmpty)
        #expect(review.signoff.cards.map(\.domain) == [
            "DRC",
            "LVS",
            "PEX",
            "Oracle",
            "Oracle",
            "Simulation",
            "Simulation",
            "Post-layout",
        ])

        let drc = try #require(review.signoff.cards.first { $0.domain == "DRC" })
        #expect(drc.passed == false)
        #expect(drc.primaryMetrics.contains { $0.label == "Active" && $0.value == "2" })
        #expect(drc.issues.first?.label == "M1.WIDTH")
        #expect(drc.issues.first?.suggestedFixes == ["widen-metal"])
        let drcIssue = try #require(drc.issues.first)
        #expect(drcIssue.evidenceArtifacts.map(\.binding.circuitStudioPresentationPath).contains(drcPath))
        #expect(drcIssue.evidenceArtifacts.map(\.binding.circuitStudioPresentationPath).contains(drcLogPath))
        #expect(drcIssue.evidenceArtifacts.map(\.binding.circuitStudioPresentationPath).contains(drcEnvelopePath))
        #expect(drcIssue.evidenceArtifacts.map(\.binding.circuitStudioPresentationPath).contains(stageResultPath))
        #expect(!drcIssue.evidenceArtifacts.map(\.binding.circuitStudioPresentationPath).contains(lvsPath))
        let drcEvaluation = try #require(drc.evaluationEvidence.first)
        #expect(drcEvaluation.artifactID == "drc-summary")
        #expect(drcEvaluation.evaluationStatus == "rejected")
        #expect(drcEvaluation.observedChannelCount == 1)
        #expect(drcEvaluation.missingChannelIDs == ["drc-magic-oracle-agreement"])
        #expect(drcEvaluation.uncalibratedChannelIDs == ["drc-qualified-calibration"])
        #expect(drcEvaluation.feedbackSignals.map(\.signalID) == ["drc-route-width-feedback"])
        #expect(drcEvaluation.feedbackSignals.first?.suggestedActions == ["apply-drc-repair-hint"])
        let drcRepairAction = try #require(drcIssue.repairActionHints.first)
        #expect(drcRepairAction.domainID == "layout-edit")
        #expect(drcRepairAction.operationID == "layout.resize-shape")
        #expect(drcRepairAction.readinessState == .registered)
        #expect(drcRepairAction.requiredInputRefs == ["document-ref", "cell-ref", "shape-ref"])
        #expect(drcRepairAction.verificationGates == ["artifact-integrity", "native-drc", "native-lvs"])
        let drcViolationDetail = try #require(drcIssue.detailRows.first { $0.label == "Violation" })
        #expect(drcViolationDetail.metrics.contains { $0.label == "Rule" && $0.value == "M1.WIDTH" })
        #expect(drcViolationDetail.metrics.contains { $0.label == "Layer" && $0.value == "met1" })
        #expect(drcViolationDetail.metrics.contains { $0.label == "Measured" && $0.value == "0.12" })
        #expect(drcViolationDetail.metrics.contains { $0.label == "Required" && $0.value == "0.14" })
        #expect(drcViolationDetail.metrics.contains { $0.label == "Region" && $0.value == "x=10 y=20 w=0.12 h=0.4" })
        #expect(drcViolationDetail.metrics.contains { $0.label == "Shapes" && $0.value == "m1-segment-a, m1-segment-b" })
        #expect(drcViolationDetail.metrics.contains { $0.label == "Nets" && $0.value == "out" })
        let drcSourcePanel = try #require(drc.detailSections.first { $0.title == "DRC Sources" })
        let drcSourceRow = try #require(drcSourcePanel.rows.first { $0.label == "Source Artifacts" })
        #expect(drcSourceRow.metrics.contains { $0.label == "Report" && $0.value.hasSuffix(drcPath) })
        #expect(drcSourceRow.metrics.contains { $0.label == "Manifest" && $0.value.hasSuffix("drc-artifact-manifest.json") })
        let drcBucketPanel = try #require(drc.detailSections.first { $0.title == "Violation Buckets" })
        let drcBucketRow = try #require(drcBucketPanel.rows.first { $0.label == "M1.WIDTH" })
        #expect(drcBucketRow.metrics.contains { $0.label == "Active" && $0.value == "2" })
        #expect(drcBucketRow.metrics.contains { $0.label == "Waived" && $0.value == "1" })
        #expect(drcBucketRow.metrics.contains { $0.label == "Region" && $0.value == "x=10 y=20 w=0.12 h=0.4" })
        #expect(drcBucketRow.metrics.contains { $0.label == "Shapes" && $0.value == "m1-segment-a, m1-segment-b" })
        #expect(drcBucketRow.metrics.contains { $0.label == "Nets" && $0.value == "out" })
        #expect(drcBucketRow.metrics.contains { $0.label == "Fixes" && $0.value == "widen-metal" })
        let drcEvaluationPanel = try #require(drc.detailSections.first { $0.title == "Artifact Evaluation" })
        let drcEvaluationRow = try #require(drcEvaluationPanel.rows.first { $0.label == "Evaluation" })
        #expect(drcEvaluationRow.metrics.contains { $0.label == "Status" && $0.value == "rejected" })
        #expect(drcEvaluationRow.metrics.contains { $0.label == "Observed" && $0.value == "1" })
        #expect(drcEvaluationRow.metrics.contains { $0.label == "Missing" && $0.value == "1" })
        #expect(drcEvaluationRow.metrics.contains { $0.label == "Uncalibrated" && $0.value == "1" })
        let drcChannelsPanel = try #require(drc.detailSections.first { $0.title == "Evaluation Channels" })
        #expect(drcChannelsPanel.rows.first?.label == "drc-magic-oracle-agreement")
        let drcFeedbackPanel = try #require(drc.detailSections.first { $0.title == "Feedback Signals" })
        let drcFeedbackRow = try #require(drcFeedbackPanel.rows.first { $0.label == "drc-route-width-feedback" })
        #expect(drcFeedbackRow.metrics.contains { $0.label == "Routing" && $0.value == "localSurface" })
        #expect(drcFeedbackRow.metrics.contains { $0.label == "Actions" && $0.value == "apply-drc-repair-hint" })
        #expect(drc.relatedArtifacts.contains { $0.binding.logicalID == "drc-raw-log" })
        #expect(drc.relatedArtifacts.contains { $0.binding.logicalID == "drc-repair-hints" })
        #expect(drc.relatedArtifacts.contains { $0.binding.circuitStudioPresentationPath == drcEnvelopePath })
        #expect(drc.relatedArtifacts.contains { $0.purpose.rawValue == "stage-result" })
        #expect(!drc.relatedArtifacts.contains { $0.binding.logicalID == "lvs-summary" })
        let drcLogPreview = try await service.loadArtifactPreview(
            runID: runID,
            artifactPath: drcLogPath,
            projectRoot: root,
            maxBytes: 12
        )
        #expect(drcLogPreview.truncated)
        #expect(drcLogPreview.text == "DRC_SUMMARY ")
        let drcJSONPreview = try await service.loadArtifactPreview(
            runID: runID,
            artifactPath: drcPath,
            projectRoot: root
        )
        #expect(drcJSONPreview.structuredPreview == "{manifestURL, reportURL, schemaVersion, summary}")
        #expect(drcJSONPreview.parseIssue == nil)
        await #expect(throws: RunReviewServiceError.artifactPreviewNotFound(
            runID: runID,
            artifactPath: "\(rawPrefix)/unknown.json"
        )) {
            try await service.loadArtifactPreview(
                runID: runID,
                artifactPath: "\(rawPrefix)/unknown.json",
                projectRoot: root
            )
        }
        let lvs = try #require(review.signoff.cards.first { $0.domain == "LVS" })
        #expect(lvs.status == "mismatch")
        #expect(lvs.passed == false)
        #expect(lvs.primaryMetrics.contains { $0.label == "Active" && $0.value == "1" })
        #expect(lvs.primaryMetrics.contains { $0.label == "Execution" && $0.value == "completed" })
        #expect(lvs.primaryMetrics.contains { $0.label == "Verdict" && $0.value == "mismatch" })
        #expect(lvs.primaryMetrics.contains { $0.label == "Readiness" && $0.value == "ready" })
        #expect(lvs.issues.first?.label == "DEVICE_COUNT")
        let lvsIssue = try #require(lvs.issues.first)
        #expect(lvsIssue.evidenceArtifacts.map(\.binding.circuitStudioPresentationPath).contains(lvsPath))
        #expect(lvsIssue.evidenceArtifacts.map(\.binding.circuitStudioPresentationPath).contains(lvsLogPath))
        #expect(!lvsIssue.evidenceArtifacts.map(\.binding.circuitStudioPresentationPath).contains(drcPath))
        #expect(lvsIssue.repairActionHints.map(\.operationID) == [
            "layout.add-label",
            "layout.add-net",
        ])
        #expect(lvsIssue.repairActionHints.allSatisfy { $0.domainID == "layout-edit" })
        let lvsMismatchDetail = try #require(lvsIssue.detailRows.first { $0.label == "Mismatch" })
        #expect(lvsMismatchDetail.metrics.contains { $0.label == "Component" && $0.value == "nmos" })
        #expect(lvsMismatchDetail.metrics.contains { $0.label == "Layout" && $0.value == "nfet" })
        #expect(lvsMismatchDetail.metrics.contains { $0.label == "Schematic" && $0.value == "nfet" })
        #expect(lvsMismatchDetail.metrics.contains { $0.label == "Layout count" && $0.value == "1" })
        #expect(lvsMismatchDetail.metrics.contains { $0.label == "Schematic count" && $0.value == "2" })
        #expect(lvsMismatchDetail.metrics.contains { $0.label == "Layout ports" && $0.value == "D, G, S" })
        #expect(lvsMismatchDetail.metrics.contains { $0.label == "Schematic ports" && $0.value == "D, G, S, B" })
        let lvsSourcePanel = try #require(lvs.detailSections.first { $0.title == "LVS Sources" })
        let lvsSourceRow = try #require(lvsSourcePanel.rows.first { $0.label == "Source Artifacts" })
        #expect(lvsSourceRow.metrics.contains { $0.label == "Report" && $0.value.hasSuffix(lvsPath) })
        #expect(lvsSourceRow.metrics.contains { $0.label == "Manifest" && $0.value.hasSuffix("lvs-artifact-manifest.json") })
        #expect(lvsSourceRow.metrics.contains { $0.label == "Layout input" && $0.value == "layout-netlist" })
        #expect(lvsSourceRow.metrics.contains { $0.label == "Extracted" && $0.value.hasSuffix("layout-extracted.spice") })
        let lvsBucketPanel = try #require(lvs.detailSections.first { $0.title == "Mismatch Buckets" })
        let lvsBucketRow = try #require(lvsBucketPanel.rows.first { $0.label == "DEVICE_COUNT" })
        #expect(lvsBucketRow.metrics.contains { $0.label == "Category" && $0.value == "device-count" })
        #expect(lvsBucketRow.metrics.contains { $0.label == "Layout count" && $0.value == "1" })
        #expect(lvsBucketRow.metrics.contains { $0.label == "Schematic count" && $0.value == "2" })
        #expect(lvsBucketRow.metrics.contains { $0.label == "Schematic ports" && $0.value == "D, G, S, B" })
        #expect(lvsBucketRow.metrics.contains { $0.label == "Fixes" && $0.value == "inspect-missing-device" })
        #expect(lvs.relatedArtifacts.contains { $0.binding.logicalID == "lvs-raw-log" })
        #expect(lvs.relatedArtifacts.contains { $0.binding.logicalID == "lvs-repair-hints" })

        let pex = try #require(review.signoff.cards.first { $0.domain == "PEX" })
        #expect(pex.passed == false)
        #expect(pex.primaryMetrics.contains { $0.label == "Failed" && $0.value == "1" })
        #expect(pex.issues.contains { $0.label == "ss:PEX_CORNER_FAILED" })
        let pexIssue = try #require(pex.issues.first { $0.label == "ss:PEX_CORNER_FAILED" })
        #expect(pexIssue.evidenceArtifacts.map(\.binding.circuitStudioPresentationPath).contains(pexPath))
        let pexDiagnosticDetail = try #require(pexIssue.detailRows.first { $0.label == "Diagnostic" })
        #expect(pexDiagnosticDetail.metrics.contains { $0.label == "Corner" && $0.value == "ss" })
        #expect(pexDiagnosticDetail.metrics.contains { $0.label == "Code" && $0.value == "PEX_CORNER_FAILED" })
        #expect(pexIssue.repairActionHints.map(\.operationID) == [
            "pex.metric-recovery-objective",
            "layout-command-replay",
        ])
        let pexRecoveryAction = try #require(pexIssue.repairActionHints.first)
        #expect(pexRecoveryAction.domainID == "pex-extraction")
        #expect(pexRecoveryAction.readinessState == .registered)
        let layoutReplayAction = try #require(pexIssue.repairActionHints.last)
        #expect(layoutReplayAction.domainID == "layout-edit")
        #expect(layoutReplayAction.readinessState == .registered)
        #expect(layoutReplayAction.requiredInputRefs == ["layout-command-request"])
        #expect(layoutReplayAction.verificationGates == ["artifact-integrity"])
        let pexCornerPanel = try #require(pex.detailSections.first { $0.title == "Corners" })
        let failedCornerRow = try #require(pexCornerPanel.rows.first { $0.label == "ss" })
        #expect(failedCornerRow.metrics.contains { $0.label == "Status" && $0.value == "failed" })
        #expect(failedCornerRow.metrics.contains { $0.label == "Diagnostics" && $0.value == "1" })
        let pexDiagnosticPanel = try #require(pex.detailSections.first { $0.title == "PEX Diagnostics" })
        let pexDiagnosticRow = try #require(pexDiagnosticPanel.rows.first { $0.label == "ss:PEX_CORNER_FAILED" })
        #expect(pexDiagnosticRow.metrics.contains { $0.label == "Message" && $0.value == "missing SPEF" })
        let pexTopNetPanel = try #require(pex.detailSections.first { $0.title == "Top Nets" })
        let pexTopNetRow = try #require(pexTopNetPanel.rows.first { $0.label == "tt:out" })
        #expect(pexTopNetRow.metrics.contains { $0.label == "Nodes" && $0.value == "4" })
        let pexSourcePanel = try #require(pex.detailSections.first { $0.title == "PEX Sources" })
        let pexSourceRow = try #require(pexSourcePanel.rows.first { $0.label == "Source Artifacts" })
        #expect(pexSourceRow.metrics.contains { $0.label == "Manifest" && $0.value.hasSuffix("pex-artifact-manifest.json") })

        let corpus = try #require(review.signoff.cards.first { $0.title == "Generated Layout Signoff Corpus" })
        #expect(corpus.domain == "Oracle")
        #expect(corpus.passed == false)
        #expect(corpus.primaryMetrics.contains { $0.label == "Cases" && $0.value == "2" })
        #expect(corpus.primaryMetrics.contains { $0.label == "Oracle ready" && $0.value == "3/4" })
        #expect(corpus.primaryMetrics.contains { $0.label == "Evidence refs" && $0.value == "3" })
        #expect(corpus.issues.contains { $0.label == "standard-gds-lvs-fail:case-disagreement" })
        #expect(corpus.issues.contains { $0.label == "standard-gds-lvs-fail:lvs:oracle-readiness" })
        #expect(corpus.issues.contains { $0.label == "standard-gds-lvs-fail:pex:oracle-readiness" })
        #expect(corpus.issues.contains { $0.label == "standard-gds-lvs-fail:020-lvs:stage-disagreement" })
        let corpusCasePanel = try #require(corpus.detailSections.first { $0.title == "Case Disagreements" })
        let failedCaseRow = try #require(corpusCasePanel.rows.first { $0.label == "standard-gds-lvs-fail" })
        #expect(failedCaseRow.metrics.contains { $0.label == "Run" && $0.value == "failed" })
        #expect(failedCaseRow.metrics.contains { $0.label == "Expected" && $0.value == "succeeded" })
        let corpusReadinessPanel = try #require(corpus.detailSections.first { $0.title == "Oracle Readiness" })
        #expect(corpusReadinessPanel.rows.contains { $0.label == "standard-gds-lvs-fail:lvs" })
        let corpusEvidencePanel = try #require(corpus.detailSections.first { $0.title == "Oracle Evidence Refs" })
        #expect(corpusEvidencePanel.rows.contains {
            $0.label == "standard-gds-drc-pass:drc:2"
                && $0.metrics.contains { $0.label == "Path" && $0.value == drcOracleLaneReportPath }
        })
        let corpusStagePanel = try #require(corpus.detailSections.first { $0.title == "Case Stage Results" })
        let lvsStageRow = try #require(corpusStagePanel.rows.first { $0.label == "standard-gds-lvs-fail:020-lvs" })
        #expect(lvsStageRow.metrics.contains { $0.label == "Matches" && $0.value == "false" })
        #expect(corpus.relatedArtifacts.contains { $0.binding.logicalID == "retained-signoff-report" })
        #expect(corpus.relatedArtifacts.contains { $0.binding.logicalID == "drc-external-oracle-report" })

        let retainedOracle = try #require(review.signoff.cards.first { $0.title == "Retained Signoff Oracle Dashboard" })
        #expect(retainedOracle.domain == "Oracle")
        #expect(retainedOracle.passed == false)
        #expect(retainedOracle.primaryMetrics.contains { $0.label == "Suite" && $0.value == "generated-layout-signoff-ladder" })
        #expect(retainedOracle.primaryMetrics.contains { $0.label == "Failed" && $0.value == "1" })
        #expect(retainedOracle.issues.contains { $0.label == "lvs:retained-oracle-lane" })
        #expect(retainedOracle.issues.contains { $0.label == "lvs-oracle-disagreement" })
        let retainedLanePanel = try #require(retainedOracle.detailSections.first { $0.title == "External Oracle Lanes" })
        let retainedLVSRow = try #require(retainedLanePanel.rows.first { $0.label == "lvs" })
        #expect(retainedLVSRow.metrics.contains { $0.label == "Agreement" && $0.value == "0.8" })
        let retainedReportPanel = try #require(retainedOracle.detailSections.first { $0.title == "Lane Report Refs" })
        #expect(retainedReportPanel.rows.contains {
            $0.label == "drc"
                && $0.metrics.contains { $0.label == "Path" && $0.value == drcOracleLaneReportPath }
        })

        let simulationMetric = try #require(review.signoff.cards.first {
            $0.domain == "Simulation" && $0.title == "tran"
        })
        #expect(simulationMetric.passed == false)
        #expect(simulationMetric.issues.contains { $0.label == "tpd" })
        let timingIssue = try #require(simulationMetric.issues.first { $0.label == "tpd" })
        #expect(timingIssue.evidenceArtifacts.map(\.binding.circuitStudioPresentationPath).contains(simulationSummaryPath))
        #expect(timingIssue.evidenceArtifacts.map(\.binding.circuitStudioPresentationPath).contains(postLayoutWaveformPath))
        #expect(timingIssue.repairActionHints.first?.operationID == "simulation.metric-improvement-objective")
        let timingVerdictDetail = try #require(timingIssue.detailRows.first { $0.label == "Verdict" })
        #expect(timingVerdictDetail.metrics.contains { $0.label == "Metric" && $0.value == "tpd" })
        #expect(timingVerdictDetail.metrics.contains { $0.label == "Value" && $0.value == "1.4e-09" })
        #expect(timingVerdictDetail.metrics.contains { $0.label == "Target" && $0.value == "1e-09" })
        #expect(simulationMetric.relatedArtifacts.contains { $0.binding.logicalID == "post-layout-waveform" })
        let waveformPreview = try await service.loadArtifactPreview(
            runID: runID,
            artifactPath: postLayoutWaveformPath,
            projectRoot: root
        )
        #expect(waveformPreview.structuredPreview == "CSV rows=2 columns=3 [time,v(out),v(in)]")
        #expect(waveformPreview.parseIssue == nil)
        let waveformSummary = try #require(waveformPreview.waveformPreview)
        #expect(waveformSummary.sweepColumn == "time")
        #expect(waveformSummary.sampleCount == 2)
        #expect(waveformSummary.signalCount == 2)
        #expect(waveformSummary.sweepStart == 0)
        #expect(waveformSummary.sweepEnd == 1e-9)
        let outputSignal = try #require(waveformSummary.signals.first { $0.name == "v(out)" })
        #expect(outputSignal.numericSampleCount == 2)
        #expect(outputSignal.firstValue == 0)
        #expect(outputSignal.lastValue == 1)
        #expect(outputSignal.minValue == 0)
        #expect(outputSignal.maxValue == 1)
        #expect(outputSignal.samples.count == 2)
        #expect(outputSignal.samples.first?.sweepValue == 0)
        #expect(outputSignal.samples.first?.signalValue == 0)
        #expect(outputSignal.samples.last?.sweepValue == 1e-9)
        #expect(outputSignal.samples.last?.signalValue == 1)

        let measurement = try #require(review.signoff.cards.first {
            $0.domain == "Simulation" && $0.title == "Simulation Measurements"
        })
        #expect(measurement.passed == nil)
        #expect(measurement.primaryMetrics.contains { $0.label == "gain" && $0.value == "12.5 V/V" })

        let comparison = try #require(review.signoff.cards.first { $0.domain == "Post-layout" })
        #expect(comparison.passed == false)
        #expect(comparison.primaryMetrics.contains { $0.label == "Max rel" && $0.value == "0.5" })
        let comparisonVariables = try #require(comparison.detailSections.first { $0.title == "Compared Variables" })
        let outputComparison = try #require(comparisonVariables.rows.first { $0.label == "v(out)" })
        #expect(outputComparison.metrics.contains { $0.label == "Points" && $0.value == "10" })
        #expect(outputComparison.metrics.contains { $0.label == "Max abs" && $0.value == "0.25" })
        #expect(outputComparison.metrics.contains { $0.label == "Max rel" && $0.value == "0.5" })
        #expect(comparison.issues.contains { $0.message == "max relative delta exceeded" })
        let comparisonIssue = try #require(comparison.issues.first { $0.label == "gate" })
        #expect(comparisonIssue.evidenceArtifacts.map(\.binding.circuitStudioPresentationPath).contains(comparisonPath))
        #expect(comparisonIssue.evidenceArtifacts.map(\.binding.circuitStudioPresentationPath).contains(postLayoutWaveformPath))
        #expect(comparisonIssue.repairActionHints.first?.operationID == "pex.metric-recovery-objective")
        #expect(comparison.relatedArtifacts.contains { $0.binding.logicalID == "pre-layout-waveform" })
        #expect(comparison.relatedArtifacts.contains { $0.binding.logicalID == "post-layout-waveform" })

        let drilldown = service.interactiveSignoffDrilldown(from: review)
        #expect(drilldown.sections.map(\.domain) == [
            .drc,
            .lvs,
            .pex,
            .oracle,
            .simulation,
            .postLayout,
            .waveform,
        ])
        let loadedDrilldown = try await service.loadInteractiveSignoffDrilldown(
            runID: runID,
            projectRoot: root
        )
        #expect(loadedDrilldown == drilldown)
        let drcDrilldown = try #require(drilldown.section(for: .drc)?.items.first)
        #expect(drcDrilldown.interactions.contains(.issueEvidence))
        #expect(drcDrilldown.interactions.contains(.repairActionSelection))
        #expect(drcDrilldown.artifactReferences.contains {
            $0.source == "run-ledger"
                && $0.artifactID == "drc-summary"
                && $0.path == drcPath
        })
        #expect(drcDrilldown.artifactReferences.contains { $0.path == drcEnvelopePath })
        #expect(drcDrilldown.detailGroups.contains { $0.title == "Artifact Evaluation" })
        #expect(drcDrilldown.detailGroups.contains { $0.title == "Evaluation Channels" })
        #expect(drcDrilldown.detailGroups.contains { $0.title == "Feedback Signals" })
        let drcDrilldownIssue = try #require(drcDrilldown.issues.first)
        #expect(drcDrilldownIssue.artifactReferences.contains { $0.path == drcLogPath })
        #expect(drcDrilldownIssue.artifactReferences.contains { $0.path == drcEnvelopePath })
        #expect(drcDrilldownIssue.repairActionHints.map(\.operationID) == ["layout.resize-shape"])
        let lvsDrilldown = try #require(drilldown.section(for: .lvs)?.items.first)
        #expect(lvsDrilldown.issues.first?.repairActionHints.map(\.operationID) == [
            "layout.add-label",
            "layout.add-net",
        ])
        let pexDrilldown = try #require(drilldown.section(for: .pex)?.items.first)
        #expect(pexDrilldown.issues.contains { $0.label == "ss:PEX_CORNER_FAILED" })
        let oracleSection = try #require(drilldown.section(for: .oracle))
        #expect(oracleSection.items.count == 2)
        #expect(oracleSection.items.contains {
            $0.title == "Generated Layout Signoff Corpus"
                && $0.issues.contains { $0.label == "standard-gds-lvs-fail:case-disagreement" }
                && $0.detailGroups.contains { $0.title == "Oracle Evidence Refs" }
        })
        #expect(oracleSection.items.contains {
            $0.title == "Retained Signoff Oracle Dashboard"
                && $0.issues.contains { $0.label == "lvs:retained-oracle-lane" }
        })
        #expect(drilldown.artifactIndex.contains { $0.path == generatedLayoutCorpusPath })
        #expect(drilldown.artifactIndex.contains { $0.path == retainedSignoffReportPath })
        let waveformSection = try #require(drilldown.section(for: .waveform))
        #expect(waveformSection.items.contains { $0.itemID == "waveform:\(preLayoutWaveformPath)" })
        #expect(waveformSection.items.contains { $0.itemID == "waveform:\(postLayoutWaveformPath)" })
        #expect(waveformSection.items.contains {
            $0.itemID == "waveform-comparison:\(comparisonPath)"
                && $0.interactions.contains(.waveformComparison)
        })
        #expect(drilldown.artifactIndex.contains { $0.path == comparisonPath })
        #expect(drilldown.artifactIndex.contains { $0.path == postLayoutWaveformPath })
        #expect(drilldown.failures.isEmpty)

        let waiver = try #require(review.waivers.items.first)
        #expect(review.waivers.decodeIssues.isEmpty)
        #expect(waiver.domain == "DRC")
        #expect(waiver.status == "needs-review")
        #expect(waiver.waivedCount == 1)
        #expect(waiver.unusedWaiverIDs == ["waive-obsolete-rule"])
        #expect(waiver.waivedBuckets.first?.label == "M1.WIDTH")
        #expect(waiver.sourceReferences.first?.waiverID == "waive-m1-width-temporary")
        #expect(waiver.sourceReferences.first?.locationLabel == "signoff/waivers/drc-waivers.json:12-18")
        #expect(waiver.sourceReferences.first?.ruleID == "M1.WIDTH")
        let proposal = try #require(waiver.editProposals.first)
        #expect(proposal.proposalID == "remove-obsolete-drc-waiver")
        #expect(proposal.waiverID == "waive-obsolete-rule")
        #expect(proposal.targetPath == waiverSourcePath)
        #expect(proposal.operation == "remove-json-object")
        #expect(proposal.risk == "low")

        let waiverDecision = try await RunReviewService().decideWaiverReview(
            runID: runID,
            waiverReviewID: waiver.waiverReviewID,
            decision: .approved,
            reviewer: "reviewer-1",
            note: "Waiver scope reviewed against the DRC summary.",
            projectRoot: root
        )
        #expect(waiverDecision.actionKind == FlowRunReviewDecisionKind.waiver.rawValue)
        #expect(waiverDecision.actor.kind == .human)
        #expect(waiverDecision.actor.identifier == "reviewer-1")
        let decisionContext = try #require(waiverDecision.context.reviewDecision)
        #expect(decisionContext.kind == .waiver)
        #expect(decisionContext.decision == "approved")
        #expect(decisionContext.targetID == waiver.waiverReviewID)
        #expect(fixture.review.bundle.artifacts.contains {
            $0.binding.logicalID == "drc-summary"
                && waiverDecision.inputs.contains($0.reference)
        })

        let proposalSelection = try await RunReviewService().recordWaiverEditProposalSelection(
            runID: runID,
            waiverReviewID: waiver.waiverReviewID,
            proposalID: proposal.proposalID,
            reviewer: "reviewer-1",
            note: "Apply this before final signoff.",
            projectRoot: root
        )
        #expect(proposalSelection.actionKind == "review.selectWaiverEditProposal")
        #expect(proposalSelection.actor.kind == .human)
        let selectionContext = try #require(proposalSelection.context.reviewDecision)
        #expect(selectionContext.targetID == waiver.waiverReviewID)
        #expect(selectionContext.targetPath == "remove-obsolete-drc-waiver")
        #expect(selectionContext.decision == "selected")
        #expect(fixture.review.bundle.artifacts.contains {
            $0.binding.logicalID == "drc-summary"
                && proposalSelection.inputs.contains($0.reference)
        })

        // The verification contract requires an explicit layout technology;
        // a minimal builtin-only package keeps the rest of the fixture's
        // behavior (no golden signoff/PEX expectations) unchanged.
        let workspaceURL = root.appending(path: "minimal-technology-package.json")
        try Data("""
        {
          "version": 1,
          "packageID": "minimal-sample-process",
          "name": "Minimal Sample Process",
          "layoutTechnology": { "kind": "builtin", "id": "sampleProcess" }
        }
        """.utf8).write(to: workspaceURL, options: .atomic)
        let verificationResult = try await RunReviewService().applyWaiverEditProposalAndRunPostVerification(
            runID: runID,
            waiverReviewID: waiver.waiverReviewID,
            proposalID: proposal.proposalID,
            reviewer: "agent-1",
            note: "Apply waiver cleanup and re-run DRC/LVS.",
            technologyPackagePath: workspaceURL.path(percentEncoded: false),
            projectRoot: root
        )
        #expect(verificationResult.kind == .applyWaiverEditProposalAndRunPostVerification)
        #expect(verificationResult.designName == "review-verification-divider")
        #expect(verificationResult.runID == runID)
        #expect(verificationResult.verificationReportPath?.hasSuffix(".xcircuite/runs/\(runID)/reports/physical-verification.json") == true)
        #expect(verificationResult.actionLogPath?.hasSuffix(".xcircuite/runs/\(runID)/actions.jsonl") == true)
        #expect(verificationResult.verificationReport?.readyForPEX == false)
        #expect(verificationResult.verificationReport?.drc.passed == true)
        #expect(verificationResult.verificationReport?.lvs.passed == true)
        #expect(verificationResult.verificationReport?.layoutTrust?.passed == true)
        #expect(verificationResult.verificationReport?.externalSignoff == nil)
        let actionRecordIDs = try #require(verificationResult.actionRecordIDs)
        #expect(actionRecordIDs.count == 2)
        #expect(actionRecordIDs.first?.hasPrefix("waiver-edit-proposal-application-") == true)
        #expect(actionRecordIDs.last?.hasPrefix("waiver-edit-proposal-verification-") == true)
        #expect(verificationResult.message?.hasPrefix("waiver-edit-proposal-verification-") == true)

        let editedWaiverData = try Data(contentsOf: root.appending(path: waiverSourcePath))
        let editedWaiverDocument = try JSONDecoder().decode(WaiverDocumentValue.self, from: editedWaiverData)
        guard case .object(let editedRoot) = editedWaiverDocument,
              case .array(let editedWaivers) = editedRoot["waivers"] else {
            Issue.record("Edited waiver document should remain a JSON object with a waivers array.")
            return
        }
        #expect(editedWaivers.contains {
            guard case .object(let waiver) = $0 else {
                return false
            }
            return waiver["waiverID"] == .string("waive-m1-width-temporary")
        })
        #expect(!editedWaivers.contains {
            guard case .object(let waiver) = $0 else {
                return false
            }
            return waiver["waiverID"] == .string("waive-obsolete-rule")
        })

        let approvedReview = try await RunReviewService().loadRun(runID: runID, projectRoot: root)
        let approvedWaiver = try #require(approvedReview.waivers.items.first)
        #expect(approvedWaiver.status == "approved")
        #expect(approvedWaiver.latestDecision?.actor == "reviewer-1")
        #expect(approvedWaiver.latestDecision?.note == "Waiver scope reviewed against the DRC summary.")
        #expect(approvedWaiver.editProposalSelections.first?.proposalID == "remove-obsolete-drc-waiver")
        #expect(approvedWaiver.editProposalSelections.first?.actor == "reviewer-1")
        #expect(approvedWaiver.editProposalSelections.first?.note == "Apply this before final signoff.")
        #expect(approvedWaiver.editApplications.first?.proposalID == "remove-obsolete-drc-waiver")
        #expect(approvedWaiver.editApplications.first?.actor == "agent-1")
        #expect(approvedWaiver.editApplications.first?.targetPath == waiverSourcePath)
        #expect(approvedWaiver.editApplications.first?.operation == "remove-json-object")
        #expect(approvedWaiver.editApplications.first?.beforeSHA256 != approvedWaiver.editApplications.first?.afterSHA256)
        #expect(approvedWaiver.editApplications.first?.note == "Apply waiver cleanup and re-run DRC/LVS.")
        #expect(approvedWaiver.editVerifications.first?.proposalID == "remove-obsolete-drc-waiver")
        #expect(approvedWaiver.editVerifications.first?.actor == "agent-1")
        #expect(approvedWaiver.editVerifications.first?.status == verificationResult.verificationReport?.status)
        #expect(approvedWaiver.editVerifications.first?.verificationReportPath.contains(
            ".xcircuite/runs/\(runID)/review/waiver-edits/remove-obsolete-drc-waiver/verification-"
        ) == true)
        #expect(approvedWaiver.editVerifications.first?.applicationActionID == approvedWaiver.editApplications.first?.actionRecordID)
        #expect(approvedWaiver.editVerifications.first?.planningFeedbackStatus == "rejected-plan-recorded")
        #expect(approvedWaiver.editVerifications.first?.rejectedPlansPath?.hasPrefix(
            ".xcircuite/runs/\(runID)/planning/rejected-plan-snapshots/"
        ) == true)
        #expect(approvedWaiver.editVerifications.first?.note == "Apply waiver cleanup and re-run DRC/LVS.")
        let approvedVerificationSummary = try #require(approvedWaiver.editVerifications.first?.reportSummary)
        #expect(approvedVerificationSummary.status == verificationResult.verificationReport?.status)
        #expect(approvedVerificationSummary.readyForPEX == verificationResult.verificationReport?.readyForPEX)
        #expect(approvedVerificationSummary.drc.passed == verificationResult.verificationReport?.drc.passed)
        #expect(approvedVerificationSummary.lvs.passed == verificationResult.verificationReport?.lvs.passed)

        let failedVerificationReport = try JSONDecoder().decode(
            DesignFlowVerificationReport.self,
            from: Data(
                """
                {
                  "status": "failed",
                  "readyForPEX": false,
                  "layoutTrust": null,
                  "drc": {
                    "passed": false,
                    "violationCount": 2,
                    "violationsByKind": {
                      "M1.WIDTH": 2
                    }
                  },
                  "lvs": {
                    "passed": true,
                    "schematicHashMatches": true,
                    "missingLayoutInstances": [],
                    "extraLayoutInstances": [],
                    "missingLayoutNets": [],
                    "extraLayoutNets": [],
                    "danglingMappedInstanceIDs": [],
                    "danglingMappedNetIDs": [],
                    "physicalShorts": [],
                    "physicalOpens": [],
                    "unconnectedLayoutPins": [],
                    "terminalMismatches": [],
                    "missingExternalLayoutPorts": [],
                    "invalidLayoutTerminals": [],
                    "duplicateLayoutTerminals": [],
                    "deviceParameterMismatches": [],
                    "duplicateLayoutDevices": [],
                    "layoutTopologyErrors": [],
                    "connectivityExtractionSkipped": false,
                    "skippedComponents": []
                  },
                  "externalSignoff": null
                }
                """.utf8
            )
        )
        let failedVerificationReportPath = ".xcircuite/runs/\(runID)/reports/failed-post-waiver-verification.json"
        let failedVerificationReportURL = root.appending(path: failedVerificationReportPath)
        try RunReviewTestSupport.writeJSON(failedVerificationReport, to: failedVerificationReportURL)

        let failedVerificationAction = try await RunReviewService().recordWaiverEditVerification(
            runID: runID,
            waiverReviewID: waiver.waiverReviewID,
            proposalID: proposal.proposalID,
            reviewer: "agent-1",
            verificationReport: failedVerificationReport,
            verificationReportURL: failedVerificationReportURL,
            layoutTrustReportURL: nil,
            note: "Rejected feedback should feed the next planning iteration.",
            projectRoot: root
        )
        #expect(failedVerificationAction.actionKind == "review.verifyWaiverEditProposal")
        #expect(failedVerificationAction.context.reviewDecision?.decision == "rejected-plan-recorded")
        #expect(failedVerificationAction.context.iterationID?.hasPrefix("waiver-edit-proposal-application-") == true)
        let failedVerificationLedger = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunLedger(runID: runID)
        let failedVerificationOutputBindings = failedVerificationLedger.artifacts.filter {
            failedVerificationAction.outputs.contains($0.reference)
        }
        #expect(failedVerificationOutputBindings.contains { $0.logicalID == "planning-rejected-plans" })
        #expect(failedVerificationOutputBindings.contains {
            $0.path.hasPrefix(".xcircuite/runs/\(runID)/planning/waiver-edit-feedback/remove-obsolete-drc-waiver/verifications/") &&
                $0.path.hasSuffix("/candidate-plan.json")
        })
        #expect(failedVerificationOutputBindings.contains {
            $0.path.hasPrefix(".xcircuite/runs/\(runID)/planning/waiver-edit-feedback/remove-obsolete-drc-waiver/verifications/") &&
                $0.path.hasSuffix("/plan-verification.json")
        })

        let rejectedPlansPath = try #require(
            failedVerificationOutputBindings.first {
                $0.logicalID == XcircuitePlanningArtifactStore.rejectedPlansArtifactID
            }?.path
        )
        #expect(rejectedPlansPath.hasPrefix(
            ".xcircuite/runs/\(runID)/planning/rejected-plan-snapshots/"
        ))
        let rejectedPlansText = try String(
            contentsOf: root.appending(path: rejectedPlansPath),
            encoding: .utf8
        )
        let rejectedPlanLine = try #require(rejectedPlansText.split(separator: "\n").last)
        let rejectedPlan = try JSONDecoder().decode(
            XcircuiteRejectedPlanRecord.self,
            from: Data(String(rejectedPlanLine).utf8)
        )
        #expect(rejectedPlan.status == "rejected")
        #expect(rejectedPlan.verificationMode == "post-waiver-edit")
        #expect(rejectedPlan.failedStepIDs == ["apply-waiver-edit-remove-obsolete-drc-waiver"])
        #expect(rejectedPlan.failedGateIDs == [
            "post-waiver-edit-drc",
            "post-waiver-edit-layout-trust",
            "post-waiver-edit-ready-for-pex",
        ])
        let failedVerificationBinding = try #require(
            failedVerificationOutputBindings.first {
                $0.logicalID.hasPrefix("post-waiver-edit-physical-verification-")
            }
        )
        let failedVerificationToken = failedVerificationBinding.reference.digest.hexadecimalValue
        let failedVerificationArtifactPrefix =
            ".xcircuite/runs/\(runID)/planning/waiver-edit-feedback/remove-obsolete-drc-waiver/verifications/\(failedVerificationToken)/"
        let rejectedCandidatePlanBindings = failedVerificationOutputBindings.filter {
            $0.reference == rejectedPlan.candidatePlanRef
                && $0.path.hasPrefix(failedVerificationArtifactPrefix)
                && $0.path.hasSuffix("/candidate-plan.json")
        }
        let rejectedPlanVerificationBindings = failedVerificationOutputBindings.filter {
            $0.reference == rejectedPlan.planVerificationRef
                && $0.path.hasPrefix(failedVerificationArtifactPrefix)
                && $0.path.hasSuffix("/plan-verification.json")
        }
        #expect(rejectedCandidatePlanBindings.count == 1)
        #expect(rejectedPlanVerificationBindings.count == 1)
        let rejectedCandidatePlanPath = try #require(rejectedCandidatePlanBindings.first?.path)
        let rejectedPlanVerificationPath = try #require(rejectedPlanVerificationBindings.first?.path)
        #expect(rejectedCandidatePlanPath.hasPrefix(".xcircuite/runs/\(runID)/planning/waiver-edit-feedback/remove-obsolete-drc-waiver/verifications/"))
        #expect(rejectedCandidatePlanPath.hasSuffix("/candidate-plan.json"))
        #expect(rejectedPlanVerificationPath.hasPrefix(".xcircuite/runs/\(runID)/planning/waiver-edit-feedback/remove-obsolete-drc-waiver/verifications/"))
        #expect(rejectedPlanVerificationPath.hasSuffix("/plan-verification.json"))
        #expect(rejectedPlan.diagnostics.map(\.code) == [
            "DRC_POST_WAIVER_EDIT_FAILED",
            "LAYOUT_TRUST_POST_WAIVER_EDIT_MISSING",
            "POST_WAIVER_EDIT_READY_FOR_PEX_FAILED",
        ])
        #expect(rejectedPlan.nextActions == [
            "repair-verification-gate:post-waiver-edit-drc",
            "repair-verification-gate:post-waiver-edit-layout-trust",
            "repair-verification-gate:post-waiver-edit-ready-for-pex",
        ])

        let rejectedReview = try await RunReviewService().loadRun(runID: runID, projectRoot: root)
        let rejectedWaiver = try #require(rejectedReview.waivers.items.first)
        let rejectedVerification = try #require(rejectedWaiver.editVerifications.last)
        #expect(rejectedVerification.planningFeedbackStatus == "rejected-plan-recorded")
        #expect(rejectedVerification.rejectedPlansPath == rejectedPlansPath)
        let rejectedSummary = try #require(rejectedVerification.reportSummary)
        #expect(rejectedSummary.status == "failed")
        #expect(rejectedSummary.readyForPEX == false)
        #expect(rejectedSummary.drc.passed == false)
        #expect(rejectedSummary.drc.violationCount == 2)
        #expect(rejectedSummary.drc.violationsByKind == [
            RunReviewWaiverVerificationBucket(label: "M1.WIDTH", count: 2),
        ])
        #expect(rejectedSummary.lvs.passed == true)
        #expect(rejectedSummary.lvs.issueCounts.isEmpty)

        let reviewAfterCandidateCycle = try await RunReviewService().loadRun(
            runID: runID,
            projectRoot: root
        )
        #expect(reviewAfterCandidateCycle.signoff.repairCandidateCycles.isEmpty)
    }

    @Test @MainActor func artifactPreviewRejectsSymlinkEscape() async throws {
        let fixture = try await RunReviewSignoffFixture.make(includeSymlinkEscape: true)
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        await #expect(throws: RunReviewServiceError.artifactPreviewEscapesProject(
            path: fixture.symlinkEscapePath
        )) {
            try await fixture.service.loadArtifactPreview(
                runID: fixture.runID,
                artifactPath: fixture.symlinkEscapePath,
                projectRoot: fixture.root
            )
        }
    }

    @Test @MainActor func signoffSummaryRequiresVerifiedIntegrity() async throws {
        let fixture = try await RunReviewSignoffFixture.make()
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        var bundle = fixture.review.bundle
        let drcIndex = try #require(bundle.artifacts.firstIndex { $0.binding.circuitStudioPresentationPath == fixture.drcPath })
        bundle.artifacts[drcIndex].integrity = FlowRunReviewArtifactIntegrity(
            status: .sha256Mismatch,
            expectedSHA256: String(repeating: "a", count: 64),
            actualSHA256: String(repeating: "b", count: 64),
            expectedByteCount: 10,
            actualByteCount: 11,
            message: "Artifact SHA-256 mismatch"
        )

        let service = RunReviewService(reviewBundler: StaticRunReviewBundler(bundle: bundle))
        let review = try await service.loadRun(runID: fixture.runID, projectRoot: fixture.root)

        #expect(!review.signoff.cards.contains { $0.domain == "DRC" })
        #expect(review.signoff.decodeIssues.contains {
            $0.artifactPath == fixture.drcPath
                && $0.message.lowercased().contains("signoff artifact integrity")
                && $0.message.contains("sha256Mismatch")
        })
    }

    @Test @MainActor func waiverReviewRequiresVerifiedArtifactIntegrity() async throws {
        let fixture = try await RunReviewSignoffFixture.make()
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        var bundle = fixture.review.bundle
        let drcIndex = try #require(bundle.artifacts.firstIndex { $0.binding.circuitStudioPresentationPath == fixture.drcPath })
        bundle.artifacts[drcIndex].integrity = FlowRunReviewArtifactIntegrity(
            status: .sha256Mismatch,
            expectedSHA256: String(repeating: "a", count: 64),
            actualSHA256: String(repeating: "b", count: 64),
            expectedByteCount: 10,
            actualByteCount: 11,
            message: "Artifact SHA-256 mismatch"
        )

        let service = RunReviewService(reviewBundler: StaticRunReviewBundler(bundle: bundle))
        let review = try await service.loadRun(runID: fixture.runID, projectRoot: fixture.root)

        #expect(review.waivers.items.isEmpty)
        #expect(review.waivers.decodeIssues.contains {
            $0.artifactPath == fixture.drcPath
                && $0.message.lowercased().contains("waiver artifact integrity")
                && $0.message.contains("sha256Mismatch")
        })
    }

    @Test @MainActor func artifactEvaluationEnvelopeRequiresVerifiedIntegrity() async throws {
        let fixture = try await RunReviewSignoffFixture.make()
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        var bundle = fixture.review.bundle
        let envelopeIndex = try #require(bundle.artifacts.firstIndex { $0.binding.circuitStudioPresentationPath == fixture.drcEnvelopePath })
        bundle.artifacts[envelopeIndex].integrity = FlowRunReviewArtifactIntegrity(
            status: .sha256Mismatch,
            expectedSHA256: String(repeating: "a", count: 64),
            actualSHA256: String(repeating: "b", count: 64),
            expectedByteCount: 10,
            actualByteCount: 11,
            message: "Artifact SHA-256 mismatch"
        )

        let service = RunReviewService(reviewBundler: StaticRunReviewBundler(bundle: bundle))
        let review = try await service.loadRun(runID: fixture.runID, projectRoot: fixture.root)
        let drc = try #require(review.signoff.cards.first { $0.domain == "DRC" })

        #expect(drc.evaluationEvidence.isEmpty)
        #expect(!drc.detailSections.contains { $0.title == "Artifact Evaluation" })
        #expect(review.signoff.decodeIssues.contains {
            $0.artifactPath == fixture.drcEnvelopePath
                && $0.message.contains("artifact integrity")
                && $0.message.contains("sha256Mismatch")
        })
    }

    @Test @MainActor func artifactPreviewRequiresVerifiedIntegrity() async throws {
        let fixture = try await RunReviewSignoffFixture.make()
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        var bundle = fixture.review.bundle
        let logIndex = try #require(bundle.artifacts.firstIndex { $0.binding.circuitStudioPresentationPath == fixture.drcLogPath })
        bundle.artifacts[logIndex].integrity = FlowRunReviewArtifactIntegrity(
            status: .sha256Mismatch,
            expectedSHA256: String(repeating: "a", count: 64),
            actualSHA256: String(repeating: "b", count: 64),
            expectedByteCount: 10,
            actualByteCount: 11,
            message: "Artifact SHA-256 mismatch"
        )

        let service = RunReviewService(reviewBundler: StaticRunReviewBundler(bundle: bundle))
        do {
            _ = try await service.loadArtifactPreview(
                runID: fixture.runID,
                artifactPath: fixture.drcLogPath,
                projectRoot: fixture.root,
                maxBytes: 12
            )
            Issue.record("Expected artifact preview to reject unverified artifact integrity.")
        } catch let error as RunReviewServiceError {
            if case .artifactPreviewIntegrityUnverified(let path, let status, _) = error {
                #expect(path == fixture.drcLogPath)
                #expect(status == "sha256Mismatch")
            } else {
                Issue.record("Expected artifact preview integrity error, got \(error).")
            }
        } catch {
            Issue.record("Expected RunReviewServiceError, got \(error).")
        }
    }

    @Test @MainActor func interactiveSignoffDrilldownPrefersLedgerArtifactWhenPathsOverlap() async throws {
        let fixture = try await RunReviewSignoffFixture.make()
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        let sharedPath = ".xcircuite/runs/\(fixture.runID)/reports/shared-integrity-artifact.json"
        let designDiffSummary = RunReviewDesignDiffSummary(
            title: "Overlapping Artifact",
            actor: "agent",
            reviewState: "needs-review",
            changeCount: 0,
            domains: [],
            operations: [],
            baseSnapshot: RunReviewDesignDiffArtifactSummary(
                artifactID: "shared-design-diff",
                path: sharedPath,
                sha256: nil,
                byteCount: nil
            ),
            changes: []
        )
        let expectedSHA256 = String(repeating: "a", count: 64)
        let ledgerReference = try ArtifactReference(
                digest: try ContentDigest(algorithm: .sha256, hexadecimalValue: expectedSHA256),
                byteCount: 128,
                descriptor: ArtifactDescriptor(role: .output, kind: .report, format: .json)
        )
        let ledgerArtifact = FlowRunReviewArtifact(
            binding: try RunReviewTestSupport.artifactBinding(
                reference: ledgerReference,
                artifactID: "shared-ledger-artifact",
                path: sharedPath
            ),
            purpose: .stageSummary,
            stageID: "007-drc",
            integrity: FlowRunReviewArtifactIntegrity(
                status: .sha256Mismatch,
                expectedSHA256: expectedSHA256,
                actualSHA256: String(repeating: "b", count: 64),
                expectedByteCount: 128,
                actualByteCount: 128,
                message: "Digest mismatch"
            )
        )
        let conflictingSignoff = RunReviewSignoffSummary(
            cards: [
                RunReviewSignoffCard(
                    domain: "DRC",
                    title: "Overlapping DRC Artifact",
                    status: "failed",
                    passed: false,
                    stageID: "007-drc",
                    artifact: ledgerArtifact,
                    primaryMetrics: []
                ),
            ]
        )
        let planning = RunReviewService.PlanningReview(
            candidatePlanArtifact: fixture.review.planning.candidatePlanArtifact,
            planVerificationArtifact: fixture.review.planning.planVerificationArtifact,
            candidatePlan: fixture.review.planning.candidatePlan,
            planVerification: fixture.review.planning.planVerification,
            designDiff: fixture.review.planning.designDiff,
            designDiffSummary: designDiffSummary,
            correctnessItems: fixture.review.planning.correctnessItems,
            selectedActions: fixture.review.planning.selectedActions,
            decodeIssues: fixture.review.planning.decodeIssues
        )
        let review = RunReviewService.RunReview(
            runID: fixture.review.runID,
            status: fixture.review.status,
            actor: fixture.review.actor,
            intent: fixture.review.intent,
            createdAt: fixture.review.createdAt,
            updatedAt: fixture.review.updatedAt,
            startedAt: fixture.review.startedAt,
            finishedAt: fixture.review.finishedAt,
            artifacts: fixture.review.artifacts,
            stages: fixture.review.stages,
            approvals: fixture.review.approvals,
            suggestedActionSelections: fixture.review.suggestedActionSelections,
            planning: planning,
            signoff: conflictingSignoff,
            waivers: fixture.review.waivers,
            failureStates: fixture.review.failureStates,
            toolchain: fixture.review.toolchain,
            flowReview: fixture.review.flowReview,
            retainedDashboard: fixture.review.retainedDashboard,
            bundle: fixture.review.bundle
        )

        let drilldown = fixture.service.interactiveSignoffDrilldown(from: review)

        let indexedArtifact = try #require(drilldown.artifactIndex.first { $0.path == sharedPath })
        #expect(indexedArtifact.source == "run-ledger")
        #expect(indexedArtifact.artifactID == "shared-ledger-artifact")
        #expect(indexedArtifact.integrityStatus == FlowRunReviewArtifactIntegrityStatus.sha256Mismatch.rawValue)
        #expect(drilldown.failures.contains {
            $0.failureID == "artifact-integrity:\(sharedPath)"
                && $0.artifactReferences.first?.source == "run-ledger"
                && $0.artifactReferences.first?.integrityStatus == FlowRunReviewArtifactIntegrityStatus.sha256Mismatch.rawValue
        })
    }

    @Test @MainActor func artifactPreviewCanResolveDuplicatePathByArtifactIdentity() async throws {
        let fixture = try await RunReviewSignoffFixture.make()
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        var bundle = fixture.review.bundle
        let logIndex = try #require(bundle.artifacts.firstIndex { $0.binding.circuitStudioPresentationPath == fixture.drcLogPath })
        let original = bundle.artifacts[logIndex]
        let duplicate = FlowRunReviewArtifact(
            binding: try FlowArtifactBinding(
                logicalID: "drc-raw-log-alias",
                reference: original.reference,
                availability: original.binding.availability,
                producer: original.binding.producer
            ),
            purpose: try FlowRunReviewArtifactPurpose(validatingRawValue: "alias-log"),
            stageID: "alias-stage",
            integrity: original.integrity
        )
        bundle.artifacts[logIndex].integrity = FlowRunReviewArtifactIntegrity(
            status: .sha256Mismatch,
            expectedSHA256: String(repeating: "a", count: 64),
            actualSHA256: String(repeating: "b", count: 64),
            expectedByteCount: 10,
            actualByteCount: 11,
            message: "Artifact SHA-256 mismatch"
        )
        bundle.artifacts.append(duplicate)

        #expect(
            RunReviewArtifactPreviewKey.make(runID: fixture.runID, artifact: bundle.artifacts[logIndex])
                != RunReviewArtifactPreviewKey.make(runID: fixture.runID, artifact: duplicate)
        )

        let service = RunReviewService(reviewBundler: StaticRunReviewBundler(bundle: bundle))
        let preview = try await service.loadArtifactPreview(
            runID: fixture.runID,
            artifact: duplicate,
            projectRoot: fixture.root,
            maxBytes: 12
        )

        #expect(preview.artifact.binding.logicalID == "drc-raw-log-alias")
        #expect(preview.text == "DRC_SUMMARY ")
        #expect(preview.truncated)
    }
}

private struct StaticRunReviewBundler: FlowRunReviewBundling {
    let bundle: FlowRunReviewBundle

    func makeReviewBundle(runID: String, workspaceID: FlowWorkspaceID) async throws -> FlowRunReviewBundle {
        bundle
    }
}
