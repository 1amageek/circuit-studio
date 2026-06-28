import Foundation
import Testing
import DesignFlowKernel
import LayoutCore
import ToolQualification
import Xcircuite
import XcircuitePackage
@testable import CircuitStudioApp
@testable import CircuitStudioCore

/// P4 gate: the cockpit and the flow kernel close one loop over one
/// ledger — a run blocks at the approval gate, the reviewer reads the
/// SAME stage results the kernel persisted and records a decision, and
/// re-running the same runID resumes past the gate.
@Suite("Run review service", .timeLimit(.minutes(2)))
struct RunReviewServiceTests {

    private struct PassingExecutor: FlowStageExecutor {
        let stageID: String
        let toolID = "stub-tool"
        var artifacts: [XcircuiteFileReference] = []
        var artifactPayloads: [String: Data] = [:]

        func execute(
            stage: FlowStageDefinition,
            context: FlowExecutionContext
        ) async throws -> FlowStageResult {
            var resolvedArtifacts = artifacts
            for index in resolvedArtifacts.indices {
                let path = resolvedArtifacts[index].path
                guard let payload = artifactPayloads[path] else {
                    continue
                }
                let url = context.projectRoot.appending(path: path)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try payload.write(to: url, options: .atomic)
                resolvedArtifacts[index].sha256 = XcircuiteHasher().sha256(data: payload)
                resolvedArtifacts[index].byteCount = Int64(payload.count)
            }

            return FlowStageResult(
                stageID: stage.stageID,
                status: .succeeded,
                gates: [FlowGateResult(gateID: "drc", status: .passed)],
                artifacts: resolvedArtifacts
            )
        }
    }

    @Test func reviewLoopBlocksDecidesAndResumes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { removeTemporaryRoot(root) }

        let request = FlowOperationRequest(
            projectRoot: root,
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
            PassingExecutor(
                stageID: "001-drc",
                artifacts: [
                    XcircuiteFileReference(
                        artifactID: "drc-summary",
                        path: summaryPath,
                        kind: .report,
                        format: .json
                    ),
                ],
                artifactPayloads: [summaryPath: summaryPayload]
            ),
            PassingExecutor(stageID: "002-ship"),
        ]

        // 1. The flow blocks at the approval gate.
        let blocked = try await DefaultFlowOrchestrator().run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(blocked.status == .blocked)

        // 2. The cockpit reads the ledger: one run, one stage awaiting
        //    this reviewer.
        let service = RunReviewService()
        let runs = try service.listRuns(projectRoot: root)
        #expect(runs.map(\.runID) == ["run-review"])

