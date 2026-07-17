import Foundation
import Testing
import DesignFlowKernel
import LayoutCore
import ToolQualification
import Xcircuite
@testable import CircuitStudioApp
@testable import CircuitStudioCore

/// P4 gate: the cockpit and the flow kernel close one loop over one
/// ledger — a run blocks at the approval gate, the reviewer reads the
/// SAME stage results the kernel persisted and records a decision, and
/// re-running the same runID resumes past the gate.
@Suite("Run review service", .timeLimit(.minutes(2)))
struct RunReviewServiceTests {

    @Test func toolchainProjectionExposesTrustAndArtifactIntegrity() throws {
        let toolchainPath = ".xcircuite/runs/run-toolchain/toolchain.json"
        let profilePath = ".xcircuite/runs/run-toolchain/toolchain-profile.json"
        let toolchainArtifact = FlowRunReviewArtifact(
            reference: try RunReviewTestSupport.artifactReference(
                artifactID: "toolchain-manifest",
                path: toolchainPath
            ),
            purpose: .toolchain,
            integrity: FlowRunReviewArtifactIntegrity(
                status: .verified,
                message: "Artifact integrity is verified."
            )
        )
        let profileArtifact = FlowRunReviewArtifact(
            reference: try RunReviewTestSupport.artifactReference(
                artifactID: "flow-toolchain-profile",
                path: profilePath
            ),
            purpose: .toolchainProfile,
            integrity: FlowRunReviewArtifactIntegrity(
                status: .sha256Mismatch,
                message: "Artifact digest does not match."
            )
        )
        let bundle = FlowRunReviewBundle(
            runID: "run-toolchain",
            status: .blocked,
            summary: FlowRunLedgerSummary(
                runID: "run-toolchain",
                status: .blocked,
                toolchain: FlowRunToolchainSummary(
                    stageCount: 4,
                    selectedToolIDs: ["drc-native", "lvs-native"],
                    rejectedEvaluationCount: 3,
                    missingSelectionStageIDs: ["pex"],
                    profileID: "sky130-signoff",
                    pdkID: "sky130",
                    technologyCatalogID: "sky130-catalog",
                    technologyCatalogPath: "pdk/catalog.json",
                    profileArtifactPath: "toolchain-profile.json"
                )
            ),
            artifacts: [toolchainArtifact, profileArtifact]
        )

        let projection = RunReviewToolchainProjection(bundle: bundle)

        #expect(projection.hasContent)
        #expect(projection.selectedToolIDs == ["drc-native", "lvs-native"])
        #expect(projection.rejectedEvaluationCount == 3)
        #expect(projection.missingSelectionStageIDs == ["pex"])
        #expect(projection.summary?.profileID == "sky130-signoff")
        #expect(projection.summary?.pdkID == "sky130")
        #expect(projection.summary?.technologyCatalogID == "sky130-catalog")
        #expect(projection.artifacts.map(\.reference.locator.location.value) == [toolchainPath, profilePath])
        #expect(projection.hasUnverifiedArtifacts)
    }

