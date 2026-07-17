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
        let drcRepairHintPath = fixture.drcRepairHintPath
        let drcEnvelopePath = fixture.drcEnvelopePath
        let lvsPath = fixture.lvsPath
        let lvsLogPath = fixture.lvsLogPath
        let lvsRepairHintPath = fixture.lvsRepairHintPath
        let pexPath = fixture.pexPath
        let simulationSummaryPath = fixture.simulationSummaryPath
        let preLayoutWaveformPath = fixture.preLayoutWaveformPath
        let postLayoutWaveformPath = fixture.postLayoutWaveformPath
        let symlinkEscapePath = fixture.symlinkEscapePath
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
        #expect(verificationContext.designSpecArtifact.reference.path == designSpecPath)
        #expect(verificationContext.layoutDocumentArtifact.reference.path == layoutDocumentPath)
        #expect(verificationContext.designUnitArtifact?.reference.path == designUnitPath)
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
        #expect(drcIssue.evidenceArtifacts.map(\.reference.locator.location.value).contains(drcPath))
        #expect(drcIssue.evidenceArtifacts.map(\.reference.locator.location.value).contains(drcLogPath))
        #expect(drcIssue.evidenceArtifacts.map(\.reference.locator.location.value).contains(drcEnvelopePath))
        #expect(drcIssue.evidenceArtifacts.map(\.reference.locator.location.value).contains(stageResultPath))
        #expect(!drcIssue.evidenceArtifacts.map(\.reference.locator.location.value).contains(lvsPath))
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
        #expect(drcRepairAction.requiredInputRefs == ["layout-ref"])
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
        #expect(drc.relatedArtifacts.contains { $0.reference.id.rawValue == "drc-raw-log" })
        #expect(drc.relatedArtifacts.contains { $0.reference.id.rawValue == "drc-repair-hints" })
        #expect(drc.relatedArtifacts.contains { $0.reference.locator.location.value == drcEnvelopePath })
        #expect(drc.relatedArtifacts.contains { $0.purpose.rawValue == "stage-result" })
        #expect(!drc.relatedArtifacts.contains { $0.reference.id.rawValue == "lvs-summary" })
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
        await #expect(throws: RunReviewServiceError.artifactPreviewEscapesProject(path: symlinkEscapePath)) {
            try await service.loadArtifactPreview(
                runID: runID,
                artifactPath: symlinkEscapePath,
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
        #expect(lvsIssue.evidenceArtifacts.map(\.reference.locator.location.value).contains(lvsPath))
        #expect(lvsIssue.evidenceArtifacts.map(\.reference.locator.location.value).contains(lvsLogPath))
        #expect(!lvsIssue.evidenceArtifacts.map(\.reference.locator.location.value).contains(drcPath))
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
        #expect(lvs.relatedArtifacts.contains { $0.reference.id.rawValue == "lvs-raw-log" })
        #expect(lvs.relatedArtifacts.contains { $0.reference.id.rawValue == "lvs-repair-hints" })

        let repairPlanning = try await service.formulateSignoffRepairPlanningProblem(
            runID: runID,
            actorKind: .agent,
            actorIdentifier: "agent-1",
            note: "Generate signoff repair planning problem from review diagnostics.",
            projectRoot: root
        )
        #expect(repairPlanning.drcRepairHintPath == drcRepairHintPath)
        #expect(repairPlanning.lvsRepairHintPath == lvsRepairHintPath)
        #expect(repairPlanning.actionDomainArtifact.path == ".xcircuite/runs/\(runID)/planning/action-domain-snapshot.json")
        #expect(repairPlanning.repairFormulationArtifact.path == ".xcircuite/runs/\(runID)/planning/repair-formulation.json")
        #expect(repairPlanning.planningProblemArtifact.path == ".xcircuite/runs/\(runID)/planning/problem.json")
        #expect(repairPlanning.sourceReports.map(\.sourceKind) == ["drc", "lvs"])
        #expect(repairPlanning.actionRecord.actor.kind == .agent)
        #expect(repairPlanning.actionRecord.actor.identifier == "agent-1")
        #expect(repairPlanning.actionRecord.actionKind == "review.formulateSignoffRepairPlanningProblem")
        #expect(repairPlanning.actionRecord.inputs.map(\.artifactID) == ["drc-repair-hints", "lvs-repair-hints"])
        #expect(repairPlanning.actionRecord.outputs.map(\.artifactID) == [
            "planning-action-domain-snapshot",
            "planning-repair-plan-formulation",
            "planning-problem",
        ])
        #expect(repairPlanning.actionRecord.context.iterationID == repairPlanning.formulationID)
        #expect(repairPlanning.actionRecord.inputs.map(\.path).contains(drcRepairHintPath))
        #expect(repairPlanning.actionRecord.inputs.map(\.path).contains(lvsRepairHintPath))

        let planningProblem = try await XcircuiteWorkspaceStore(projectRoot: root).readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: repairPlanning.planningProblemArtifact.path
        )
        #expect(planningProblem.runID == runID)
        #expect(planningProblem.sourceRefs.contains {
            $0.refID == "drc-repair-hints" && $0.path == drcRepairHintPath
        })
        #expect(planningProblem.sourceRefs.contains {
            $0.refID == "lvs-repair-hints" && $0.path == lvsRepairHintPath
        })
        #expect(planningProblem.candidateActions.map(\.operationID).contains("layout.resize-shape"))
        #expect(planningProblem.candidateActions.map(\.operationID).contains("layout.add-label"))
        #expect(planningProblem.verificationGates.contains { $0.gateID == "native-drc" })
        #expect(planningProblem.verificationGates.contains { $0.gateID == "native-lvs" })

        let signoffPlanningActions = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunActions(runID: runID)
            .filter { $0.actionKind == "review.formulateSignoffRepairPlanningProblem" }
        #expect(signoffPlanningActions.map(\.actionID) == [repairPlanning.actionRecord.actionID])

        let pex = try #require(review.signoff.cards.first { $0.domain == "PEX" })
        #expect(pex.passed == false)
        #expect(pex.primaryMetrics.contains { $0.label == "Failed" && $0.value == "1" })
        #expect(pex.issues.contains { $0.label == "ss:PEX_CORNER_FAILED" })
        let pexIssue = try #require(pex.issues.first { $0.label == "ss:PEX_CORNER_FAILED" })
        #expect(pexIssue.evidenceArtifacts.map(\.reference.locator.location.value).contains(pexPath))
        let pexDiagnosticDetail = try #require(pexIssue.detailRows.first { $0.label == "Diagnostic" })
        #expect(pexDiagnosticDetail.metrics.contains { $0.label == "Corner" && $0.value == "ss" })
        #expect(pexDiagnosticDetail.metrics.contains { $0.label == "Code" && $0.value == "PEX_CORNER_FAILED" })
        #expect(pexIssue.repairActionHints.map(\.operationID) == [
            "pex.metric-recovery-objective",
            "layout-command-replay",
        ])
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
        #expect(corpus.relatedArtifacts.contains { $0.reference.id.rawValue == "retained-signoff-report" })
        #expect(corpus.relatedArtifacts.contains { $0.reference.id.rawValue == "drc-external-oracle-report" })

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
        #expect(timingIssue.evidenceArtifacts.map(\.reference.locator.location.value).contains(simulationSummaryPath))
        #expect(timingIssue.evidenceArtifacts.map(\.reference.locator.location.value).contains(postLayoutWaveformPath))
        #expect(timingIssue.repairActionHints.first?.operationID == "simulation.metric-improvement-objective")
        let timingVerdictDetail = try #require(timingIssue.detailRows.first { $0.label == "Verdict" })
        #expect(timingVerdictDetail.metrics.contains { $0.label == "Metric" && $0.value == "tpd" })
        #expect(timingVerdictDetail.metrics.contains { $0.label == "Value" && $0.value == "1.4e-09" })
        #expect(timingVerdictDetail.metrics.contains { $0.label == "Target" && $0.value == "1e-09" })
        #expect(simulationMetric.relatedArtifacts.contains { $0.reference.id.rawValue == "post-layout-waveform" })
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
        #expect(comparisonIssue.evidenceArtifacts.map(\.reference.locator.location.value).contains(comparisonPath))
        #expect(comparisonIssue.evidenceArtifacts.map(\.reference.locator.location.value).contains(postLayoutWaveformPath))
        #expect(comparisonIssue.repairActionHints.first?.operationID == "pex.metric-recovery-objective")
        #expect(comparison.relatedArtifacts.contains { $0.reference.id.rawValue == "pre-layout-waveform" })
        #expect(comparison.relatedArtifacts.contains { $0.reference.id.rawValue == "post-layout-waveform" })

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
        #expect(waiverDecision.inputs.first?.artifactID == "drc-summary")

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
        #expect(proposalSelection.inputs.first?.artifactID == "drc-summary")

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
        #expect(approvedWaiver.editVerifications.first?.verificationReportPath.hasSuffix(".xcircuite/runs/\(runID)/reports/physical-verification.json") == true)
        #expect(approvedWaiver.editVerifications.first?.applicationActionID == approvedWaiver.editApplications.first?.actionRecordID)
        #expect(approvedWaiver.editVerifications.first?.planningFeedbackStatus == "accepted-no-rejected-plan")
        #expect(approvedWaiver.editVerifications.first?.rejectedPlansPath == nil)
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
        #expect(failedVerificationAction.outputs.contains { $0.artifactID == "planning-rejected-plans" })
        #expect(failedVerificationAction.outputs.contains {
            $0.path == ".xcircuite/runs/\(runID)/planning/waiver-edit-feedback/remove-obsolete-drc-waiver/candidate-plan.json"
        })
        #expect(failedVerificationAction.outputs.contains {
            $0.path == ".xcircuite/runs/\(runID)/planning/waiver-edit-feedback/remove-obsolete-drc-waiver/plan-verification.json"
        })

        let rejectedPlansPath = ".xcircuite/runs/\(runID)/planning/rejected-plans.jsonl"
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
            "post-waiver-edit-ready-for-pex",
        ])
        #expect(rejectedPlan.candidatePlanRef.path == ".xcircuite/runs/\(runID)/planning/waiver-edit-feedback/remove-obsolete-drc-waiver/candidate-plan.json")
        #expect(rejectedPlan.planVerificationRef.path == ".xcircuite/runs/\(runID)/planning/waiver-edit-feedback/remove-obsolete-drc-waiver/plan-verification.json")
        #expect(rejectedPlan.diagnostics.map(\.code) == [
            "DRC_POST_WAIVER_EDIT_FAILED",
            "POST_WAIVER_EDIT_READY_FOR_PEX_FAILED",
        ])
        #expect(rejectedPlan.nextActions == [
            "repair-verification-gate:post-waiver-edit-drc",
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

        let candidateCycle = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .runSignoffRepairCandidateCycle,
            projectRootPath: root.path(percentEncoded: false),
            runID: runID,
            approvalReviewer: "agent-1",
            approvalNote: "Run candidate cycle from signoff repair planning artifacts.",
            actionActorKind: .agent
        ))
        let cycleResult = try #require(candidateCycle.signoffRepairCandidateCycleResult)
        #expect(cycleResult.cycleIndex == 1)
        #expect(cycleResult.planningResult.sourceReports.map(\.sourceKind) == ["drc", "lvs"])
        #expect(cycleResult.candidateGeneration.status == "generated")
        let cycleTrace = try #require(cycleResult.candidateGeneration.symbolicPlannerTrace)
        #expect(cycleTrace.rejectedPlansPath == rejectedPlansPath)
        #expect(cycleTrace.rejectedPlanFeedbackRecordCount == 1)
        #expect(cycleTrace.globalRejectedPlanFeedbackCount == 1)
        #expect(candidateCycle.candidateAccepted == cycleResult.candidateVerification.accepted)
        let planningProblemPath = try #require(candidateCycle.planningProblemPath)
        let candidateCyclePlanningProblem = try JSONDecoder().decode(
            XcircuiteCircuitPlanningProblem.self,
            from: Data(contentsOf: URL(filePath: planningProblemPath))
        )
        let commandHistorySummary = try #require(
            candidateCycle.signoffRepairCandidateCycleHistorySummary
        )
        #expect(commandHistorySummary.cycleCount == 1)
        #expect(commandHistorySummary.acceptedCount == (cycleResult.candidateVerification.accepted ? 1 : 0))
        #expect(commandHistorySummary.notAcceptedCount == (cycleResult.candidateVerification.accepted ? 0 : 1))
        #expect(commandHistorySummary.latestCycleIndex == 1)
        #expect(commandHistorySummary.latestAccepted == .some(cycleResult.candidateVerification.accepted))
        #expect(commandHistorySummary.consumedRejectedPlanFeedbackRecordCount == 1)
        #expect(commandHistorySummary.maximumGlobalRejectedPlanFeedbackCount == 1)
        #expect(commandHistorySummary.selectedActionIDs == cycleTrace.selectedActionIDs)
        #expect(commandHistorySummary.selectedActionDomainIDs == RunReviewTestSupport.selectedActionDomainIDs(from: cycleTrace))
        #expect(
            commandHistorySummary.selectedObjectiveDomainIDs
                == RunReviewTestSupport.selectedObjectiveDomainIDs(from: cycleTrace, problem: candidateCyclePlanningProblem)
        )
        #expect(
            commandHistorySummary.objectiveDomainSummaries.map(\.domainID)
                == commandHistorySummary.selectedObjectiveDomainIDs
        )
        #expect(commandHistorySummary.feedbackPenalizedActionIDs == RunReviewTestSupport.feedbackPenalizedActionIDs(from: cycleTrace))
        #expect(commandHistorySummary.feedbackRankChangeCount == RunReviewTestSupport.feedbackRankChanges(from: cycleTrace).count)
        #expect(commandHistorySummary.feedbackScoreDeltaCount == RunReviewTestSupport.feedbackScoreDeltas(from: cycleTrace).count)

        let candidatePlanPath = try #require(candidateCycle.candidatePlanPath)
        let planExecutionPath = try #require(candidateCycle.planExecutionPath)
        let planVerificationPath = try #require(candidateCycle.planVerificationPath)
        let cycleHistorySummaryPath = try #require(candidateCycle.candidateCycleHistorySummaryPath)
        #expect(FileManager.default.fileExists(atPath: candidatePlanPath))
        #expect(FileManager.default.fileExists(atPath: planExecutionPath))
        #expect(FileManager.default.fileExists(atPath: planVerificationPath))
        #expect(FileManager.default.fileExists(atPath: cycleHistorySummaryPath))
        let persistedHistorySummary = try JSONDecoder().decode(
            RunReviewSignoffRepairCandidateCycleHistorySummary.self,
            from: Data(contentsOf: URL(filePath: cycleHistorySummaryPath))
        )
        #expect(persistedHistorySummary == commandHistorySummary)
        let retainedHistory = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .summarizeSignoffRepairCandidateCycles,
            projectRootPath: root.path(percentEncoded: false)
        ))
        let retainedHistoryIndex = try #require(retainedHistory.signoffRepairCandidateCycleHistoryIndex)
        #expect(retainedHistoryIndex.runCount == 1)
        #expect(retainedHistoryIndex.cycleCount == commandHistorySummary.cycleCount)
        #expect(retainedHistoryIndex.acceptedCount == commandHistorySummary.acceptedCount)
        #expect(retainedHistoryIndex.notAcceptedCount == commandHistorySummary.notAcceptedCount)
        #expect(retainedHistoryIndex.consumedRejectedPlanFeedbackRecordCount == 1)
        #expect(retainedHistoryIndex.maximumGlobalRejectedPlanFeedbackCount == 1)
        #expect(retainedHistoryIndex.feedbackRankChangeCount == commandHistorySummary.feedbackRankChangeCount)
        #expect(retainedHistoryIndex.feedbackScoreDeltaCount == commandHistorySummary.feedbackScoreDeltaCount)
        #expect(retainedHistoryIndex.selectedActionDomainIDs == commandHistorySummary.selectedActionDomainIDs)
        #expect(retainedHistoryIndex.selectedObjectiveDomainIDs == commandHistorySummary.selectedObjectiveDomainIDs)
        #expect(retainedHistoryIndex.objectiveDomainSummaries == commandHistorySummary.objectiveDomainSummaries)
        #expect(retainedHistoryIndex.feedbackRankChangedActionIDs == commandHistorySummary.feedbackRankChangedActionIDs)
        #expect(retainedHistoryIndex.feedbackScoreDeltaActionIDs == commandHistorySummary.feedbackScoreDeltaActionIDs)
        #expect(retainedHistoryIndex.runs.first?.runID == runID)
        #expect(retainedHistoryIndex.runs.first?.summaryPath == ".xcircuite/runs/\(runID)/planning/candidate-cycle-history-summary.json")
        if let designDiffPath = candidateCycle.designDiffPath {
            #expect(FileManager.default.fileExists(atPath: designDiffPath))
        }
        if let cycleRejectedPlansPath = candidateCycle.rejectedPlansPath {
            #expect(FileManager.default.fileExists(atPath: cycleRejectedPlansPath))
        }

        let cycleActions = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunActions(runID: runID)
        #expect(cycleActions.contains { $0.actionKind == "planning.execute-candidate-plan" })
        #expect(cycleActions.contains { $0.actionKind == "planning.verify-candidate-plan" })
        let cycleSummaryAction = try #require(cycleActions.first {
            $0.actionKind == "review.runSignoffRepairCandidateCycle"
        })
        #expect(cycleSummaryAction.outputs.contains { $0.artifactID == "planning-plan-verification" })
        #expect(cycleSummaryAction.outputs.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.candidateCycleHistorySummaryArtifactID
        })
        #expect(cycleSummaryAction.context.iterationID == "1")
        let cycleArtifact = try #require(cycleSummaryAction.outputs.first {
            $0.artifactID == "signoff-repair-candidate-cycle-1"
        })
        let persistedCycle = try JSONDecoder().decode(
            RunReviewSignoffRepairCandidateCycleHistoryItem.self,
            from: Data(contentsOf: root.appending(path: cycleArtifact.path))
        )
        #expect(persistedCycle.rejectedPlanFeedbackRecordCount == 1)
        #expect(persistedCycle.globalRejectedPlanFeedbackCount == 1)
        #expect(persistedCycle.selectedActionIDs == cycleTrace.selectedActionIDs)
        #expect(persistedCycle.selectedActionDomainIDs == RunReviewTestSupport.selectedActionDomainIDs(from: cycleTrace))
        #expect(persistedCycle.selectedObjectiveDomainIDs == RunReviewTestSupport.selectedObjectiveDomainIDs(from: cycleTrace, problem: candidateCyclePlanningProblem))
        #expect(persistedCycle.feedbackPenalizedActionIDs == RunReviewTestSupport.feedbackPenalizedActionIDs(from: cycleTrace))
        #expect(persistedCycle.feedbackRankChanges == RunReviewTestSupport.feedbackRankChanges(from: cycleTrace))
        #expect(persistedCycle.feedbackScoreDeltas == RunReviewTestSupport.feedbackScoreDeltas(from: cycleTrace))

        let reloadedReview = try await RunReviewService().loadRun(runID: runID, projectRoot: root)
        #expect(reloadedReview.signoff.repairCandidateCycles.count == 1)
        let projectedCycle = try #require(reloadedReview.signoff.repairCandidateCycles.first)
        #expect(projectedCycle.actionID == cycleSummaryAction.actionID)
        #expect(projectedCycle.cycleIndex == 1)
        #expect(projectedCycle.status == cycleSummaryAction.status)
        #expect(projectedCycle.planID == cycleResult.candidateGeneration.planID)
        #expect(projectedCycle.generationStatus == cycleResult.candidateGeneration.status)
        #expect(projectedCycle.executionStatus == cycleResult.candidateExecution.status)
        #expect(projectedCycle.verificationStatus == cycleResult.candidateVerification.status)
        #expect(projectedCycle.accepted == cycleResult.candidateVerification.accepted)
        #expect(projectedCycle.rejectedPlansPath == rejectedPlansPath)
        #expect(projectedCycle.rejectedPlanFeedbackRecordCount == 1)
        #expect(projectedCycle.globalRejectedPlanFeedbackCount == 1)
        #expect(projectedCycle.selectedActionIDs == cycleTrace.selectedActionIDs)
        #expect(projectedCycle.selectedActionDomainIDs == RunReviewTestSupport.selectedActionDomainIDs(from: cycleTrace))
        #expect(
            projectedCycle.selectedObjectiveDomainIDs
                == RunReviewTestSupport.selectedObjectiveDomainIDs(from: cycleTrace, problem: candidateCyclePlanningProblem)
        )
        #expect(projectedCycle.feedbackPenalizedActionIDs == RunReviewTestSupport.feedbackPenalizedActionIDs(from: cycleTrace))
        #expect(projectedCycle.feedbackRankChanges == RunReviewTestSupport.feedbackRankChanges(from: cycleTrace))
        #expect(projectedCycle.feedbackScoreDeltas == RunReviewTestSupport.feedbackScoreDeltas(from: cycleTrace))
        #expect(projectedCycle.candidatePlanArtifact?.path == cycleResult.candidateGeneration.candidatePlanArtifact.path)
        #expect(projectedCycle.planExecutionArtifact?.path == cycleResult.candidateExecution.planExecutionArtifact.path)
        #expect(projectedCycle.planVerificationArtifact?.path == cycleResult.candidateVerification.planVerificationArtifact.path)
        #expect(projectedCycle.rejectedPlansArtifact?.path == cycleResult.candidateVerification.rejectedPlansArtifact?.path)
        #expect(projectedCycle.designDiffArtifact?.path == cycleResult.candidateExecution.designDiffArtifact?.path)

        let projectedHistorySummary = reloadedReview.signoff.repairCandidateCycleHistorySummary
        #expect(projectedHistorySummary.cycleCount == 1)
        #expect(projectedHistorySummary.acceptedCount == (projectedCycle.accepted ? 1 : 0))
        #expect(projectedHistorySummary.notAcceptedCount == (projectedCycle.accepted ? 0 : 1))
        #expect(projectedHistorySummary.latestCycleIndex == 1)
        #expect(projectedHistorySummary.latestAccepted == .some(projectedCycle.accepted))
        #expect(projectedHistorySummary.consumedRejectedPlanFeedbackRecordCount == 1)
        #expect(projectedHistorySummary.maximumGlobalRejectedPlanFeedbackCount == 1)
        #expect(projectedHistorySummary.selectedActionIDs == projectedCycle.selectedActionIDs)
        #expect(projectedHistorySummary.selectedActionDomainIDs == projectedCycle.selectedActionDomainIDs)
        #expect(projectedHistorySummary.selectedObjectiveDomainIDs == projectedCycle.selectedObjectiveDomainIDs)
        #expect(projectedHistorySummary.feedbackPenalizedActionIDs == projectedCycle.feedbackPenalizedActionIDs)
        #expect(projectedHistorySummary.feedbackRankChangeCount == projectedCycle.feedbackRankChanges.count)
        #expect(projectedHistorySummary.feedbackScoreDeltaCount == projectedCycle.feedbackScoreDeltas.count)
    }

    @Test @MainActor func signoffSummaryRequiresVerifiedIntegrity() async throws {
        let fixture = try await RunReviewSignoffFixture.make()
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        var bundle = fixture.review.bundle
        let drcIndex = try #require(bundle.artifacts.firstIndex { $0.reference.locator.location.value == fixture.drcPath })
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

    @Test @MainActor func signoffRepairPlanningRequiresVerifiedRepairHintIntegrity() async throws {
        let fixture = try await RunReviewSignoffFixture.make()
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        var bundle = fixture.review.bundle
        let hintIndex = try #require(bundle.artifacts.firstIndex { $0.reference.locator.location.value == fixture.drcRepairHintPath })
        bundle.artifacts[hintIndex].integrity = FlowRunReviewArtifactIntegrity(
            status: .sha256Mismatch,
            expectedSHA256: String(repeating: "a", count: 64),
            actualSHA256: String(repeating: "b", count: 64),
            expectedByteCount: 10,
            actualByteCount: 11,
            message: "Artifact SHA-256 mismatch"
        )

        let service = RunReviewService(reviewBundler: StaticRunReviewBundler(bundle: bundle))
        await #expect(throws: RunReviewServiceError.signoffRepairHintIntegrityUnverified(
            path: fixture.drcRepairHintPath,
            status: "sha256Mismatch",
            message: "Artifact SHA-256 mismatch"
        )) {
            try await service.formulateSignoffRepairPlanningProblem(
                runID: fixture.runID,
                actorKind: .agent,
                actorIdentifier: "agent-1",
                projectRoot: fixture.root
            )
        }
    }

    @Test @MainActor func waiverReviewRequiresVerifiedArtifactIntegrity() async throws {
        let fixture = try await RunReviewSignoffFixture.make()
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.root) }
        defer { RunReviewTestSupport.removeTemporaryRoot(fixture.outsideRoot) }

        var bundle = fixture.review.bundle
        let drcIndex = try #require(bundle.artifacts.firstIndex { $0.reference.locator.location.value == fixture.drcPath })
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
        let envelopeIndex = try #require(bundle.artifacts.firstIndex { $0.reference.locator.location.value == fixture.drcEnvelopePath })
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
        let logIndex = try #require(bundle.artifacts.firstIndex { $0.reference.locator.location.value == fixture.drcLogPath })
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
        let ledgerArtifact = FlowRunReviewArtifact(
            reference: ArtifactReference(
                id: try ArtifactID(rawValue: "shared-ledger-artifact"),
                locator: ArtifactLocator(
                    location: try ArtifactLocation(workspaceRelativePath: sharedPath),
                    role: .output,
                    kind: .report,
                    format: .json
                ),
                digest: try ContentDigest(algorithm: .sha256, hexadecimalValue: expectedSHA256),
                byteCount: 128
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
            selectedCommands: fixture.review.planning.selectedCommands,
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
            suggestedCommandSelections: fixture.review.suggestedCommandSelections,
            planning: planning,
            signoff: conflictingSignoff,
            waivers: fixture.review.waivers,
            failureStates: fixture.review.failureStates,
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
        let logIndex = try #require(bundle.artifacts.firstIndex { $0.reference.locator.location.value == fixture.drcLogPath })
        let original = bundle.artifacts[logIndex]
        let duplicate = FlowRunReviewArtifact(
            reference: ArtifactReference(
                id: try ArtifactID(rawValue: "drc-raw-log-alias"),
                locator: original.reference.locator,
                digest: original.reference.digest,
                byteCount: original.reference.byteCount,
                producer: original.reference.producer
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

        #expect(preview.artifact.reference.id.rawValue == "drc-raw-log-alias")
        #expect(preview.text == "DRC_SUMMARY ")
        #expect(preview.truncated)
    }
}

private struct StaticRunReviewBundler: FlowRunReviewBundling {
    let bundle: FlowRunReviewBundle

    func makeReviewBundle(runID: String, projectRoot: URL) throws -> FlowRunReviewBundle {
        bundle
    }
}