        var review = try service.loadRun(runID: "run-review", projectRoot: root)
        #expect(review.status == .blocked)
        #expect(review.stages.count == 1)
        #expect(review.bundle.reviewItems.contains {
            $0.kind == .approvalGate
                && $0.status == .needsReview
                && $0.stageID == "001-drc"
        })
        #expect(review.bundle.artifacts.contains {
            $0.role == "stage-result"
                && $0.path == ".xcircuite/runs/run-review/stages/001-drc/result.json"
        })
        #expect(review.bundle.artifacts.contains {
            $0.role == "stage-summary"
                && $0.artifactID == "drc-summary"
                && $0.path == summaryPath
                && $0.integrity?.status == .verified
                && $0.integrity?.actualByteCount == Int64(summaryPayload.count)
        })
        let awaiting = try #require(review.stages.first)
        #expect(awaiting.awaitingApproval)
        #expect(awaiting.approval == nil)

        // 3. The reviewer decides; the decision lands in the ledger.
        _ = try service.decide(
            runID: "run-review",
            stageID: "001-drc",
            verdict: .approved,
            reviewer: "reviewer-1",
            note: "verified against the report",
            projectRoot: root
        )
        review = try service.loadRun(runID: "run-review", projectRoot: root)
        #expect(review.bundle.reviewItems.contains {
            $0.kind == .approvalGate
                && $0.status == .readyToResume
                && $0.nextActionID == "001-drc-resume-run"
                && $0.artifactPaths.contains(".xcircuite/runs/run-review/approvals/001-drc.json")
        })
        let approvalActions = try XcircuitePackageStore().loadRunActions(
            runID: "run-review",
            inProjectAt: root
        )
        let approvalAction = try #require(approvalActions.first {
            $0.actionKind == XcircuiteRunReviewDecisionActionKind.approval.rawValue
        })
        #expect(approvalAction.actor.kind == .human)
        #expect(approvalAction.actor.identifier == "reviewer-1")
        #expect(approvalAction.metadata["source"] == .string("circuit-studio.run-review"))
        #expect(approvalAction.metadata["decision"] == .string("approved"))
        #expect(approvalAction.outputs.map(\.path) == [".xcircuite/runs/run-review/approvals/001-drc.json"])

        // 4. Re-running the same runID resumes past the gate; the
        //    cockpit shows the full picture.
        let resumed = try await DefaultFlowOrchestrator().run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(resumed.status == .succeeded)

        review = try service.loadRun(runID: "run-review", projectRoot: root)
        #expect(review.stages.count == 2)
        let decided = try #require(review.stages.first { $0.result.stageID == "001-drc" })
        #expect(!decided.awaitingApproval)
        #expect(decided.approval?.verdict == .approved)
        #expect(decided.approval?.reviewer == "reviewer-1")
        #expect(decided.result.gates.contains { $0.gateID == "approval" && $0.status == .passed })
    }

    @Test func reviewFailureStatesProjectMissingIntegrityBlockedAndStaleEvidence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-failure-states-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { removeTemporaryRoot(root) }

        let runID = "run-failure-states"
        let stageID = "001-drc"
        let rawPrefix = ".xcircuite/runs/\(runID)/stages/\(stageID)/raw"
        let missingPath = "\(rawPrefix)/missing-report.json"
        let mismatchPath = "\(rawPrefix)/mismatch-report.json"
        let stalePath = "\(rawPrefix)/stale-report.json"
        let staleURL = root.appending(path: stalePath)
        try FileManager.default.createDirectory(
            at: staleURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"state":"unhashed"}"#.utf8).write(to: staleURL, options: .atomic)

        let mismatchPayload = Data(#"{"state":"original"}"#.utf8)
        _ = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: runID,
                intent: "Review failure states",
                stages: [
                    FlowStageDefinition(stageID: stageID, displayName: "DRC", requiresApproval: true),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                PassingExecutor(
                    stageID: stageID,
                    artifacts: [
                        XcircuiteFileReference(
                            artifactID: "missing-report",
                            path: missingPath,
                            kind: .report,
                            format: .json
                        ),
                        XcircuiteFileReference(
                            artifactID: "mismatch-report",
                            path: mismatchPath,
                            kind: .report,
                            format: .json
                        ),
                        XcircuiteFileReference(
                            artifactID: "stale-report",
                            path: stalePath,
                            kind: .report,
                            format: .json
                        ),
                    ],
                    artifactPayloads: [
                        mismatchPath: mismatchPayload,
                    ]
                ),
            ]
        )

        let mismatchURL = root.appending(path: mismatchPath)
        try Data(#"{"state":"changed-after-ledger"}"#.utf8).write(to: mismatchURL, options: .atomic)

        let service = RunReviewService()
        let review = try service.loadRun(runID: runID, projectRoot: root)
        let failureStates = review.failureStates

        #expect(failureStates.count(of: .missingArtifact) >= 1)
        #expect(failureStates.count(of: .integrityMismatch) >= 1)
        #expect(failureStates.count(of: .staleEvidence) >= 1)
        #expect(failureStates.count(of: .blockedGate) >= 1)
        #expect(service.failureStateSummary(from: review) == failureStates)

        let missing = try #require(failureStates.states(of: .missingArtifact).first {
            $0.artifactRefs.contains { $0.path == missingPath && $0.integrityStatus == "missingArtifact" }
        })
        #expect(missing.suggestedActions.contains("restore-or-regenerate-artifact"))

        let mismatch = try #require(failureStates.states(of: .integrityMismatch).first {
            $0.artifactRefs.contains {
                $0.path == mismatchPath
                    && ($0.integrityStatus == "sha256Mismatch" || $0.integrityStatus == "byteCountMismatch")
            }
        })
        #expect(mismatch.suggestedActions.contains("rerun-artifact-integrity-gate"))

        let stale = try #require(failureStates.states(of: .staleEvidence).first {
            $0.artifactRefs.contains {
                $0.path == stalePath
                    && ($0.integrityStatus == "missingDigest" || $0.integrityStatus == "missingByteCount")
            }
        })
        #expect(stale.suggestedActions.contains("record-digest-and-byte-count"))

        let blockedGate = try #require(failureStates.states(of: .blockedGate).first {
            $0.stageID == stageID && $0.gateID == "approval"
        })
        #expect(blockedGate.nextActionID == "\(stageID)-decide-approval")
        #expect(blockedGate.suggestedActions.contains("record-approval-decision"))

        let unsupportedBundle = FlowRunReviewBundle(
            runID: "unsupported-action",
            status: .blocked,
            runDirectoryPath: ".xcircuite/runs/unsupported-action",
            summary: FlowRunLedgerSummary(
                runID: "unsupported-action",
                status: .blocked,
                runDirectoryPath: ".xcircuite/runs/unsupported-action",
                nextActions: [
                    FlowRunNextAction(
                        actionID: "unsupported-repair",
                        kind: "repair",
                        severity: .warning,
                        reason: "An unsupported repair command was proposed.",
                        suggestedCommands: [
                            FlowRunSuggestedCommand(
                                commandID: "unsupported-command",
                                readiness: .requiresInput,
                                executable: "unsupported-tool",
                                arguments: [],
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
        #expect(unsupported.suggestedActions == ["unsupported-command"])
    }

    @Test func waiverEditVerificationContextReportsMissingInputs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-context-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { removeTemporaryRoot(root) }

        let runID = "run-missing-context"
        let stageID = "001-review"
        let designSpecPath = ".xcircuite/runs/\(runID)/stages/\(stageID)/raw/design-spec.json"
        let layoutDocumentPath = ".xcircuite/runs/\(runID)/stages/\(stageID)/raw/layout-document.json"
        let service = RunReviewService()

        _ = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: runID,
                intent: "Missing review context",
                stages: [
                    FlowStageDefinition(stageID: stageID, displayName: "Review"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                PassingExecutor(
                    stageID: stageID,
                    artifacts: [
                        XcircuiteFileReference(
                            artifactID: "design-spec",
                            path: designSpecPath,
                            kind: .other,
                            format: .json
                        ),
                    ],
                    artifactPayloads: [
                        designSpecPath: try encodedJSONData(reviewVerificationDesignSpec()),
                    ]
                ),
            ]
        )

        let missingLayoutReview = try service.loadRun(runID: runID, projectRoot: root)
        #expect(throws: RunReviewServiceError.waiverEditVerificationLayoutDocumentNotFound(runID: runID)) {
            try service.waiverEditVerificationContext(
                review: missingLayoutReview,
                projectRoot: root
            )
        }

        _ = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: runID,
                intent: "Missing review context",
                stages: [
                    FlowStageDefinition(stageID: stageID, displayName: "Review"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                PassingExecutor(
                    stageID: stageID,
                    artifacts: [
                        XcircuiteFileReference(
                            artifactID: "design-spec",
                            path: designSpecPath,
                            kind: .other,
                            format: .json
                        ),
                        XcircuiteFileReference(
                            artifactID: "layout-document",
                            path: layoutDocumentPath,
                            kind: .layout,
                            format: .json
                        ),
                    ],
                    artifactPayloads: [
                        designSpecPath: try encodedJSONData(reviewVerificationDesignSpec()),
                    ]
                ),
            ]
        )

        let missingFileReview = try service.loadRun(runID: runID, projectRoot: root)
        #expect(throws: RunReviewServiceError.waiverEditVerificationInputMissing(path: layoutDocumentPath)) {
            try service.waiverEditVerificationContext(
                review: missingFileReview,
                projectRoot: root
            )
        }
    }

    @Test func rejectionIsVisibleInTheReview() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-reject-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { removeTemporaryRoot(root) }

        let request = FlowOperationRequest(
            projectRoot: root,
            runID: "run-reject",
            intent: "Review loop",
            stages: [
                FlowStageDefinition(stageID: "001-drc", displayName: "DRC", requiresApproval: true),
            ]
        )
        let executors: [any FlowStageExecutor] = [PassingExecutor(stageID: "001-drc")]

        _ = try await DefaultFlowOrchestrator().run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        let service = RunReviewService()
        _ = try service.decide(
            runID: "run-reject",
            stageID: "001-drc",
            verdict: .rejected,
            reviewer: "reviewer-1",
            note: "rail too narrow",
            projectRoot: root
        )
        let rerun = try await DefaultFlowOrchestrator().run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(rerun.status == .failed)

        let review = try service.loadRun(runID: "run-reject", projectRoot: root)
        let stage = try #require(review.stages.first)
        #expect(stage.approval?.verdict == .rejected)
        #expect(stage.result.gates.contains { $0.gateID == "approval" && $0.status == .failed })
        #expect(review.bundle.reviewItems.contains {
            $0.kind == .stageFailure
                && $0.status == .needsRepair
                && $0.stageID == "001-drc"
        })
    }

    @Test func planningCorrectnessItemsAreVisibleInTheReview() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-planning-correctness-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { removeTemporaryRoot(root) }

        _ = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-planning",
                intent: "Review planning correctness",
                stages: [
                    FlowStageDefinition(stageID: "001-planning", displayName: "Planning"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                PassingExecutor(stageID: "001-planning"),
            ]
        )

        let store = XcircuitePackageStore()
        let encoder = JSONEncoder()
        let candidatePlanPath = ".xcircuite/runs/run-planning/planning/candidate-plan.json"
        let candidatePlan = XcircuiteCandidatePlan(
            planID: "plan-1",
            problemID: "problem-1",
            runID: "run-planning",
            strategy: "approval-required-policy-repair",
            executionReadiness: "approval-required",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "problem-ref",
                kind: "planning-problem",
                path: ".xcircuite/runs/run-planning/planning/problem.json",
                artifactID: "planning-problem"
            ),
            riskClassifications: [
                XcircuitePlanningRiskClassification(
                    riskID: "risk-policy-repair",
                    category: "lvs-policy",
                    severity: "high",
                    scope: "plan",
                    description: "Policy repair changes LVS equivalence and needs review.",
                    affectedActionIDs: ["action-1"],
                    requiredApprovals: ["policy-repair-approval"],
                    mitigationActions: ["approval-gate", "native-lvs"]
                ),
            ],
            steps: [
                XcircuiteCandidatePlanStep(
                    stepID: "step-1",
                    order: 1,
                    actionID: "action-1",
                    domainID: "lvs-signoff",
                    operationID: "lvs.policy-repair",
                    maturity: "usable",
                    readiness: "approval-required",
                    sourceObjectiveIDs: ["objective-1"],
                    requiredInputRefs: ["layout-netlist-ref", "schematic-netlist-ref"],
                    missingInputRefs: [],
                    verificationGates: ["approval-gate", "native-lvs"],
                    reason: "Allow a reviewed model-equivalence policy before native LVS.",
                    parameterHints: [:],
                    blockers: []
                ),
            ],
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "approval-gate",
                    required: true,
                    description: "Policy repair requires human approval."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "native-lvs",
                    required: true,
                    description: "Native LVS must pass after policy repair."
                ),
            ],
            constraints: [
                XcircuitePlanningConstraint(
                    constraintID: "policy-repair-approval",
                    kind: "human-approval",
                    severity: "high",
                    description: "Human review is required before policy repair execution."
                ),
            ],
            unresolvedObjectives: [],
            blockers: ["approval-required"]
        )
        let candidatePlanPayload = try encoder.encode(candidatePlan)
        try FileManager.default.createDirectory(
            at: root.appending(path: candidatePlanPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try candidatePlanPayload.write(to: root.appending(path: candidatePlanPath), options: .atomic)
        let candidatePlanReference = try store.fileReference(
            forProjectRelativePath: candidatePlanPath,
            artifactID: "planning-candidate-plan",
            kind: .other,
            format: .json,
            inProjectAt: root,
            producedByRunID: "run-planning"
        )
        try store.upsertRunArtifact(candidatePlanReference, runID: "run-planning", inProjectAt: root)

        let planVerificationPath = ".xcircuite/runs/run-planning/planning/plan-verification.json"
        let planVerification = XcircuitePlanVerification(
            problemID: "problem-1",
            planID: "plan-1",
            runID: "run-planning",
            verificationMode: "preflight",
            candidatePlanRef: candidatePlanReference,
            stepResults: [
                XcircuitePlanVerificationStepResult(
                    stepID: "step-1",
                    order: 1,
                    actionID: "action-1",
                    domainID: "lvs-signoff",
                    operationID: "lvs.policy-repair",
                    status: "blocked",
                    gateIDs: ["approval-gate", "native-lvs"],
                    diagnostics: [
                        XcircuitePlanVerificationDiagnostic(
                            severity: "warning",
                            code: "risk-approval-required",
                            message: "Policy repair requires human approval before execution.",
                            stepID: "step-1",
                            gateID: "approval-gate"
                        ),
                    ]
                ),
            ],
            gateResults: [
                XcircuitePlanVerificationGateResult(
                    gateID: "approval-gate",
                    required: true,
                    status: "pending",
                    sourceStepIDs: ["step-1"]
                ),
                XcircuitePlanVerificationGateResult(
                    gateID: "native-lvs",
                    required: true,
                    status: "pending",
                    sourceStepIDs: ["step-1"]
                ),
            ],
            correctnessGateResults: [
                XcircuitePlanningCorrectnessGateResult(
                    gateID: "action-domain-binding",
                    status: "passed",
                    summary: "Candidate steps bind to declared operations."
                ),
                XcircuitePlanningCorrectnessGateResult(
                    gateID: "post-execution-signoff",
                    status: "pending",
                    summary: "Post-execution signoff still needs review.",
                    diagnostics: [
                        XcircuitePlanVerificationDiagnostic(
                            severity: "warning",
                            code: "post-execution-verification-required",
                            message: "Post-execution signoff still needs review."
                        ),
                    ],
                    nextActions: ["verify-candidate-plan:post-execution"]
                ),
            ],
            riskReviews: [
                XcircuitePlanRiskReview(
                    riskID: "risk-policy-repair",
                    category: "lvs-policy",
                    severity: "high",
                    scope: "plan",
                    status: "approval-required",
                    description: "Policy repair changes LVS equivalence and needs review.",
                    affectedActionIDs: ["action-1"],
                    affectedStepIDs: ["step-1"],
                    requiredApprovals: ["policy-repair-approval"],
                    approvalReviews: [
                        XcircuitePlanApprovalReview(
                            approvalID: "policy-repair-approval",
                            status: "missing"
                        ),
                    ],
                    mitigationActions: ["approval-gate", "native-lvs"]
                ),
            ],
            artifactRefs: [candidatePlanReference],
            diagnostics: [],
            accepted: false,
            nextActions: [
                "request-human-approval:policy-repair-approval",
                "verify-candidate-plan:post-execution",
            ]
        )
        let payload = try encoder.encode(planVerification)
        try FileManager.default.createDirectory(
            at: root.appending(path: planVerificationPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.write(to: root.appending(path: planVerificationPath), options: .atomic)
        let reference = try store.fileReference(
            forProjectRelativePath: planVerificationPath,
            artifactID: "planning-plan-verification",
            kind: .other,
            format: .json,
            inProjectAt: root,
            producedByRunID: "run-planning"
        )
        try store.upsertRunArtifact(reference, runID: "run-planning", inProjectAt: root)
        try store.writeDesignDiff(
            XcircuiteDesignDiff(
                runID: "run-planning",
                title: "Planning edit proposal",
                actor: "agent-1",
                changes: [
                    XcircuiteDesignDiffChange(
                        changeID: "change-1",
                        domain: .layout,
                        operation: .replace,
                        path: "/cells/INV/layout/shapes/met1/rail",
                        before: .object([
                            "geometry": .object([
                                "kind": .string("rect"),
                                "rect": .object([
                                    "origin": .object([
                                        "x": .number(0),
                                        "y": .number(0),
                                    ]),
                                    "size": .object([
                                        "height": .number(3),
                                        "width": .number(1),
                                    ]),
                                ]),
                            ]),
                            "layer": .string("M1"),
                            "width": .number(0.14),
                        ]),
                        after: .object([
                            "geometry": .object([
                                "kind": .string("rect"),
                                "rect": .object([
                                    "origin": .object([
                                        "x": .number(0),
                                        "y": .number(0),
                                    ]),
                                    "size": .object([
                                        "height": .number(3),
                                        "width": .number(2),
                                    ]),
                                ]),
                            ]),
                            "net": .string("VDD"),
                            "width": .number(0.20),
                        ]),
                        artifacts: [candidatePlanReference],
                        summary: "Widen the rail before post-execution signoff."
                    ),
                    XcircuiteDesignDiffChange(
                        changeID: "change-2",
                        domain: .layout,
                        operation: .replace,
                        path: "/cells/INV/layout/shapes/met2/strap",
                        before: .object([
                            "geometry": .object([
                                "kind": .string("rect"),
                                "rect": .object([
                                    "origin": .object([
                                        "x": .number(3),
                                        "y": .number(1),
                                    ]),
                                    "size": .object([
                                        "height": .number(1),
                                        "width": .number(1),
                                    ]),
                                ]),
                            ]),
                            "layer": .string("M2"),
                        ]),
                        after: .object([
                            "geometry": .object([
                                "kind": .string("rect"),
                                "rect": .object([
                                    "origin": .object([
                                        "x": .number(3),
                                        "y": .number(1),
                                    ]),
                                    "size": .object([
                                        "height": .number(2),
                                        "width": .number(1),
                                    ]),
                                ]),
                            ]),
                            "net": .string("VSS"),
                        ]),
                        artifacts: [candidatePlanReference],
                        summary: "Stretch the upper strap in the same native layout canvas."
                    ),
                    XcircuiteDesignDiffChange(
                        changeID: "change-3",
                        domain: .schematic,
                        operation: .replace,
                        path: "/cells/INV/schematic/instances/M1/parameters/w",
                        before: .number(1.0),
                        after: .number(1.2),
                        summary: "Retune M1 width for the same candidate plan."
                    ),
                ]
            ),
            inProjectAt: root
        )

        let service = RunReviewService()
        let review = try service.loadRun(runID: "run-planning", projectRoot: root)
        #expect(review.planning.hasContent)
        #expect(review.planning.candidatePlanArtifact?.artifactID == "planning-candidate-plan")
        #expect(review.planning.candidatePlanArtifact?.path == candidatePlanPath)
        #expect(review.planning.planVerificationArtifact?.artifactID == "planning-plan-verification")
        #expect(review.planning.planVerificationArtifact?.path == planVerificationPath)
        #expect(review.planning.decodeIssues.isEmpty)
        #expect(review.planning.candidatePlan?.steps.first?.operationID == "lvs.policy-repair")
        #expect(review.planning.candidatePlan?.riskClassifications.first?.requiredApprovals == [
            "policy-repair-approval",
        ])
        #expect(review.planning.planVerification?.gateResults.map(\.gateID) == ["approval-gate", "native-lvs"])
        #expect(review.planning.planVerification?.riskReviews.first?.status == "approval-required")
        #expect(review.planning.planVerification?.riskReviews.first?.approvalReviews.first?.status == "missing")
        #expect(review.planning.designDiff?.title == "Planning edit proposal")
        #expect(review.planning.designDiff?.changes.first?.summary == "Widen the rail before post-execution signoff.")
        let designDiffSummary = try #require(review.planning.designDiffSummary)
        #expect(designDiffSummary.title == "Planning edit proposal")
        #expect(designDiffSummary.actor == "agent-1")
        #expect(designDiffSummary.reviewState == "proposed")
        #expect(designDiffSummary.changeCount == 3)
        #expect(designDiffSummary.domains == [
            RunReviewDesignDiffBucket(label: "layout", count: 2),
            RunReviewDesignDiffBucket(label: "schematic", count: 1),
        ])
        #expect(designDiffSummary.operations == [
            RunReviewDesignDiffBucket(label: "replace", count: 3),
        ])
        #expect(designDiffSummary.canvases == [
            RunReviewDesignDiffCanvasSummary(
                canvasID: "layout:INV",
                scope: "layout",
                cellID: "INV",
                title: "layout INV",
                nodeCount: 2,
                changedFieldCount: 7,
                viewport: RunReviewDesignDiffCanvasViewportSummary(
                    bounds: RunReviewDesignDiffFrameSummary(
                        x: 0,
                        y: 0,
                        width: 4,
                        height: 3
                    ),
                    beforeBounds: RunReviewDesignDiffFrameSummary(
                        x: 0,
                        y: 0,
                        width: 4,
                        height: 3
                    ),
                    afterBounds: RunReviewDesignDiffFrameSummary(
                        x: 0,
                        y: 0,
                        width: 4,
                        height: 3
                    ),
                    geometryNodeCount: 2,
                    sources: ["geometry.rect"],
                    layerIDs: ["met1", "met2"]
                ),
                rendering: RunReviewDesignDiffCanvasRenderingSummary(
                    coordinateSpace: "layout-native",
                    aspectRatio: 4.0 / 3.0,
                    beforePrimitiveCount: 2,
                    afterPrimitiveCount: 2,
                    overlayPrimitiveCount: 2,
                    layers: [
                        RunReviewDesignDiffCanvasLayerSummary(
                            layerID: "met1",
                            nodeCount: 1,
                            changedFieldCount: 4,
                            beforePrimitiveCount: 1,
                            afterPrimitiveCount: 1,
                            emphasisBuckets: [
                                RunReviewDesignDiffBucket(label: "modified", count: 1),
                            ]
                        ),
                        RunReviewDesignDiffCanvasLayerSummary(
                            layerID: "met2",
                            nodeCount: 1,
                            changedFieldCount: 3,
                            beforePrimitiveCount: 1,
                            afterPrimitiveCount: 1,
                            emphasisBuckets: [
                                RunReviewDesignDiffBucket(label: "modified", count: 1),
                            ]
                        ),
                    ],
                    primitives: [
                        RunReviewDesignDiffCanvasPrimitiveSummary(
                            primitiveID: "layout:INV:shapes:met1:rail",
                            nodeID: "layout:INV:shapes:met1:rail",
                            label: "rail",
                            layerID: "met1",
                            emphasis: "modified",
                            changedFieldCount: 4,
                            beforeFrame: RunReviewDesignDiffFrameSummary(
                                x: 0,
                                y: 0,
                                width: 1,
                                height: 3
                            ),
                            afterFrame: RunReviewDesignDiffFrameSummary(
                                x: 0,
                                y: 0,
                                width: 2,
                                height: 3
                            ),
                            selectionFrame: RunReviewDesignDiffFrameSummary(
                                x: 0,
                                y: 0,
                                width: 2,
                                height: 3
                            )
                        ),
                        RunReviewDesignDiffCanvasPrimitiveSummary(
                            primitiveID: "layout:INV:shapes:met2:strap",
                            nodeID: "layout:INV:shapes:met2:strap",
                            label: "strap",
                            layerID: "met2",
                            emphasis: "modified",
                            changedFieldCount: 3,
                            beforeFrame: RunReviewDesignDiffFrameSummary(
                                x: 3,
                                y: 1,
                                width: 1,
                                height: 1
                            ),
                            afterFrame: RunReviewDesignDiffFrameSummary(
                                x: 3,
                                y: 1,
                                width: 1,
                                height: 2
                            ),
                            selectionFrame: RunReviewDesignDiffFrameSummary(
                                x: 3,
                                y: 1,
                                width: 1,
                                height: 2
                            )
                        ),
                    ]
                ),
                nodes: [
                    RunReviewDesignDiffCanvasNodeSummary(
                        nodeID: "layout:INV:shapes:met1:rail",
                        kind: "layout-shape",
                        title: "rail",
                        subtitle: "INV / met1 / shapes",
                        emphasis: "modified",
                        layerID: "met1",
                        entityID: "rail",
                        changedFields: ["/geometry/rect/size/width", "/layer", "/net", "/width"],
                        geometry: RunReviewDesignDiffCanvasGeometrySummary(
                            source: "geometry.rect",
                            beforeFrame: RunReviewDesignDiffFrameSummary(
                                x: 0,
                                y: 0,
                                width: 1,
                                height: 3
                            ),
                            afterFrame: RunReviewDesignDiffFrameSummary(
                                x: 0,
                                y: 0,
                                width: 2,
                                height: 3
                            ),
                            delta: RunReviewDesignDiffFrameDeltaSummary(
                                dx: 0,
                                dy: 0,
                                dWidth: 1,
                                dHeight: 0
                            )
                        )
                    ),
                    RunReviewDesignDiffCanvasNodeSummary(
                        nodeID: "layout:INV:shapes:met2:strap",
                        kind: "layout-shape",
                        title: "strap",
                        subtitle: "INV / met2 / shapes",
                        emphasis: "modified",
                        layerID: "met2",
                        entityID: "strap",
                        changedFields: ["/geometry/rect/size/height", "/layer", "/net"],
                        geometry: RunReviewDesignDiffCanvasGeometrySummary(
                            source: "geometry.rect",
                            beforeFrame: RunReviewDesignDiffFrameSummary(
                                x: 3,
                                y: 1,
                                width: 1,
                                height: 1
                            ),
                            afterFrame: RunReviewDesignDiffFrameSummary(
                                x: 3,
                                y: 1,
                                width: 1,
                                height: 2
                            ),
                            delta: RunReviewDesignDiffFrameDeltaSummary(
                                dx: 0,
                                dy: 0,
                                dWidth: 0,
                                dHeight: 1
                            )
                        )
                    ),
                ]
            ),
            RunReviewDesignDiffCanvasSummary(
                canvasID: "schematic:INV",
                scope: "schematic",
                cellID: "INV",
                title: "schematic INV",
                nodeCount: 1,
                changedFieldCount: 1,
                nodes: [
                    RunReviewDesignDiffCanvasNodeSummary(
                        nodeID: "schematic:INV:instances:M1",
                        kind: "schematic-instance",
                        title: "M1",
                        subtitle: "INV / instances / parameters/w",
                        emphasis: "modified",
                        entityID: "M1",
                        changedFields: ["parameters/w"]
                    ),
                ]
            ),
        ])
        let designDiffChange = try #require(designDiffSummary.changes.first)
        #expect(designDiffChange.path == "/cells/INV/layout/shapes/met1/rail")
        #expect(designDiffChange.pathContext == RunReviewDesignDiffPathContext(
            scope: "layout",
            displayName: "layout shapes rail",
            cellID: "INV",
            collection: "shapes",
            layerID: "met1",
            entityID: "rail"
        ))
        #expect(designDiffChange.visualFocus == RunReviewDesignDiffVisualFocus(
            kind: "layout-shape",
            title: "rail",
            subtitle: "INV / met1 / shapes",
            emphasis: "modified",
            changedFields: ["/geometry/rect/size/width", "/layer", "/net", "/width"]
        ))
        #expect(designDiffChange.beforePreview == "{geometry: {kind, rect}, layer: \"M1\", width: 0.14}")
        #expect(designDiffChange.afterPreview == "{geometry: {kind, rect}, net: \"VDD\", width: 0.2}")
        #expect(designDiffChange.valueChanges == [
            RunReviewDesignDiffValueChangeSummary(
                path: "/geometry/rect/size/width",
                state: "modified",
                beforePreview: "1.0",
                afterPreview: "2.0"
            ),
            RunReviewDesignDiffValueChangeSummary(
                path: "/layer",
                state: "removed",
                beforePreview: "\"M1\""
            ),
            RunReviewDesignDiffValueChangeSummary(
                path: "/net",
                state: "added",
                afterPreview: "\"VDD\""
            ),
            RunReviewDesignDiffValueChangeSummary(
                path: "/width",
                state: "modified",
                beforePreview: "0.14",
                afterPreview: "0.2"
            ),
        ])
        #expect(designDiffChange.geometry == RunReviewDesignDiffCanvasGeometrySummary(
            source: "geometry.rect",
            beforeFrame: RunReviewDesignDiffFrameSummary(
                x: 0,
                y: 0,
                width: 1,
                height: 3
            ),
            afterFrame: RunReviewDesignDiffFrameSummary(
                x: 0,
                y: 0,
                width: 2,
                height: 3
            ),
            delta: RunReviewDesignDiffFrameDeltaSummary(
                dx: 0,
                dy: 0,
                dWidth: 1,
                dHeight: 0
            )
        ))
        #expect(designDiffChange.artifactCount == 1)
        #expect(designDiffChange.artifacts.first?.path == candidatePlanPath)
        let schematicDiffChange = try #require(designDiffSummary.changes.last)
        #expect(schematicDiffChange.pathContext == RunReviewDesignDiffPathContext(
            scope: "schematic",
            displayName: "schematic instances M1",
            cellID: "INV",
            collection: "instances",
            entityID: "M1",
            propertyPath: "parameters/w"
        ))
        #expect(schematicDiffChange.visualFocus == RunReviewDesignDiffVisualFocus(
            kind: "schematic-instance",
            title: "M1",
            subtitle: "INV / instances / parameters/w",
            emphasis: "modified",
            changedFields: ["parameters/w"]
        ))
        #expect(schematicDiffChange.valueChanges == [
            RunReviewDesignDiffValueChangeSummary(
                path: "/",
                state: "modified",
                beforePreview: "1.0",
                afterPreview: "1.2"
            ),
        ])
        let planningDrilldown = service.interactiveSignoffDrilldown(from: review)
        let diffSection = try #require(planningDrilldown.section(for: .designDiff))
        #expect(diffSection.items.count == 4)
        let diffSummaryItem = try #require(diffSection.items.first { $0.itemID == "design-diff:summary" })
        #expect(diffSummaryItem.interactions.contains(.designDiffCanvas))
        #expect(diffSummaryItem.metrics.contains {
            $0.label == "Changes" && $0.value == "3"
        })
        let railDiffItem = try #require(diffSection.items.first {
            $0.itemID == "design-diff:change:change-1"
        })
        #expect(railDiffItem.artifactRefs.contains {
            $0.source == "design-diff" && $0.path == candidatePlanPath
        })
        #expect(railDiffItem.detailGroups.contains { $0.title == "Path Context" })
        #expect(railDiffItem.detailGroups.contains { $0.title == "Visual Focus" })
        #expect(railDiffItem.detailGroups.contains { $0.title == "Value Changes" })
        #expect(planningDrilldown.artifactIndex.contains {
            $0.source == "design-diff" && $0.path == candidatePlanPath
        })
        #expect(planningDrilldown.failures.isEmpty)
        let item = try #require(review.bundle.reviewItems.first {
            $0.kind == .planningCorrectness
                && $0.itemID == "planning-correctness-post-execution-signoff"
        })
        #expect(review.planning.correctnessItems.contains { $0.itemID == item.itemID })
        #expect(item.status == .needsReview)
        #expect(item.diagnosticCodes == ["post-execution-verification-required"])
        #expect(item.artifactPaths == [planVerificationPath])
        #expect(item.nextActionID == "verify-candidate-plan:post-execution")
        let action = try #require(review.bundle.summary.nextActions.first {
            $0.kind == "verifyPlanningCorrectness"
                && $0.actionID == "verify-candidate-plan:post-execution"
        })
        let command = try #require(action.suggestedCommands.first)
        #expect(command.readiness == .ready)
        #expect(command.executable == "xcircuite-flow")
        #expect(command.arguments == [
            "verify-candidate-plan",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-planning",
            "--mode",
            "post-execution",
            "--pretty",
        ])

        let record = try service.recordSuggestedCommandSelection(
            runID: "run-planning",
            nextActionID: action.actionID,
            commandID: command.commandID,
            reviewer: "reviewer-1",
            projectRoot: root
        )
        #expect(record.actionKind == "review.selectSuggestedCommand")
        #expect(record.actor.kind == .human)
        #expect(record.metadata["nextActionID"] == .string("verify-candidate-plan:post-execution"))
        #expect(record.metadata["commandID"] == .string("xcircuite-flow.verify-candidate-plan.post-execution"))
        #expect(record.metadata["readiness"] == .string("ready"))
        #expect(record.metadata["executable"] == .string("xcircuite-flow"))
        #expect(record.metadata["arguments"] == .array(command.arguments.map { .string($0) }))

        let actions = try XcircuitePackageStore().loadRunActions(
            runID: "run-planning",
            inProjectAt: root
        )
        #expect(actions.contains {
            $0.actionKind == "review.selectSuggestedCommand"
                && $0.metadata["commandID"] == .string(command.commandID)
        })
        let selections = try service.loadSuggestedCommandSelections(
            runID: "run-planning",
            projectRoot: root
        )
        let selection = try #require(selections.first)
        #expect(selections.count == 1)
        #expect(selection.actionRecordID == record.actionID)
        #expect(selection.actor.identifier == "reviewer-1")
        #expect(selection.nextActionID == action.actionID)
        #expect(selection.commandID == command.commandID)
        #expect(selection.executable == "xcircuite-flow")
        #expect(selection.arguments == command.arguments)

        let reloadedReview = try service.loadRun(runID: "run-planning", projectRoot: root)
        #expect(reloadedReview.suggestedCommandSelections == selections)
        #expect(reloadedReview.planning.selectedCommands == selections)

        let approvalResult = try service.decidePlanningRiskApproval(
            runID: "run-planning",
            approvalID: "policy-repair-approval",
            verdict: .approved,
            reviewer: "reviewer-1",
            note: "Policy repair reviewed in the cockpit.",
            projectRoot: root
        )
        #expect(approvalResult.status == "approved")
        #expect(approvalResult.approvalPath == ".xcircuite/runs/run-planning/approvals/policy-repair-approval.json")
        #expect(approvalResult.approval.reviewer == "reviewer-1")

        let approvalRecord = try #require(
            try XcircuitePackageStore().loadApproval(
                runID: "run-planning",
                stageID: "policy-repair-approval",
                inProjectAt: root
            )
        )
        #expect(approvalRecord.verdict == .approved)
        #expect(approvalRecord.note == "Policy repair reviewed in the cockpit.")

        let approvalActions = try XcircuitePackageStore().loadRunActions(
            runID: "run-planning",
            inProjectAt: root
        )
        let approvalAction = try #require(approvalActions.last {
            $0.actionKind == "planning.approve-candidate-plan-risk"
        })
        #expect(approvalAction.actor.kind == .human)
        #expect(approvalAction.actor.identifier == "reviewer-1")
        #expect(approvalAction.status == .succeeded)

        let approvedReview = try service.loadRun(runID: "run-planning", projectRoot: root)
        #expect(approvedReview.planning.planVerification?.riskReviews.first?.status == "approved")
        #expect(approvedReview.planning.planVerification?.riskReviews.first?.approvalReviews.first?.status == "approved")
        #expect(approvedReview.planning.planVerification?.riskReviews.first?.approvalReviews.first?.reviewer == "reviewer-1")
    }

    @Test @MainActor func signoffArtifactsAreVisibleInTheReview() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-signoff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { removeTemporaryRoot(root) }

        let runID = "run-signoff"
        let stageID = "001-signoff"
        let rawPrefix = ".xcircuite/runs/\(runID)/stages/\(stageID)/raw"
        let stageResultPath = ".xcircuite/runs/\(runID)/stages/\(stageID)/result.json"
        let drcPath = "\(rawPrefix)/drc-summary.json"
        let drcLogPath = "\(rawPrefix)/drc-native.log"
        let drcRepairHintPath = "\(rawPrefix)/drc-repair-hints.json"
        let drcEnvelopePath = ".xcircuite/runs/\(runID)/evidence/drc-summary-envelope.json"
        let lvsPath = "\(rawPrefix)/lvs-summary.json"
        let lvsLogPath = "\(rawPrefix)/lvs-native.log"
        let lvsRepairHintPath = "\(rawPrefix)/lvs-repair-hints.json"
        let pexPath = "\(rawPrefix)/pex-summary.json"
        let simulationSummaryPath = "\(rawPrefix)/simulation-summary.json"
        let preLayoutWaveformPath = "\(rawPrefix)/pre-layout-waveform.csv"
        let postLayoutWaveformPath = "\(rawPrefix)/post-layout-waveform.csv"
        let symlinkEscapePath = "\(rawPrefix)/symlink-escape.log"
        let measurementsPath = "\(rawPrefix)/measurements.json"
        let comparisonPath = "\(rawPrefix)/comparison-report.json"
        let designSpecPath = "\(rawPrefix)/design-spec.json"
        let layoutDocumentPath = "\(rawPrefix)/layout-document.json"
        let designUnitPath = "\(rawPrefix)/design-unit.json"
        let waiverSourcePath = "signoff/waivers/drc-waivers.json"
        try FileManager.default.createDirectory(
            at: root.appending(path: waiverSourcePath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(
            """
            {
              "waivers": [
                {
                  "waiverID": "waive-m1-width-temporary",
                  "ruleID": "M1.WIDTH",
                  "reason": "temporary analog guard-ring exception"
                },
                {
                  "waiverID": "waive-obsolete-rule",
                  "ruleID": "M1.SPACING",
                  "reason": "obsolete waiver"
                }
              ]
            }
            """.utf8
        ).write(to: root.appending(path: waiverSourcePath), options: .atomic)

        let designSpec = reviewVerificationDesignSpec()
        let builtDesign = try designSpec.build()
        let layoutOutput = try DesignFlowService().generateLayout(DesignFlowLayoutGenerationRequest(
            schematic: builtDesign.schematic,
            catalog: .standard()
        ))

        let artifacts = [
            XcircuiteFileReference(artifactID: "drc-summary", path: drcPath, kind: .report, format: .json),
            XcircuiteFileReference(artifactID: "drc-raw-log", path: drcLogPath, kind: .report, format: .text),
            XcircuiteFileReference(artifactID: "drc-repair-hints", path: drcRepairHintPath, kind: .report, format: .json),
            XcircuiteFileReference(
                artifactID: "evidence-drc-summary-review",
                path: drcEnvelopePath,
                kind: .report,
                format: .json
            ),
            XcircuiteFileReference(artifactID: "lvs-summary", path: lvsPath, kind: .report, format: .json),
            XcircuiteFileReference(artifactID: "lvs-raw-log", path: lvsLogPath, kind: .report, format: .text),
            XcircuiteFileReference(artifactID: "lvs-repair-hints", path: lvsRepairHintPath, kind: .report, format: .json),
            XcircuiteFileReference(artifactID: "pex-summary", path: pexPath, kind: .report, format: .json),
            XcircuiteFileReference(
                artifactID: "planning-simulation-summary",
                path: simulationSummaryPath,
                kind: .report,
                format: .json
            ),
            XcircuiteFileReference(
                artifactID: "pre-layout-waveform",
                path: preLayoutWaveformPath,
                kind: .waveform,
                format: .csv
            ),
            XcircuiteFileReference(
                artifactID: "post-layout-waveform",
                path: postLayoutWaveformPath,
                kind: .waveform,
                format: .csv
            ),
            XcircuiteFileReference(
                artifactID: "symlink-escape",
                path: symlinkEscapePath,
                kind: .report,
                format: .text
            ),
            XcircuiteFileReference(path: measurementsPath, kind: .measurement, format: .json),
            XcircuiteFileReference(artifactID: "post-layout-comparison", path: comparisonPath, kind: .report, format: .json),
            XcircuiteFileReference(artifactID: "design-spec", path: designSpecPath, kind: .other, format: .json),
            XcircuiteFileReference(artifactID: "layout-document", path: layoutDocumentPath, kind: .layout, format: .json),
            XcircuiteFileReference(artifactID: "design-unit", path: designUnitPath, kind: .other, format: .json),
        ]
        let payloads = [
            drcPath: Data(
                """
                {
                  "schemaVersion": 1,
                  "reportURL": "\(root.appending(path: drcPath).absoluteString)",
                  "manifestURL": "\(root.appending(path: "\(rawPrefix)/drc-artifact-manifest.json").absoluteString)",
                  "summary": {
                    "status": "failed",
                    "toolName": "native-drc",
                    "topCell": "INVX1",
                    "passed": false,
                    "activeViolationCount": 2,
                    "waivedViolationCount": 1,
                    "unusedWaiverIDs": ["waive-obsolete-rule"],
                    "waiverSources": [
                      {
                        "waiverID": "waive-m1-width-temporary",
                        "path": "\(waiverSourcePath)",
                        "lineStart": 12,
                        "lineEnd": 18,
                        "ruleID": "M1.WIDTH",
                        "diagnosticID": "drc:M1.WIDTH:1",
                        "reason": "temporary analog guard-ring exception"
                      }
                    ],
                    "waiverEditProposals": [
                      {
                        "proposalID": "remove-obsolete-drc-waiver",
                        "waiverID": "waive-obsolete-rule",
                        "kind": "remove-unused-waiver",
                        "status": "proposed",
                        "targetPath": "\(waiverSourcePath)",
                        "operation": "remove-json-object",
                        "summary": "Remove the unused DRC waiver before signoff.",
                        "replacementText": null,
                        "risk": "low"
                      }
                    ],
                    "violationBuckets": [
                      {
                        "ruleID": "M1.WIDTH",
                        "kind": "width",
                        "layer": "met1",
                        "activeCount": 2,
                        "waivedCount": 1,
                        "maxMeasured": 0.12,
                        "required": 0.14,
                        "representativeRegion": {
                          "x": 10,
                          "y": 20,
                          "width": 0.12,
                          "height": 0.4
                        },
                        "relatedShapeIDs": ["m1-segment-a", "m1-segment-b"],
                        "relatedNetIDs": ["out"],
                        "suggestedFixes": ["widen-metal"]
                      }
                    ]
                  }
                }
                """.utf8
            ),
            drcEnvelopePath: try encodedJSONData(XcircuiteArtifactEnvelope(
                artifactID: "drc-summary",
                role: "drc-summary",
                stageID: stageID,
                reference: XcircuiteFileReference(
                    artifactID: "drc-summary",
                    path: drcPath,
                    kind: .report,
                    format: .json
                ),
                evaluationSpec: XcircuiteEvaluationSpec(
                    specID: "drc-summary-evaluation-spec",
                    objective: "Evaluate DRC artifact evidence for repair planning.",
                    criteria: [
                        XcircuiteEvaluationCriterion(
                            criterionID: "drc-active-violation-count",
                            channelID: "drc-active-violation-count",
                            comparator: .equal,
                            target: .number(0)
                        ),
                    ],
                    requiredArtifactRoles: ["drc-summary"]
                ),
                observationSet: XcircuiteObservationSet(
                    observationSetID: "drc-summary-observations",
                    specID: "drc-summary-evaluation-spec",
                    channels: [
                        XcircuiteObservationChannel(
                            channelID: "drc-active-violation-count",
                            label: "Active DRC violations",
                            status: .observed,
                            value: .number(2),
                            sourceArtifactIDs: ["drc-summary"],
                            confidence: XcircuiteEvidenceConfidence(value: 0.9, calibrated: true)
                        ),
                        XcircuiteObservationChannel(
                            channelID: "drc-magic-oracle-agreement",
                            status: .missing,
                            sourceArtifactIDs: ["drc-summary"],
                            confidence: XcircuiteEvidenceConfidence(value: 0, calibrated: false)
                        ),
                        XcircuiteObservationChannel(
                            channelID: "drc-qualified-calibration",
                            status: .uncalibrated,
                            value: .number(0.4),
                            sourceArtifactIDs: ["drc-summary"],
                            confidence: XcircuiteEvidenceConfidence(
                                value: 0.4,
                                posteriorVariance: 0.6,
                                calibrated: false
                            )
                        ),
                    ],
                    confidence: XcircuiteEvidenceConfidence(
                        value: 0.55,
                        posteriorVariance: 0.45,
                        calibrated: false
                    )
                ),
                evaluationResult: XcircuiteEvaluationResult(
                    evaluationID: "drc-summary-evaluation",
                    specID: "drc-summary-evaluation-spec",
                    status: .rejected,
                    likelihood: 0.2,
                    residual: 2,
                    confidence: XcircuiteEvidenceConfidence(
                        value: 0.55,
                        posteriorVariance: 0.45,
                        calibrated: false
                    ),
                    channelResults: [
                        XcircuiteEvaluationChannelResult(
                            criterionID: "drc-active-violation-count",
                            channelID: "drc-active-violation-count",
                            status: .rejected,
                            observedValue: .number(2),
                            residual: 2,
                            likelihood: 0.2,
                            confidence: XcircuiteEvidenceConfidence(value: 0.9, calibrated: true)
                        ),
                    ],
                    feedbackSignals: [
                        XcircuiteFeedbackSignal(
                            signalID: "drc-route-width-feedback",
                            sourceEvaluationID: "drc-summary-evaluation",
                            channelID: "drc-active-violation-count",
                            routingLevel: .localSurface,
                            severity: .error,
                            summary: "Active DRC violations should route to layout repair.",
                            residual: 2,
                            affectedArtifactIDs: ["drc-summary"],
                            affectedPaths: [drcPath],
                            suggestedActions: ["apply-drc-repair-hint"],
                            confidence: XcircuiteEvidenceConfidence(value: 0.55, calibrated: false)
                        ),
                    ],
                    summary: "DRC has active violations and incomplete oracle evidence."
                )
            )),
            drcLogPath: Data("DRC_SUMMARY total=2 cell=INVX1\nDRC_DONE\n".utf8),
            drcRepairHintPath: Data(
                """
                {
                  "schemaVersion": 1,
                  "status": "ready",
                  "reportURL": null,
                  "backendID": "native-drc",
                  "topCell": "INVX1",
                  "activeDiagnosticCount": 1,
                  "hintCount": 1,
                  "hints": [
                    {
                      "hintID": "drc-repair-0-M1-WIDTH",
                      "sourceDiagnosticIndex": 0,
                      "operationID": "layout.resize-shape",
                      "confidence": "high",
                      "ruleID": "M1.WIDTH",
                      "kind": "width",
                      "layer": "met1",
                      "targetShapeIDs": ["m1-segment-a"],
                      "relatedViaIDs": [],
                      "relatedNetIDs": ["out"],
                      "region": {
                        "x": 10,
                        "y": 20,
                        "width": 0.12,
                        "height": 0.4
                      },
                      "measured": 0.12,
                      "required": 0.14,
                      "numericParameters": {
                        "deltaMaxX": 0.02,
                        "deltaMaxY": 0
                      },
                      "stringParameters": {
                        "layer": "met1",
                        "shapeID": "m1-segment-a",
                        "unit": "um"
                      },
                      "verificationGates": ["artifact-integrity", "native-drc", "native-lvs"],
                      "rationale": "M1.WIDTH maps to layout.resize-shape because the diagnostic exposes a target shape."
                    }
                  ],
                  "unsupportedDiagnosticIndexes": []
                }
                """.utf8
            ),
            lvsPath: Data(
                """
                {
                  "schemaVersion": 1,
                  "reportURL": "\(root.appending(path: lvsPath).absoluteString)",
                  "manifestURL": "\(root.appending(path: "\(rawPrefix)/lvs-artifact-manifest.json").absoluteString)",
                  "summary": {
                    "status": "failed",
                    "toolName": "native-lvs",
                    "topCell": "INVX1",
                    "layoutInputKind": "layout-netlist",
                    "passed": false,
                    "activeMismatchCount": 1,
                    "waivedMismatchCount": 0,
                    "extractedLayoutNetlistURL": "\(root.appending(path: "\(rawPrefix)/layout-extracted.spice").absoluteString)",
                    "mismatchBuckets": [
                      {
                        "ruleID": "DEVICE_COUNT",
                        "category": "device-count",
                        "componentSignature": "nmos",
                        "parameterName": null,
                        "layoutModel": "nfet",
                        "schematicModel": "nfet",
                        "activeCount": 1,
                        "waivedCount": 0,
                        "layoutCount": 1,
                        "schematicCount": 2,
                        "layoutPorts": ["D", "G", "S"],
                        "schematicPorts": ["D", "G", "S", "B"],
                        "suggestedFixes": ["inspect-missing-device"]
                      }
                    ]
                  }
                }
                """.utf8
            ),
            lvsLogPath: Data("LVS_RESULT status=mismatch cell=INVX1\nLVS_DONE\n".utf8),
            lvsRepairHintPath: Data(
                """
                {
                  "schemaVersion": 1,
                  "status": "ready",
                  "reportURL": null,
                  "backendID": "native-lvs",
                  "topCell": "INVX1",
                  "activeDiagnosticCount": 1,
                  "hintCount": 1,
                  "hints": [
                    {
                      "hintID": "lvs-repair-0-DEVICE_COUNT",
                      "sourceDiagnosticIndex": 0,
                      "operationID": "layout.add-label",
                      "confidence": "medium",
                      "ruleID": "DEVICE_COUNT",
                      "category": "device-count",
                      "componentSignature": "nmos",
                      "parameterName": null,
                      "layoutModel": "nfet",
                      "schematicModel": "nfet",
                      "layoutValue": null,
                      "schematicValue": null,
                      "layoutPorts": ["D", "G", "S"],
                      "schematicPorts": ["D", "G", "S", "B"],
                      "layoutCount": 1,
                      "schematicCount": 2,
                      "stringParameters": {
                        "netName": "out",
                        "labelLayer": "met1"
                      },
                      "verificationGates": ["artifact-integrity", "native-lvs"],
                      "rationale": "DEVICE_COUNT maps to layout.add-label because the mismatch requires layout-side connectivity evidence."
                    }
                  ],
                  "unsupportedDiagnosticIndexes": []
                }
                """.utf8
            ),
            pexPath: Data(
                """
                {
                  "manifestURL": "\(root.appending(path: "\(rawPrefix)/pex-artifact-manifest.json").absoluteString)",
                  "summary": {
                    "runID": "run-signoff",
                    "status": "completed",
                    "backendID": "mock-pex",
                    "corners": [
                      {
                        "cornerID": "tt",
                        "status": "success",
                        "netCount": 3,
                        "elementCount": 8,
                        "topNets": [
                          {
                            "name": "out",
                            "groundCapF": 1e-15,
                            "couplingCapF": 2e-15,
                            "resistanceOhm": 25,
                            "nodeCount": 4
                          }
                        ],
                        "diagnostics": []
                      },
                      {
                        "cornerID": "ss",
                        "status": "failed",
                        "netCount": 0,
                        "elementCount": 0,
                        "topNets": [],
                        "diagnostics": [
                          {
                            "severity": "error",
                            "code": "PEX_CORNER_FAILED",
                            "message": "missing SPEF"
                          }
                        ]
                      }
                    ]
                  }
                }
                """.utf8
            ),
            preLayoutWaveformPath: Data("time,v(out),v(in)\n0,0,1\n1e-9,0.9,0\n".utf8),
            postLayoutWaveformPath: Data("time,v(out),v(in)\n0,0,1\n1e-9,1,0\n".utf8),
            simulationSummaryPath: Data(
                """
                {
                  "schemaVersion": 1,
                  "status": "failed",
                  "source": "post-layout-comparison",
                  "sourceReportPath": null,
                  "analysisLabel": "tran",
                  "expectations": [{"name": "tpd", "target": 1e-9, "tolerance": 1e-10}],
                  "measurements": [{"name": "tpd", "value": 1.4e-9, "unit": "s"}],
                  "verdicts": [
                    {"name": "tpd", "status": "failed", "value": 1.4e-9, "target": 1e-9, "tolerance": 1e-10}
                  ],
                  "diagnostics": [
                    {"severity": "error", "code": "SIM_METRIC_OUT_OF_RANGE", "message": "tpd exceeded bound"}
                  ]
                }
                """.utf8
            ),
            measurementsPath: Data(
                """
                [
                  {"name": "gain", "value": 12.5, "unit": "V/V"}
                ]
                """.utf8
            ),
            comparisonPath: Data(
                """
                {
                  "schemaVersion": 1,
                  "status": "completed",
                  "preLayoutPointCount": 10,
                  "postLayoutPointCount": 10,
                  "sweepVariable": "time",
                  "comparedPointCount": 10,
                  "maxAbsoluteDelta": 0.25,
                  "maxRelativeDelta": 0.5,
                  "comparedVariables": [
                    {
                      "variableName": "v(out)",
                      "pointCount": 10,
                      "maxAbsoluteDelta": 0.25,
                      "maxRelativeDelta": 0.5
                    }
                  ],
                  "requiredPostVariables": [],
                  "oscillationMetrics": [],
                  "missingInPostLayout": [],
                  "addedInPostLayout": [],
                  "diagnostics": ["ringing observed"],
                  "gateStatus": "failed",
                  "gateViolations": ["max relative delta exceeded"]
                }
                """.utf8
            ),
            designSpecPath: try encodedJSONData(designSpec),
            layoutDocumentPath: try encodedJSONData(layoutOutput.document),
            designUnitPath: try encodedJSONData(layoutOutput.designUnit),
        ]

        _ = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: runID,
                intent: "Review signoff artifacts",
                stages: [
                    FlowStageDefinition(stageID: stageID, displayName: "Signoff"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                PassingExecutor(stageID: stageID, artifacts: artifacts, artifactPayloads: payloads),
            ]
        )
        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-signoff-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        defer { removeTemporaryRoot(outsideRoot) }
        let outsideArtifact = outsideRoot.appending(path: "outside.log")
        try Data("outside artifact\n".utf8).write(to: outsideArtifact, options: .atomic)
        let symlinkURL = root.appending(path: symlinkEscapePath)
        try FileManager.default.createDirectory(
            at: symlinkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideArtifact)

        let service = RunReviewService()
        let review = try service.loadRun(runID: runID, projectRoot: root)
        let verificationContext = try service.waiverEditVerificationContext(
            review: review,
            projectRoot: root
        )
        #expect(verificationContext.designSpecArtifact.path == designSpecPath)
        #expect(verificationContext.layoutDocumentArtifact.path == layoutDocumentPath)
        #expect(verificationContext.designUnitArtifact?.path == designUnitPath)
        #expect(review.signoff.decodeIssues.isEmpty)
        #expect(review.signoff.cards.map(\.domain) == [
            "DRC",
            "LVS",
            "PEX",
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
        #expect(drcIssue.evidenceArtifacts.map(\.path).contains(drcPath))
        #expect(drcIssue.evidenceArtifacts.map(\.path).contains(drcLogPath))
        #expect(drcIssue.evidenceArtifacts.map(\.path).contains(drcEnvelopePath))
        #expect(drcIssue.evidenceArtifacts.map(\.path).contains(stageResultPath))
        #expect(!drcIssue.evidenceArtifacts.map(\.path).contains(lvsPath))
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
        #expect(drc.relatedArtifacts.contains { $0.artifactID == "drc-raw-log" })
        #expect(drc.relatedArtifacts.contains { $0.artifactID == "drc-repair-hints" })
        #expect(drc.relatedArtifacts.contains { $0.path == drcEnvelopePath })
        #expect(drc.relatedArtifacts.contains { $0.role == "stage-result" })
        #expect(!drc.relatedArtifacts.contains { $0.artifactID == "lvs-summary" })
        let drcLogPreview = try service.loadArtifactPreview(
            runID: runID,
            artifactPath: drcLogPath,
            projectRoot: root,
            maxBytes: 12
        )
        #expect(drcLogPreview.truncated)
        #expect(drcLogPreview.text == "DRC_SUMMARY ")
        let drcJSONPreview = try service.loadArtifactPreview(
            runID: runID,
            artifactPath: drcPath,
            projectRoot: root
        )
        #expect(drcJSONPreview.structuredPreview == "{manifestURL, reportURL, schemaVersion, summary}")
        #expect(drcJSONPreview.parseIssue == nil)
        #expect(throws: RunReviewServiceError.artifactPreviewNotFound(
            runID: runID,
            artifactPath: "\(rawPrefix)/unknown.json"
        )) {
            try service.loadArtifactPreview(
                runID: runID,
                artifactPath: "\(rawPrefix)/unknown.json",
                projectRoot: root
            )
        }
        #expect(throws: RunReviewServiceError.artifactPreviewEscapesProject(path: symlinkEscapePath)) {
            try service.loadArtifactPreview(
                runID: runID,
                artifactPath: symlinkEscapePath,
                projectRoot: root
            )
        }

        let lvs = try #require(review.signoff.cards.first { $0.domain == "LVS" })
        #expect(lvs.primaryMetrics.contains { $0.label == "Active" && $0.value == "1" })
        #expect(lvs.issues.first?.label == "DEVICE_COUNT")
        let lvsIssue = try #require(lvs.issues.first)
        #expect(lvsIssue.evidenceArtifacts.map(\.path).contains(lvsPath))
        #expect(lvsIssue.evidenceArtifacts.map(\.path).contains(lvsLogPath))
        #expect(!lvsIssue.evidenceArtifacts.map(\.path).contains(drcPath))
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
        #expect(lvs.relatedArtifacts.contains { $0.artifactID == "lvs-raw-log" })
        #expect(lvs.relatedArtifacts.contains { $0.artifactID == "lvs-repair-hints" })

        let repairPlanning = try service.formulateSignoffRepairPlanningProblem(
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
        #expect(repairPlanning.actionRecord.metadata["drcRepairHintPath"] == .string(drcRepairHintPath))
        #expect(repairPlanning.actionRecord.metadata["lvsRepairHintPath"] == .string(lvsRepairHintPath))
        #expect(repairPlanning.actionRecord.metadata["note"] == .string(
            "Generate signoff repair planning problem from review diagnostics."
        ))

        let planningProblem = try XcircuitePackageStore().readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: root.appending(path: repairPlanning.planningProblemArtifact.path)
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

        let signoffPlanningActions = try XcircuitePackageStore()
            .loadRunActions(runID: runID, inProjectAt: root)
            .filter { $0.actionKind == "review.formulateSignoffRepairPlanningProblem" }
        #expect(signoffPlanningActions.map(\.actionID) == [repairPlanning.actionRecord.actionID])

        let pex = try #require(review.signoff.cards.first { $0.domain == "PEX" })
        #expect(pex.passed == false)
        #expect(pex.primaryMetrics.contains { $0.label == "Failed" && $0.value == "1" })
        #expect(pex.issues.contains { $0.label == "ss:PEX_CORNER_FAILED" })
        let pexIssue = try #require(pex.issues.first { $0.label == "ss:PEX_CORNER_FAILED" })
        #expect(pexIssue.evidenceArtifacts.map(\.path).contains(pexPath))
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

        let simulationMetric = try #require(review.signoff.cards.first {
            $0.domain == "Simulation" && $0.title == "tran"
        })
        #expect(simulationMetric.passed == false)
        #expect(simulationMetric.issues.contains { $0.label == "tpd" })
        let timingIssue = try #require(simulationMetric.issues.first { $0.label == "tpd" })
        #expect(timingIssue.evidenceArtifacts.map(\.path).contains(simulationSummaryPath))
        #expect(timingIssue.evidenceArtifacts.map(\.path).contains(postLayoutWaveformPath))
        #expect(timingIssue.repairActionHints.first?.operationID == "simulation.metric-improvement-objective")
        let timingVerdictDetail = try #require(timingIssue.detailRows.first { $0.label == "Verdict" })
        #expect(timingVerdictDetail.metrics.contains { $0.label == "Metric" && $0.value == "tpd" })
        #expect(timingVerdictDetail.metrics.contains { $0.label == "Value" && $0.value == "1.4e-09" })
        #expect(timingVerdictDetail.metrics.contains { $0.label == "Target" && $0.value == "1e-09" })
        #expect(simulationMetric.relatedArtifacts.contains { $0.artifactID == "post-layout-waveform" })
        let waveformPreview = try service.loadArtifactPreview(
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
        #expect(comparisonIssue.evidenceArtifacts.map(\.path).contains(comparisonPath))
        #expect(comparisonIssue.evidenceArtifacts.map(\.path).contains(postLayoutWaveformPath))
        #expect(comparisonIssue.repairActionHints.first?.operationID == "pex.metric-recovery-objective")
        #expect(comparison.relatedArtifacts.contains { $0.artifactID == "pre-layout-waveform" })
        #expect(comparison.relatedArtifacts.contains { $0.artifactID == "post-layout-waveform" })

        let drilldown = service.interactiveSignoffDrilldown(from: review)
        #expect(drilldown.sections.map(\.domain) == [
            .drc,
            .lvs,
            .pex,
            .simulation,
            .postLayout,
            .waveform,
        ])
        let loadedDrilldown = try service.loadInteractiveSignoffDrilldown(
            runID: runID,
            projectRoot: root
        )
        #expect(loadedDrilldown == drilldown)
        let drcDrilldown = try #require(drilldown.section(for: .drc)?.items.first)
        #expect(drcDrilldown.interactions.contains(.issueEvidence))
        #expect(drcDrilldown.interactions.contains(.repairActionSelection))
        #expect(drcDrilldown.artifactRefs.contains {
            $0.source == "run-ledger"
                && $0.artifactID == "drc-summary"
                && $0.path == drcPath
        })
        #expect(drcDrilldown.artifactRefs.contains { $0.path == drcEnvelopePath })
        #expect(drcDrilldown.detailGroups.contains { $0.title == "Artifact Evaluation" })
        #expect(drcDrilldown.detailGroups.contains { $0.title == "Evaluation Channels" })
        #expect(drcDrilldown.detailGroups.contains { $0.title == "Feedback Signals" })
        let drcDrilldownIssue = try #require(drcDrilldown.issues.first)
        #expect(drcDrilldownIssue.artifactRefs.contains { $0.path == drcLogPath })
        #expect(drcDrilldownIssue.artifactRefs.contains { $0.path == drcEnvelopePath })
        #expect(drcDrilldownIssue.repairActionHints.map(\.operationID) == ["layout.resize-shape"])
        let lvsDrilldown = try #require(drilldown.section(for: .lvs)?.items.first)
        #expect(lvsDrilldown.issues.first?.repairActionHints.map(\.operationID) == [
            "layout.add-label",
            "layout.add-net",
        ])
        let pexDrilldown = try #require(drilldown.section(for: .pex)?.items.first)
        #expect(pexDrilldown.issues.contains { $0.label == "ss:PEX_CORNER_FAILED" })
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

        let waiverDecision = try RunReviewService().decideWaiverReview(
            runID: runID,
            waiverReviewID: waiver.waiverReviewID,
            decision: .approved,
            reviewer: "reviewer-1",
            note: "Waiver scope reviewed against the DRC summary.",
            projectRoot: root
        )
        #expect(waiverDecision.actionKind == "review.decideWaiver")
        #expect(waiverDecision.actor.kind == .human)
        #expect(waiverDecision.actor.identifier == "reviewer-1")
        #expect(waiverDecision.metadata["decision"] == .string("approved"))
        #expect(waiverDecision.metadata["waiverReviewID"] == .string(waiver.waiverReviewID))
        #expect(waiverDecision.inputs.first?.artifactID == "drc-summary")
        #expect(waiverDecision.metadata["editProposalIDs"] == .array([
            .string("remove-obsolete-drc-waiver"),
        ]))

        let proposalSelection = try RunReviewService().recordWaiverEditProposalSelection(
            runID: runID,
            waiverReviewID: waiver.waiverReviewID,
            proposalID: proposal.proposalID,
            reviewer: "reviewer-1",
            note: "Apply this before final signoff.",
            projectRoot: root
        )
        #expect(proposalSelection.actionKind == "review.selectWaiverEditProposal")
        #expect(proposalSelection.actor.kind == .human)
        #expect(proposalSelection.metadata["waiverReviewID"] == .string(waiver.waiverReviewID))
        #expect(proposalSelection.metadata["proposalID"] == .string("remove-obsolete-drc-waiver"))
        #expect(proposalSelection.metadata["targetPath"] == .string(waiverSourcePath))
        #expect(proposalSelection.metadata["operation"] == .string("remove-json-object"))
        #expect(proposalSelection.inputs.first?.artifactID == "drc-summary")

        let verificationResult = try await RunReviewService().applyWaiverEditProposalAndRunPostVerification(
            runID: runID,
            waiverReviewID: waiver.waiverReviewID,
            proposalID: proposal.proposalID,
            reviewer: "agent-1",
            note: "Apply waiver cleanup and re-run DRC/LVS.",
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
        let editedWaiverDocument = try JSONDecoder().decode(XcircuiteJSONValue.self, from: editedWaiverData)
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

        let approvedReview = try RunReviewService().loadRun(runID: runID, projectRoot: root)
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
        try writeJSON(failedVerificationReport, to: failedVerificationReportURL)

        let failedVerificationAction = try RunReviewService().recordWaiverEditVerification(
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
        #expect(failedVerificationAction.metadata["planningFeedbackStatus"] == XcircuiteJSONValue.string("rejected-plan-recorded"))
        #expect(failedVerificationAction.metadata["rejectedPlansPath"] == XcircuiteJSONValue.string(".xcircuite/runs/\(runID)/planning/rejected-plans.jsonl"))
        guard case .object(let failedVerificationSummaryMetadata) = failedVerificationAction.metadata["verificationSummary"] else {
            Issue.record("Failed verification action should persist a structured verification summary.")
            return
        }
        #expect(failedVerificationSummaryMetadata["readyForPEX"] == .bool(false))
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

        let rejectedReview = try RunReviewService().loadRun(runID: runID, projectRoot: root)
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
        #expect(commandHistorySummary.selectedActionDomainIDs == selectedActionDomainIDs(from: cycleTrace))
        #expect(
            commandHistorySummary.selectedObjectiveDomainIDs
                == selectedObjectiveDomainIDs(from: cycleTrace, problem: candidateCyclePlanningProblem)
        )
        #expect(
            commandHistorySummary.objectiveDomainSummaries.map(\.domainID)
                == commandHistorySummary.selectedObjectiveDomainIDs
        )
        #expect(commandHistorySummary.feedbackPenalizedActionIDs == feedbackPenalizedActionIDs(from: cycleTrace))
        #expect(commandHistorySummary.feedbackRankChangeCount == feedbackRankChanges(from: cycleTrace).count)
        #expect(commandHistorySummary.feedbackScoreDeltaCount == feedbackScoreDeltas(from: cycleTrace).count)

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

        let cycleActions = try XcircuitePackageStore().loadRunActions(runID: runID, inProjectAt: root)
        #expect(cycleActions.contains { $0.actionKind == "planning.execute-candidate-plan" })
        #expect(cycleActions.contains { $0.actionKind == "planning.verify-candidate-plan" })
        let cycleSummaryAction = try #require(cycleActions.first {
            $0.actionKind == "review.runSignoffRepairCandidateCycle"
        })
        #expect(cycleSummaryAction.outputs.contains { $0.artifactID == "planning-plan-verification" })
        #expect(cycleSummaryAction.outputs.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.candidateCycleHistorySummaryArtifactID
        })
        #expect(cycleSummaryAction.metadata["candidateCycleIndex"] == .number(1))
        #expect(cycleSummaryAction.metadata["rejectedPlanFeedbackRecordCount"] == .number(1))
        #expect(cycleSummaryAction.metadata["globalRejectedPlanFeedbackCount"] == .number(1))
        #expect(cycleSummaryAction.metadata["selectedActionIDs"] == .array(
            cycleTrace.selectedActionIDs.map { .string($0) }
        ))
        #expect(cycleSummaryAction.metadata["selectedActionDomainIDs"] == .array(
            selectedActionDomainIDs(from: cycleTrace).map { .string($0) }
        ))
        #expect(cycleSummaryAction.metadata["selectedObjectiveDomainIDs"] == .array(
            selectedObjectiveDomainIDs(from: cycleTrace, problem: candidateCyclePlanningProblem).map { .string($0) }
        ))
        #expect(cycleSummaryAction.metadata["feedbackPenalizedActionIDs"] == .array(
            feedbackPenalizedActionIDs(from: cycleTrace).map { .string($0) }
        ))
        #expect(cycleSummaryAction.metadata["feedbackRankChanges"] == .array(
            feedbackRankChanges(from: cycleTrace).map { .string($0) }
        ))
        #expect(cycleSummaryAction.metadata["feedbackScoreDeltas"] == .array(
            feedbackScoreDeltas(from: cycleTrace).map { .string($0) }
        ))

        let reloadedReview = try RunReviewService().loadRun(runID: runID, projectRoot: root)
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
        #expect(projectedCycle.selectedActionDomainIDs == selectedActionDomainIDs(from: cycleTrace))
        #expect(
            projectedCycle.selectedObjectiveDomainIDs
                == selectedObjectiveDomainIDs(from: cycleTrace, problem: candidateCyclePlanningProblem)
        )
        #expect(projectedCycle.feedbackPenalizedActionIDs == feedbackPenalizedActionIDs(from: cycleTrace))
        #expect(projectedCycle.feedbackRankChanges == feedbackRankChanges(from: cycleTrace))
        #expect(projectedCycle.feedbackScoreDeltas == feedbackScoreDeltas(from: cycleTrace))
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

    @Test func signoffRepairCandidateCycleHistorySummaryAggregatesFeedbackImpact() throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let firstCycle = RunReviewSignoffRepairCandidateCycleHistoryItem(
            actionID: "cycle-1",
            cycleIndex: 1,
            status: .blocked,
            planID: "plan-1",
            generationStatus: "succeeded",
            executionStatus: "succeeded",
            verificationStatus: "blocked",
            accepted: false,
            rejectedPlansPath: ".xcircuite/runs/run/rejected-plans.jsonl",
            rejectedPlanFeedbackRecordCount: 1,
            globalRejectedPlanFeedbackCount: 2,
            selectedActionIDs: ["repair-a", "repair-b"],
            selectedActionDomainIDs: ["layout-edit", "lvs-signoff"],
            selectedObjectiveDomainIDs: ["drc", "lvs"],
            feedbackPenalizedActionIDs: ["repair-a"],
            feedbackRankChanges: ["repair-a:1->2"],
            feedbackScoreDeltas: ["repair-a:-6"],
            candidatePlanArtifact: nil,
            planExecutionArtifact: nil,
            planVerificationArtifact: nil,
            rejectedPlansArtifact: nil,
            designDiffArtifact: nil,
            createdAt: baseDate
        )
        let secondCycle = RunReviewSignoffRepairCandidateCycleHistoryItem(
            actionID: "cycle-2",
            cycleIndex: 2,
            status: .succeeded,
            planID: "plan-2",
            generationStatus: "succeeded",
            executionStatus: "succeeded",
            verificationStatus: "succeeded",
            accepted: true,
            rejectedPlansPath: ".xcircuite/runs/run/rejected-plans.jsonl",
            rejectedPlanFeedbackRecordCount: 2,
            globalRejectedPlanFeedbackCount: 4,
            selectedActionIDs: ["repair-b", "repair-c"],
            selectedActionDomainIDs: ["lvs-signoff", "pex-extraction"],
            selectedObjectiveDomainIDs: ["lvs", "pex"],
            feedbackPenalizedActionIDs: ["repair-a", "repair-c"],
            feedbackRankChanges: ["repair-b:2->1", "repair-a:1->2"],
            feedbackScoreDeltas: ["repair-c:-3"],
            candidatePlanArtifact: nil,
            planExecutionArtifact: nil,
            planVerificationArtifact: nil,
            rejectedPlansArtifact: nil,
            designDiffArtifact: nil,
            createdAt: baseDate.addingTimeInterval(1)
        )

        let summary = RunReviewSignoffSummary(
            cards: [],
            repairCandidateCycles: [firstCycle, secondCycle]
        ).repairCandidateCycleHistorySummary

        #expect(summary.cycleCount == 2)
        #expect(summary.acceptedCount == 1)
        #expect(summary.notAcceptedCount == 1)
        #expect(summary.latestCycleIndex == 2)
        #expect(summary.latestAccepted == .some(true))
        #expect(summary.consumedRejectedPlanFeedbackRecordCount == 3)
        #expect(summary.maximumGlobalRejectedPlanFeedbackCount == 4)
        #expect(summary.selectedActionIDs == ["repair-a", "repair-b", "repair-c"])
        #expect(summary.selectedActionDomainIDs == ["layout-edit", "lvs-signoff", "pex-extraction"])
        #expect(summary.selectedObjectiveDomainIDs == ["drc", "lvs", "pex"])
        #expect(summary.objectiveDomainSummaries.map(\.domainID) == ["drc", "lvs", "pex"])
        #expect(summary.objectiveDomainSummaries.map(\.cycleCount) == [1, 2, 1])
        #expect(summary.objectiveDomainSummaries.map(\.acceptedCount) == [0, 1, 1])
        #expect(summary.feedbackPenalizedActionIDs == ["repair-a", "repair-c"])
        #expect(summary.feedbackRankChangeCount == 3)
        #expect(summary.feedbackRankChangedActionIDs == ["repair-a", "repair-b"])
        #expect(summary.feedbackScoreDeltaCount == 2)
        #expect(summary.feedbackScoreDeltaActionIDs == ["repair-a", "repair-c"])
        #expect(summary.hasFeedbackImpact)
    }

    private func feedbackPenalizedActionIDs(
        from trace: XcircuiteSymbolicPlannerTrace
    ) -> [String] {
        let actionIDs = trace.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.compactMap { actionTrace in
                actionTrace.scoreComponents.contains {
                    $0.termID.hasPrefix("feedback.") && $0.contribution < 0
                } ? actionTrace.actionID : nil
            }
        }
        return uniquePreservingOrder(actionIDs)
    }

    private func selectedActionDomainIDs(
        from trace: XcircuiteSymbolicPlannerTrace
    ) -> [String] {
        let domainIDs = trace.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.compactMap { actionTrace in
                actionTrace.selected ? actionTrace.domainID : nil
            }
        }
        return uniquePreservingOrder(domainIDs)
    }

    private func selectedObjectiveDomainIDs(
        from trace: XcircuiteSymbolicPlannerTrace,
        problem: XcircuiteCircuitPlanningProblem
    ) -> [String] {
        let domainsByObjectiveID = Dictionary(
            uniqueKeysWithValues: problem.objectives.map { ($0.objectiveID, $0.domain) }
        )
        let objectiveIDs = trace.objectiveTraces.compactMap { objectiveTrace in
            objectiveTrace.selectedActionID == nil ? nil : objectiveTrace.objectiveID
        }
        return uniquePreservingOrder(objectiveIDs.compactMap { domainsByObjectiveID[$0] })
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func feedbackRankChanges(
        from trace: XcircuiteSymbolicPlannerTrace
    ) -> [String] {
        let changes: [String] = trace.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.compactMap { actionTrace in
                guard actionTrace.rejectedFeedbackRankDelta != 0 else {
                    return nil
                }
                return "\(actionTrace.actionID):\(actionTrace.rankBeforeRejectedFeedback)->\(actionTrace.rank)"
            }
        }
        return uniquePreservingOrder(changes)
    }

    private func feedbackScoreDeltas(
        from trace: XcircuiteSymbolicPlannerTrace
    ) -> [String] {
        let deltas: [String] = trace.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.compactMap { actionTrace in
                guard actionTrace.rejectedFeedbackScoreDelta != 0 else {
                    return nil
                }
                return "\(actionTrace.actionID):\(actionTrace.rejectedFeedbackScoreDelta)"
            }
        }
        return uniquePreservingOrder(deltas)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func encodedJSONData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func reviewVerificationDesignSpec() -> DesignFlowDesignSpec {
        DesignFlowDesignSpec(
            name: "review-verification-divider",
            title: "Review verification divider",
            components: [
                DesignFlowDesignSpec.Component(
                    name: "V1",
                    deviceKindID: "vsource",
                    parameters: ["dc": 5.0]
                ),
                DesignFlowDesignSpec.Component(
                    name: "R1",
                    deviceKindID: "resistor",
                    parameters: ["r": 1_000]
                ),
                DesignFlowDesignSpec.Component(
                    name: "R2",
                    deviceKindID: "resistor",
                    parameters: ["r": 1_000]
                ),
                DesignFlowDesignSpec.Component(
                    name: "GND1",
                    deviceKindID: "ground"
                ),
            ],
            nets: [
                DesignFlowDesignSpec.Net(
                    name: "vin",
                    terminals: [
                        DesignFlowDesignSpec.Terminal(component: "V1", port: "pos"),
                        DesignFlowDesignSpec.Terminal(component: "R1", port: "pos"),
                    ]
                ),
                DesignFlowDesignSpec.Net(
                    name: "out",
                    terminals: [
                        DesignFlowDesignSpec.Terminal(component: "R1", port: "neg"),
                        DesignFlowDesignSpec.Terminal(component: "R2", port: "pos"),
                    ]
                ),
                DesignFlowDesignSpec.Net(
                    name: "0",
                    terminals: [
                        DesignFlowDesignSpec.Terminal(component: "V1", port: "neg"),
                        DesignFlowDesignSpec.Terminal(component: "R2", port: "neg"),
                        DesignFlowDesignSpec.Terminal(component: "GND1", port: "gnd"),
                    ]
                ),
            ],
            analyses: [
                DesignFlowDesignSpec.Analysis(kind: .op),
            ]
        )
    }

    private func removeTemporaryRoot(_ root: URL) {
        let path = root.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}