    @Test func toolchainTrustCardPresentsEveryReviewField() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let sourceURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/CircuitStudioApp/Views/RunReviewToolchainCard.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for label in [
            "Selected tools",
            "Rejected",
            "Missing selections",
            "Profile",
            "PDK",
            "Technology catalog",
            "Catalog path",
            "Profile artifact",
            "Selected tool IDs",
            "Missing stage selections",
        ] {
            #expect(source.contains("\"\(label)\""))
        }
        #expect(source.contains("artifact.integrity?.status.rawValue"))
    }

    @Test func reviewLoopBlocksDecidesAndResumes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { RunReviewTestSupport.removeTemporaryRoot(root) }

        let request = FlowOperationRequest(
            workspaceID: try await RunReviewTestSupport.workspaceID(projectRoot: root),
            runID: "run-review",
            intent: "Review loop",
            stages: [
                FlowStageDefinition(stageID: "001-drc", displayName: "DRC", requiresApproval: true),
                FlowStageDefinition(stageID: "002-ship", displayName: "Ship"),
            ]
        )
        let summaryPath = ".xcircuite/runs/run-review/stages/001-drc/raw/drc-summary.json"
        let summaryPayload = Data(#"{"artifactID":"drc-summary"}"#.utf8)
        let executors: [any FlowStageExecutor] = [
            RunReviewPassingExecutor(
                stageID: "001-drc",
                artifacts: [
                    try RunReviewTestSupport.artifactReference(
                        artifactID: "drc-summary",
                        path: summaryPath,
                        kind: .report,
                        format: .json
                    ),
                ],
                artifactPayloads: [summaryPath: summaryPayload]
            ),
            RunReviewPassingExecutor(stageID: "002-ship"),
        ]

        // 1. The flow blocks at the approval gate.
        let blocked = try await RunReviewTestSupport.orchestrator(projectRoot: root).run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(blocked.status == .blocked)

        // 2. The cockpit reads the ledger: one run, one stage awaiting
        //    this reviewer.
        let service = RunReviewService()
        let runs = try await service.listRuns(projectRoot: root)
        #expect(runs.map(\.runID) == ["run-review"])

        var review = try await service.loadRun(runID: "run-review", projectRoot: root)
        #expect(review.status == .blocked)
        #expect(review.stages.count == 1)
        #expect(review.bundle.reviewItems.contains {
            $0.kind == .approvalGate
                && $0.status == .needsReview
                && $0.stageID == "001-drc"
        })
        #expect(review.bundle.artifacts.contains {
            $0.purpose.rawValue == "stage-result"
                && $0.reference.locator.location.value == ".xcircuite/runs/run-review/stages/001-drc/result.json"
        })
        #expect(review.bundle.artifacts.contains {
            $0.purpose.rawValue == "stage-summary"
                && $0.reference.id.rawValue == "drc-summary"
                && $0.reference.locator.location.value == summaryPath
                && $0.integrity?.status == .verified
                && $0.integrity?.actualByteCount == UInt64(summaryPayload.count)
        })
        let awaiting = try #require(review.stages.first)
        #expect(awaiting.awaitingApproval)
        #expect(awaiting.approval == nil)

        // 3. The reviewer decides; the decision lands in the ledger.
        _ = try await service.decide(
            runID: "run-review",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1",
            note: "verified against the report",
            projectRoot: root
        )
        review = try await service.loadRun(runID: "run-review", projectRoot: root)
        #expect(review.bundle.reviewItems.contains {
            $0.kind == .approvalGate
                && $0.status == .readyToResume
                && $0.nextActionID == "001-drc-resume-run"
                && $0.artifactPaths.contains(".xcircuite/runs/run-review/approvals/001-drc.json")
        })
        let approvalStore = try XcircuiteWorkspaceStore(projectRoot: root)
        let approvalActions = try await approvalStore.loadRunActions(runID: "run-review")
        let approvalAction = try #require(approvalActions.first {
            $0.actionKind == FlowRunReviewDecisionKind.approval.rawValue
        })
        #expect(approvalAction.actor.kind == .human)
        #expect(approvalAction.actor.identifier == "reviewer-1")
        let approvalDecision = try #require(try FlowRunReviewDecision(record: approvalAction))
        #expect(approvalDecision.decision == "approved")
        #expect(approvalDecision.targetID == "001-drc")
        #expect(approvalDecision.reason == "verified against the report")

        // 4. Re-running the same runID resumes past the gate; the
        //    cockpit shows the full picture.
        var resumeRequest = request
        resumeRequest.allowExistingRun = true
        let resumed = try await RunReviewTestSupport.orchestrator(projectRoot: root).run(
            request: resumeRequest,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(resumed.status == .succeeded)

        review = try await service.loadRun(runID: "run-review", projectRoot: root)
        #expect(review.stages.count == 2)
        let decided = try #require(review.stages.first { $0.result.stageID == "001-drc" })
        #expect(!decided.awaitingApproval)
        #expect(decided.approval?.verdict == .approved)
        #expect(decided.approval?.reviewer == "reviewer-1")
        #expect(decided.result.gates.contains { $0.gateID == "approval" && $0.status == .passed })
    }

    @Test func runLedgerFlowReviewProjectionSurfacesSharedBundleRefs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-flow-projection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { RunReviewTestSupport.removeTemporaryRoot(root) }

        let runID = "run-flow-review"
        let stageID = "001-drc"
        let summaryPath = ".xcircuite/runs/\(runID)/stages/\(stageID)/raw/drc-summary.json"
        _ = try await RunReviewTestSupport.orchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                workspaceID: try await RunReviewTestSupport.workspaceID(projectRoot: root),
                runID: runID,
                intent: "Review projection",
                stages: [
                    FlowStageDefinition(stageID: stageID, displayName: "DRC", requiresApproval: true),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                RunReviewPassingExecutor(
                    stageID: stageID,
                    artifacts: [
                        try RunReviewTestSupport.artifactReference(
                            artifactID: "drc-summary",
                            path: summaryPath,
                            kind: .report,
                            format: .json
                        ),
                    ],
                    artifactPayloads: [summaryPath: Data(#"{"artifactID":"drc-summary"}"#.utf8)]
                ),
            ]
        )

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let ladderPath = ".xcircuite/runs/\(runID)/review/stage-artifact-ladder.json"
        let planningPath = ".xcircuite/runs/\(runID)/planning/candidate-plan.json"
        let retainedPath = ".xcircuite/runs/\(runID)/retention/retained-ci-regression-budget.json"
        let waiverPath = ".xcircuite/runs/\(runID)/waivers/waiver-review.json"
        _ = try await RunReviewTestSupport.writeRunJSONArtifact(
            Data(#"{"schemaVersion":1,"readiness":"needsReview"}"#.utf8),
            path: ladderPath,
            artifactID: "review-stage-artifact-ladder",
            root: root,
            runID: runID
        )
        _ = try await RunReviewTestSupport.writeRunJSONArtifact(
            Data(#"{"schemaVersion":1,"planID":"plan-1","steps":[]}"#.utf8),
            path: planningPath,
            artifactID: "planning-candidate-plan",
            root: root,
            runID: runID
        )
        _ = try await RunReviewTestSupport.writeRunJSONArtifact(
            Data(#"{"schemaVersion":1,"status":"failed","failures":[{"code":"retained_ci_regression_budget_evidence_stale"}]}"#.utf8),
            path: retainedPath,
            artifactID: "retained-ci-regression-budget",
            root: root,
            runID: runID
        )
        let waiverRef = try await RunReviewTestSupport.writeRunJSONArtifact(
            Data(#"{"schemaVersion":1,"waiverID":"waiver-1","status":"accepted"}"#.utf8),
            path: waiverPath,
            artifactID: "waiver-review",
            root: root,
            runID: runID
        )

        let service = RunReviewService()
        _ = try await service.decide(
            runID: runID,
            stageID: stageID,
            verdict: .approved,
            reviewer: "reviewer-1",
            note: "reviewed",
            projectRoot: root
        )
        try await store.appendReviewDecisionAction(
            FlowRunReviewDecisionRequest(
                actionID: "waiver-decision-1",
                runID: runID,
                stageID: stageID,
                actor: FlowRunActor(kind: .human, identifier: "reviewer-1"),
                decisionKind: .waiver,
                decision: "accepted",
                targetID: "waiver-1",
                targetPath: waiverPath,
                reason: "Reviewed waiver is accepted.",
                outputs: [waiverRef]
            )
        )
        try await store.appendReviewDecisionAction(
            FlowRunReviewDecisionRequest(
                actionID: "resume-decision-1",
                runID: runID,
                actor: FlowRunActor(kind: .human, identifier: "reviewer-1"),
                decisionKind: .resume,
                decision: "requested",
                targetID: runID,
                reason: "Approval and waiver decisions are recorded."
            )
        )

        let review = try await service.loadRun(runID: runID, projectRoot: root)
        #expect(review.flowReview.hasContent)
        #expect(review.flowReview.signoffLadderArtifacts.contains {
            $0.purpose.rawValue == "stage-artifact-ladder" && $0.reference.locator.location.value == ladderPath
        })
        #expect(review.flowReview.planningArtifacts.contains {
            $0.purpose.rawValue == "planning-candidate-plan" && $0.reference.locator.location.value == planningPath
        })
        #expect(review.flowReview.retainedHistoryArtifacts.contains {
            $0.purpose.rawValue == "retained-ci-regression-budget" && $0.reference.locator.location.value == retainedPath
        })
        #expect(review.flowReview.approvalActions.map(\.decision) == ["approved"])
        #expect(review.flowReview.waiverActions.map(\.targetID) == ["waiver-1"])
        #expect(review.flowReview.resumeActions.map(\.targetID) == [runID])
        #expect(review.flowReview.resumeItems.contains {
            $0.kind == .approvalGate && $0.status == .readyToResume
        })
        #expect(review.flowReview.blockedItems.contains {
            $0.kind == .retainedHistory
                && $0.diagnosticCodes.contains("retained_ci_regression_budget_evidence_stale")
        })
        #expect(review.flowReview.coverageDomains.contains { $0.domain == "approval" })
        #expect(review.flowReview.coverageDomains.contains { $0.domain == "waiver" })
        #expect(review.flowReview.coverageDomains.contains { $0.domain == "resume" })
        #expect(review.flowReview.coverageDomains.contains { $0.domain == "planning" })
        #expect(review.flowReview.coverageDomains.contains { $0.domain == "retained-history" })
        #expect(review.flowReview.coverageRefs.contains {
            $0.domain == "retained-history"
                && $0.path == retainedPath
                && $0.reviewItemIDs == ["review-retained-history"]
        })
        #expect(review.retainedDashboard.hasContent)
        #expect(review.retainedDashboard.status == .needsRepair)
        #expect(review.retainedDashboard.artifactStates.contains {
            $0.role == "retained-ci-regression-budget"
                && $0.path == retainedPath
                && $0.evidenceStatus == "stale"
                && $0.diagnosticCodes.contains("retained_ci_regression_budget_evidence_stale")
        })
        #expect(review.retainedDashboard.blockerSummaries.contains {
            $0.id == "review-retained-history"
                && $0.status == .needsRepair
                && $0.nextActionID == "repair-retained-history-evidence"
        })
        #expect(review.retainedDashboard.decisionSummaries.map(\.targetID).contains("waiver-1"))
        #expect(review.retainedDashboard.decisionSummaries.map(\.targetID).contains(runID))
        #expect(review.retainedDashboard.diagnosticCodes.contains("retained_ci_regression_budget_evidence_stale"))

        let dashboardRef = try await service.persistRetainedDashboardProjection(
            runID: runID,
            projectRoot: root
        )
        #expect(dashboardRef.artifactID == "retained-dashboard-projection")
        #expect(dashboardRef.path == ".xcircuite/runs/\(runID)/review/retained-dashboard-projection.json")
        #expect(!dashboardRef.digest.hexadecimalValue.isEmpty)
        #expect(dashboardRef.byteCount > 0)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persistedProjection = try decoder.decode(
            RunReviewRetainedDashboardProjection.self,
            from: Data(contentsOf: root.appending(path: dashboardRef.path))
        )
        #expect(persistedProjection.status == .needsRepair)
        #expect(persistedProjection.artifactStates.contains { $0.path == retainedPath })
        let runManifest = try await store.readJSON(
            FlowRunManifest.self,
            from: ".xcircuite/runs/\(runID)/manifest.json"
        )
        #expect(runManifest.artifacts.contains {
            $0.artifactID == "retained-dashboard-projection"
                && $0.path == dashboardRef.path
        })
    }

    @Test func flowReviewProjectionSeparatesUnverifiedArtifactsFromDecisionRefs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-flow-integrity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { RunReviewTestSupport.removeTemporaryRoot(root) }

        let runID = "run-flow-integrity"
        let stageID = "001-plan"
        _ = try await RunReviewTestSupport.orchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                workspaceID: try await RunReviewTestSupport.workspaceID(projectRoot: root),
                runID: runID,
                intent: "Review projection integrity",
                stages: [
                    FlowStageDefinition(stageID: stageID, displayName: "Planning", requiresApproval: true),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                RunReviewPassingExecutor(stageID: stageID),
            ]
        )

        let planningPath = ".xcircuite/runs/\(runID)/planning/candidate-plan.json"
        _ = try await RunReviewTestSupport.writeRunJSONArtifact(
            Data(#"{"schemaVersion":1,"planID":"plan-1","steps":[]}"#.utf8),
            path: planningPath,
            artifactID: "planning-candidate-plan",
            root: root,
            runID: runID
        )
        try Data(#"{"schemaVersion":1,"planID":"plan-2","steps":[]}"#.utf8)
            .write(to: root.appending(path: planningPath), options: .atomic)

        let review = try await RunReviewService().loadRun(runID: runID, projectRoot: root)
        #expect(!review.flowReview.planningArtifacts.contains { $0.reference.locator.location.value == planningPath })
        #expect(review.flowReview.integrityIssueArtifacts.contains {
            $0.reference.locator.location.value == planningPath && $0.integrity?.status == .sha256Mismatch
        })
        let planningDomain = try #require(review.flowReview.coverageDomains.first {
            $0.domain == "planning"
        })
        #expect(!planningDomain.artifactPaths.contains(planningPath))
        #expect(planningDomain.unverifiedArtifactPaths.contains(planningPath))
    }

    @Test func retainedDashboardProjectionRejectsUnsafeRunIDBeforeWriting() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("retained-dashboard-validation-\(UUID().uuidString)")
        let root = parent.appending(path: "project")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { RunReviewTestSupport.removeTemporaryRoot(parent) }

        let escapedName = "retained-dashboard-escape-\(UUID().uuidString)"
        let invalidRunID = "../../../\(escapedName)"
        let bundle = FlowRunReviewBundle(
            runID: invalidRunID,
            status: .blocked,
            summary: FlowRunLedgerSummary(
                runID: invalidRunID,
                status: .blocked
            )
        )
        let service = RunReviewService(
            reviewBundler: RetainedDashboardStaticReviewBundler(bundle: bundle)
        )

        await #expect(throws: FlowIdentifierValidationError.invalidIdentifier(kind: "runID", value: invalidRunID)) {
            _ = try await service.persistRetainedDashboardProjection(
                runID: invalidRunID,
                projectRoot: root
            )
        }
        let escapedProjection = parent
            .appending(path: escapedName)
            .appending(path: RunReviewService.retainedDashboardRelativePath)
        #expect(!FileManager.default.fileExists(atPath: escapedProjection.path(percentEncoded: false)))
    }

    @Test func runReviewViewSurfacesFlowReviewProjectionCard() throws {
        let source = try RunReviewTestSupport.projectSource("Sources/CircuitStudioApp/Views/RunReviewView.swift")
        let cardSource = try RunReviewTestSupport.projectSource(
            "Sources/CircuitStudioApp/Views/RunReviewFlowReviewProjectionCard.swift"
        )
        #expect(source.contains("review.flowReview.hasContent"))
        #expect(source.contains("RunReviewFlowReviewProjectionCard(projection: review.flowReview)"))
        #expect(cardSource.contains("projection.integrityIssueArtifacts"))
        #expect(cardSource.contains("Integrity Issues"))
    }

    @Test func runReviewViewSurfacesRetainedDashboardCard() throws {
        let source = try RunReviewTestSupport.projectSource("Sources/CircuitStudioApp/Views/RunReviewView.swift")
        #expect(source.contains("review.retainedDashboard.hasContent"))
        #expect(source.contains("RunReviewRetainedDashboardCard(projection: review.retainedDashboard)"))
    }

    @Test func runReviewViewClearsStaleLoadErrorWhenSelectionIsCleared() throws {
        let source = try RunReviewTestSupport.projectSource("Sources/CircuitStudioApp/Views/RunReviewView.swift")
        #expect(source.contains("guard let selectedRunID else {"))
        #expect(source.contains("loadError = nil"))
    }

    @Test func reviewFailureStatesProjectMissingIntegrityBlockedAndCanonicalIntegrityFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-failure-states-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { RunReviewTestSupport.removeTemporaryRoot(root) }

        let runID = "run-failure-states"
        let stageID = "001-drc"
        let rawPrefix = ".xcircuite/runs/\(runID)/stages/\(stageID)/raw"
        let missingPath = "\(rawPrefix)/missing-report.json"
        let mismatchPath = "\(rawPrefix)/mismatch-report.json"
        let stalePath = "\(rawPrefix)/stale-report.json"
        let missingPayload = Data(#"{"state":"will-be-removed"}"#.utf8)
        let mismatchPayload = Data(#"{"state":"original"}"#.utf8)
        let stalePayload = Data(#"{"state":"original-stale"}"#.utf8)
        _ = try await RunReviewTestSupport.orchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                workspaceID: try await RunReviewTestSupport.workspaceID(projectRoot: root),
                runID: runID,
                intent: "Review failure states",
                stages: [
                    FlowStageDefinition(stageID: stageID, displayName: "DRC", requiresApproval: true),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                RunReviewPassingExecutor(
                    stageID: stageID,
                    artifacts: [
                        try RunReviewTestSupport.artifactReference(
                            artifactID: "missing-report",
                            path: missingPath,
                            kind: .report,
                            format: .json
                        ),
                        try RunReviewTestSupport.artifactReference(
                            artifactID: "mismatch-report",
                            path: mismatchPath,
                            kind: .report,
                            format: .json
                        ),
                        try RunReviewTestSupport.artifactReference(
                            artifactID: "stale-report",
                            path: stalePath,
                            kind: .report,
                            format: .json
                        ),
                    ],
                    artifactPayloads: [
                        missingPath: missingPayload,
                        mismatchPath: mismatchPayload,
                        stalePath: stalePayload,
                    ]
                ),
            ]
        )

        try FileManager.default.removeItem(at: root.appending(path: missingPath))
        let mismatchURL = root.appending(path: mismatchPath)
        try Data(#"{"state":"changed-after-ledger"}"#.utf8).write(to: mismatchURL, options: .atomic)
        let staleURL = root.appending(path: stalePath)
        try Data(#"{"state":"also-changed-after-ledger"}"#.utf8).write(to: staleURL, options: .atomic)

        let service = RunReviewService()
        let review = try await service.loadRun(runID: runID, projectRoot: root)
        let failureStates = review.failureStates

        #expect(failureStates.count(of: .missingArtifact) >= 1)
        #expect(failureStates.count(of: .integrityMismatch) >= 1)
        #expect(failureStates.count(of: .integrityMismatch) >= 2)
        #expect(failureStates.count(of: .blockedGate) >= 1)
        #expect(service.failureStateSummary(from: review) == failureStates)

        let missing = try #require(failureStates.states(of: .missingArtifact).first {
            $0.artifactReferences.contains { $0.path == missingPath && $0.integrityStatus == "missingArtifact" }
        })
        #expect(missing.suggestedActions.contains("restore-or-regenerate-artifact"))

        let mismatch = try #require(failureStates.states(of: .integrityMismatch).first {
            $0.artifactReferences.contains {
                $0.path == mismatchPath
                    && ($0.integrityStatus == "sha256Mismatch" || $0.integrityStatus == "byteCountMismatch")
            }
        })
        #expect(mismatch.suggestedActions.contains("rerun-artifact-integrity-gate"))

        let stale = try #require(failureStates.states(of: .integrityMismatch).first {
            $0.artifactReferences.contains {
                $0.path == stalePath
                    && ($0.integrityStatus == "byteCountMismatch" || $0.integrityStatus == "sha256Mismatch")
            }
        })
        #expect(stale.suggestedActions.contains("rerun-artifact-integrity-gate"))

        let blockedGate = try #require(failureStates.states(of: .blockedGate).first {
            $0.stageID == stageID && $0.gateID == "approval"
        })
        #expect(blockedGate.nextActionID == "\(stageID)-decide-approval")
        #expect(blockedGate.suggestedActions.contains("record-approval-decision"))

        let unsupportedBundle = FlowRunReviewBundle(
            runID: "unsupported-action",
            status: .blocked,
            summary: FlowRunLedgerSummary(
                runID: "unsupported-action",
                status: .blocked,
                nextActions: [
                    FlowRunNextAction(
                        actionID: "unsupported-repair",
                        kind: "repair",
                        severity: .warning,
                        reason: "An unsupported repair command was proposed.",
                        suggestedActions: [
                            FlowRunSuggestedAction(
                                id: "unsupported-action",
                                readiness: .requiresInput,
                                operation: .executeCandidatePlan,
                                runID: "unsupported-action",
                                reason: "Unsupported by the local toolchain."
                            ),
                        ]
                    ),
                ]
            )
        )
        let unsupportedSummary = service.failureStateSummary(
            bundle: unsupportedBundle,
            stages: [],
            planningDecodeIssues: [],
            signoffDecodeIssues: [],
            waiverDecodeIssues: []
        )
        let unsupported = try #require(unsupportedSummary.states(of: .unsupportedAction).first)
        #expect(unsupported.nextActionID == "unsupported-repair")
        #expect(unsupported.suggestedActions == ["unsupported-action"])
    }

    @Test func waiverEditVerificationContextReportsMissingInputs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-context-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { RunReviewTestSupport.removeTemporaryRoot(root) }

        let runID = "run-missing-context"
        let stageID = "001-review"
        let designSpecPath = ".xcircuite/runs/\(runID)/stages/\(stageID)/raw/design-spec.json"
        let layoutDocumentPath = ".xcircuite/runs/\(runID)/stages/\(stageID)/raw/layout-document.json"
        let service = RunReviewService()

        _ = try await RunReviewTestSupport.orchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                workspaceID: try await RunReviewTestSupport.workspaceID(projectRoot: root),
                runID: runID,
                intent: "Missing review context",
                stages: [
                    FlowStageDefinition(stageID: stageID, displayName: "Review"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                RunReviewPassingExecutor(
                    stageID: stageID,
                    artifacts: [
                        try RunReviewTestSupport.artifactReference(
                            artifactID: "design-spec",
                            path: designSpecPath,
                            kind: .other,
                            format: .json
                        ),
                    ],
                    artifactPayloads: [
                        designSpecPath: try RunReviewTestSupport.encodedJSONData(RunReviewTestSupport.reviewVerificationDesignSpec()),
                    ]
                ),
            ]
        )

        let missingLayoutReview = try await service.loadRun(runID: runID, projectRoot: root)
        await #expect(throws: RunReviewServiceError.waiverEditVerificationLayoutDocumentNotFound(runID: runID)) {
            try await service.waiverEditVerificationContext(
                review: missingLayoutReview,
                projectRoot: root
            )
        }

        // Add a deliberately missing artifact reference without rewriting the
        // already-succeeded run lifecycle or replaying its stage evidence.
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        var ledger = try await store.loadRunLedger(runID: runID)
        let missingLayoutArtifact = try RunReviewTestSupport.artifactReference(
            artifactID: "layout-document",
            path: layoutDocumentPath,
            kind: .layout,
            format: .json
        )
        ledger.artifacts.append(missingLayoutArtifact)
        let manifest = ledger.runManifest
        ledger.runManifest = try FlowRunManifest(
            runID: manifest.runID,
            status: manifest.status,
            revision: manifest.revision,
            actor: manifest.actor,
            intent: manifest.intent,
            parentRunID: manifest.parentRunID,
            createdAt: manifest.createdAt,
            updatedAt: manifest.updatedAt,
            startedAt: manifest.startedAt,
            finishedAt: manifest.finishedAt,
            artifacts: manifest.artifacts + [missingLayoutArtifact]
        )
        let missingArtifactLoader = RunReviewStaticLedgerLoader(ledger: ledger)
        let missingArtifactService = RunReviewService(
            ledgerLoader: missingArtifactLoader,
            reviewLedgerLoader: missingArtifactLoader
        )

        let missingFileReview = try await missingArtifactService.loadRun(runID: runID, projectRoot: root)
        await #expect(throws: RunReviewServiceError.waiverEditVerificationInputMissing(path: layoutDocumentPath)) {
            try await missingArtifactService.waiverEditVerificationContext(
                review: missingFileReview,
                projectRoot: root
            )
        }
    }

    @Test func rejectionIsVisibleInTheReview() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-reject-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { RunReviewTestSupport.removeTemporaryRoot(root) }

        let request = FlowOperationRequest(
            workspaceID: try await RunReviewTestSupport.workspaceID(projectRoot: root),
            runID: "run-reject",
            intent: "Review loop",
            stages: [
                FlowStageDefinition(stageID: "001-drc", displayName: "DRC", requiresApproval: true),
            ]
        )
        let executors: [any FlowStageExecutor] = [RunReviewPassingExecutor(stageID: "001-drc")]

        _ = try await RunReviewTestSupport.orchestrator(projectRoot: root).run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        let service = RunReviewService()
        _ = try await service.decide(
            runID: "run-reject",
            stageID: "001-drc",
            verdict: .rejected,
            reviewer: "reviewer-1",
            note: "rail too narrow",
            projectRoot: root
        )
        var resumeRequest = request
        resumeRequest.allowExistingRun = true
        let rerun = try await RunReviewTestSupport.orchestrator(projectRoot: root).run(
            request: resumeRequest,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(rerun.status == .failed)

        let review = try await service.loadRun(runID: "run-reject", projectRoot: root)
        let stage = try #require(review.stages.first)
        #expect(stage.approval?.verdict == .rejected)
        #expect(stage.result.gates.contains { $0.gateID == "approval" && $0.status == .failed })
        #expect(review.bundle.reviewItems.contains {
            $0.kind == .stageFailure
                && $0.status == .needsRepair
                && $0.stageID == "001-drc"
        })
    }


}

private struct RetainedDashboardStaticReviewBundler: FlowRunReviewBundling {
    let bundle: FlowRunReviewBundle

    func makeReviewBundle(runID: String, workspaceID: FlowWorkspaceID) async throws -> FlowRunReviewBundle {
        bundle
    }
}

private struct RunReviewStaticLedgerLoader: FlowRunLedgerLoading, FlowRunReviewLedgerLoading {
    let ledger: FlowRunLedger

    func loadRunLedger(runID: String) async throws -> FlowRunLedger {
        ledger
    }

    func loadRunLedgerForReview(runID: String) async throws -> FlowRunLedger {
        ledger
    }
}
