import DesignFlowKernel
import Foundation
import Xcircuite
import XcircuitePackage

extension RunReviewService {
    func signoffReview(
        bundle: FlowRunReviewBundle,
        actions: [XcircuiteRunActionRecord],
        projectRoot: URL
    ) -> RunReviewSignoffSummary {
        var cards: [RunReviewSignoffCard] = []
        var decodeIssues: [RunReviewArtifactDecodeIssue] = []

        for artifact in bundle.artifacts where artifact.format == .json {
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
            case .none:
                continue
            }
        }

        return RunReviewSignoffSummary(
            cards: cards.sorted { left, right in
                if left.domain != right.domain {
                    return signoffDomainRank(left.domain) < signoffDomainRank(right.domain)
                }
                return left.artifact.path < right.artifact.path
            },
            repairCandidateCycles: signoffRepairCandidateCycles(from: actions),
            decodeIssues: decodeIssues
        )
    }

    private func signoffRepairCandidateCycles(
        from actions: [XcircuiteRunActionRecord]
    ) -> [RunReviewSignoffRepairCandidateCycleHistoryItem] {
        var cycles: [RunReviewSignoffRepairCandidateCycleHistoryItem] = []
        for action in actions where action.actionKind == "review.runSignoffRepairCandidateCycle" {
            let cycleIndex = intMetadata("candidateCycleIndex", in: action) ?? cycles.count + 1
            cycles.append(
                RunReviewSignoffRepairCandidateCycleHistoryItem(
                    actionID: action.actionID,
                    cycleIndex: cycleIndex,
                    status: action.status,
                    planID: stringMetadata("planID", in: action),
                    generationStatus: stringMetadata("generationStatus", in: action),
                    executionStatus: stringMetadata("executionStatus", in: action),
                    verificationStatus: stringMetadata("verificationStatus", in: action),
                    accepted: boolMetadata("accepted", in: action) ?? (action.status == .succeeded),
                    rejectedPlansPath: nonEmptyStringMetadata("rejectedPlansPath", in: action),
                    rejectedPlanFeedbackRecordCount: intMetadata(
                        "rejectedPlanFeedbackRecordCount",
                        in: action
                    ) ?? 0,
                    globalRejectedPlanFeedbackCount: intMetadata(
                        "globalRejectedPlanFeedbackCount",
                        in: action
                    ) ?? 0,
                    selectedActionIDs: stringArrayMetadata("selectedActionIDs", in: action),
                    selectedActionDomainIDs: stringArrayMetadata("selectedActionDomainIDs", in: action),
                    selectedObjectiveDomainIDs: stringArrayMetadata("selectedObjectiveDomainIDs", in: action),
                    feedbackPenalizedActionIDs: stringArrayMetadata(
                        "feedbackPenalizedActionIDs",
                        in: action
                    ),
                    feedbackRankChanges: stringArrayMetadata("feedbackRankChanges", in: action),
                    feedbackScoreDeltas: stringArrayMetadata("feedbackScoreDeltas", in: action),
                    candidatePlanArtifact: outputArtifact(
                        artifactID: XcircuitePlanningArtifactStore.candidatePlanArtifactID,
                        in: action
                    ),
                    planExecutionArtifact: outputArtifact(
                        artifactID: XcircuitePlanningArtifactStore.planExecutionArtifactID,
                        in: action
                    ),
                    planVerificationArtifact: outputArtifact(
                        artifactID: XcircuitePlanningArtifactStore.planVerificationArtifactID,
                        in: action
                    ),
                    rejectedPlansArtifact: outputArtifact(
                        artifactID: XcircuitePlanningArtifactStore.rejectedPlansArtifactID,
                        in: action
                    ),
                    designDiffArtifact: designDiffOutputArtifact(in: action),
                    createdAt: action.createdAt
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

    private func stringMetadata(_ key: String, in action: XcircuiteRunActionRecord) -> String? {
        guard case .string(let value) = action.metadata[key] else {
            return nil
        }
        return value
    }

    private func nonEmptyStringMetadata(
        _ key: String,
        in action: XcircuiteRunActionRecord
    ) -> String? {
        guard let value = stringMetadata(key, in: action), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func boolMetadata(_ key: String, in action: XcircuiteRunActionRecord) -> Bool? {
        guard case .bool(let value) = action.metadata[key] else {
            return nil
        }
        return value
    }

    private func intMetadata(_ key: String, in action: XcircuiteRunActionRecord) -> Int? {
        guard case .number(let value) = action.metadata[key] else {
            return nil
        }
        return Int(value)
    }

    private func stringArrayMetadata(
        _ key: String,
        in action: XcircuiteRunActionRecord
    ) -> [String] {
        guard case .array(let values) = action.metadata[key] else {
            return []
        }
        return values.compactMap { value in
            guard case .string(let string) = value else {
                return nil
            }
            return string
        }
    }

    private func outputArtifact(
        artifactID: String,
        in action: XcircuiteRunActionRecord
    ) -> XcircuiteFileReference? {
        action.outputs.first { $0.artifactID == artifactID }
    }

    private func designDiffOutputArtifact(
        in action: XcircuiteRunActionRecord
    ) -> XcircuiteFileReference? {
        action.outputs.first { artifact in
            artifact.kind == .designDiff || artifact.path.hasSuffix("/design-diff.json")
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
                    artifactRole: artifact.role,
                    artifactPath: artifact.path,
                    message: error.localizedDescription
                )
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
        let activeBuckets = summary.mismatchBuckets
            .filter { $0.activeCount > 0 }
            .sorted { $0.activeCount > $1.activeCount }
        return RunReviewSignoffCard(
            domain: "LVS",
            title: "LVS Summary",
            status: summary.status,
            passed: summary.passed,
            stageID: artifact.stageID,
            artifact: artifact,
            primaryMetrics: [
                RunReviewSignoffMetric(label: "Active", value: "\(summary.activeMismatchCount)"),
                RunReviewSignoffMetric(label: "Waived", value: "\(summary.waivedMismatchCount)"),
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
            ) + lvsDetailSections(summary),
            issues: activeBuckets.prefix(5).map { bucket in
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

    private func signoffArtifactKind(for artifact: FlowRunReviewArtifact) -> SignoffArtifactKind? {
        let artifactID = artifact.artifactID ?? ""
        let path = artifact.path.lowercased()
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
            || path.hasSuffix("signoff-retained-report-v1.json") {
            return .retainedSignoffReport
        }
        if artifactID == "planning-simulation-summary" || path.hasSuffix("simulation-summary.json") {
            return .simulationMetric
        }
        if artifact.kind == .measurement && path.hasSuffix("measurements.json") {
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
                candidate.path != artifact.path
                    && seenPaths.insert(candidate.path).inserted
                    && isRelatedArtifact(candidate, to: artifact, artifactKind: artifactKind)
            }
            .sorted { left, right in
                if left.role != right.role {
                    return left.role < right.role
                }
                return left.path < right.path
            }
    }

    private func issueEvidenceArtifacts(
        primary: FlowRunReviewArtifact,
        relatedArtifacts: [FlowRunReviewArtifact]
    ) -> [FlowRunReviewArtifact] {
        var seenPaths = Set<String>()
        return ([primary] + relatedArtifacts).filter { artifact in
            seenPaths.insert(artifact.path).inserted
        }
    }

    private func isRelatedArtifact(
        _ candidate: FlowRunReviewArtifact,
        to artifact: FlowRunReviewArtifact,
        artifactKind: SignoffArtifactKind?
    ) -> Bool {
        if candidate.stageID == artifact.stageID && candidate.role == "stage-result" {
            return true
        }
        guard let artifactKind else {
            return false
        }
        let searchable = [
            candidate.artifactID,
            candidate.role,
            candidate.path,
            candidate.kind.rawValue,
            candidate.format.rawValue,
        ]
        .compactMap { $0?.lowercased() }
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
        }
    }

    private func signoffDomainRank(_ domain: String) -> Int {
        switch domain {
        case "DRC": 0
        case "LVS": 1
        case "PEX": 2
        case "Oracle": 3
        case "Simulation": 4
        case "Post-layout": 5
        default: 10
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
        if artifact.path.hasPrefix("/") {
            URL(filePath: artifact.path)
        } else {
            projectRoot.appending(path: artifact.path)
        }
    }

}
