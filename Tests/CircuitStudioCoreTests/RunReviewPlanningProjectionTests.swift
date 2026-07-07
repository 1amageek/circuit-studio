import Foundation
import Testing
import DesignFlowKernel
import ToolQualification
import Xcircuite
import XcircuitePackage
@testable import CircuitStudioApp
@testable import CircuitStudioCore

@Suite("Run review planning projection", .timeLimit(.minutes(2)))
struct RunReviewPlanningProjectionTests {
    @Test func planningCorrectnessItemsAreVisibleInTheReview() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-planning-correctness-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { RunReviewTestSupport.removeTemporaryRoot(root) }

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
                RunReviewPassingExecutor(stageID: "001-planning"),
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

    @Test func planningProjectionRequiresVerifiedArtifactIntegrity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-planning-integrity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { RunReviewTestSupport.removeTemporaryRoot(root) }

        let runID = "run-planning-integrity"
        let runDirectoryPath = ".xcircuite/runs/\(runID)"
        let candidatePlanPath = "\(runDirectoryPath)/planning/candidate-plan.json"
        let candidatePlan = XcircuiteCandidatePlan(
            planID: "plan-integrity",
            problemID: "problem-integrity",
            runID: runID,
            strategy: "integrity-regression",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "problem-ref",
                kind: "planning-problem"
            ),
            steps: [],
            verificationGates: [],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
        let payload = try RunReviewTestSupport.encodedJSONData(candidatePlan)
        try FileManager.default.createDirectory(
            at: root.appending(path: candidatePlanPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.write(to: root.appending(path: candidatePlanPath), options: .atomic)
        try FileManager.default.createDirectory(
            at: root.appending(path: runDirectoryPath),
            withIntermediateDirectories: true
        )
        let reference = XcircuiteFileReference(
            artifactID: "planning-candidate-plan",
            path: candidatePlanPath,
            kind: .other,
            format: .json,
            sha256: XcircuiteHasher().sha256(data: payload),
            byteCount: Int64(payload.count),
            producedByRunID: runID
        )
        let artifact = FlowRunReviewArtifact(
            role: "planning-candidate-plan",
            artifactID: "planning-candidate-plan",
            path: candidatePlanPath,
            kind: .other,
            format: .json,
            sha256: reference.sha256,
            byteCount: reference.byteCount,
            integrity: FlowRunReviewArtifactIntegrity(
                status: .sha256Mismatch,
                expectedSHA256: String(repeating: "a", count: 64),
                actualSHA256: String(repeating: "b", count: 64),
                expectedByteCount: 10,
                actualByteCount: 11,
                message: "Artifact SHA-256 mismatch"
            )
        )
        let ledger = FlowRunLedger(
            runID: runID,
            runDirectory: root.appending(path: runDirectoryPath),
            runManifest: XcircuiteRunManifest(
                runID: runID,
                status: .blocked,
                artifacts: [reference]
            ),
            stages: []
        )
        let bundle = FlowRunReviewBundle(
            runID: runID,
            status: .blocked,
            runDirectoryPath: runDirectoryPath,
            summary: FlowRunLedgerSummary(
                runID: runID,
                status: .blocked,
                runDirectoryPath: runDirectoryPath
            ),
            artifacts: [artifact]
        )
        let service = RunReviewService(
            ledgerLoader: PlanningStaticLedgerLoader(ledger: ledger),
            reviewBundler: PlanningStaticRunReviewBundler(bundle: bundle)
        )

        let review = try service.loadRun(runID: runID, projectRoot: root)

        #expect(review.planning.candidatePlanArtifact?.path == candidatePlanPath)
        #expect(review.planning.candidatePlan == nil)
        #expect(review.planning.decodeIssues.contains {
            $0.artifactPath == candidatePlanPath
                && $0.message.lowercased().contains("planning artifact integrity")
                && $0.message.contains("sha256Mismatch")
        })
    }
}

private struct PlanningStaticLedgerLoader: FlowRunLedgerLoading {
    let ledger: FlowRunLedger

    func loadRunLedger(runID: String, projectRoot: URL) throws -> FlowRunLedger {
        ledger
    }
}

private struct PlanningStaticRunReviewBundler: FlowRunReviewBundling {
    let bundle: FlowRunReviewBundle

    func makeReviewBundle(runID: String, projectRoot: URL) throws -> FlowRunReviewBundle {
        bundle
    }
}
