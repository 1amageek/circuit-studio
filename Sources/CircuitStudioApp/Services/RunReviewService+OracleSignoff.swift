import DesignFlowKernel
import Foundation
import CircuiteFoundation
import Xcircuite

extension RunReviewService {
    func generatedLayoutSignoffCorpusCard(
        document: XcircuiteGeneratedLayoutSignoffCorpusReport,
        artifact: FlowRunReviewArtifact
    ) -> RunReviewSignoffCard {
        let readinessValues = document.caseResults.flatMap(\.oracleReadiness)
        let readyReadinessCount = readinessValues.filter { $0.status == .ready }.count
        let evidenceRefCount = readinessValues.reduce(0) { $0 + $1.evidenceRefs.count }
        let disagreementCases = document.caseResults.filter { caseResult in
            caseResult.status != .passed || !caseResult.runStatusMatches
        }
        let missingEvidenceCount = readinessValues.filter {
            $0.status == .ready && $0.evidenceRefs.isEmpty
        }.count

        return RunReviewSignoffCard(
            domain: "Oracle",
            title: "Generated Layout Signoff Corpus",
            status: document.status.rawValue,
            passed: document.status == .passed
                && disagreementCases.isEmpty
                && missingEvidenceCount == 0,
            stageID: artifact.stageID,
            artifact: artifact,
            primaryMetrics: [
                RunReviewSignoffMetric(label: "Cases", value: "\(document.summary.caseCount)"),
                RunReviewSignoffMetric(label: "Passed", value: "\(document.summary.passedCaseCount)"),
                RunReviewSignoffMetric(label: "Failed", value: "\(document.summary.failedCaseCount)"),
                RunReviewSignoffMetric(label: "Oracle ready", value: "\(readyReadinessCount)/\(readinessValues.count)"),
                RunReviewSignoffMetric(label: "Evidence refs", value: "\(evidenceRefCount)"),
                RunReviewSignoffMetric(label: "Verdict mismatches", value: "\(document.summary.expectedVerdictMismatchCount)"),
            ],
            detailSections: generatedLayoutCorpusDetailSections(
                document: document,
                readyReadinessCount: readyReadinessCount,
                evidenceRefCount: evidenceRefCount,
                missingEvidenceCount: missingEvidenceCount
            ),
            issues: Array(
                (
                    generatedLayoutCorpusCaseIssues(document.caseResults)
                        + generatedLayoutCorpusReadinessIssues(document.caseResults)
                        + generatedLayoutCorpusStageIssues(document.caseResults)
                ).prefix(12)
            )
        )
    }

    func retainedSignoffReportCard(
        document: XcircuiteRetainedSignoffReport,
        artifact: FlowRunReviewArtifact
    ) -> RunReviewSignoffCard {
        let failedLanes = document.externalOracleResults.filter { !$0.provesRetainedExternalOracleReadiness }
        let passedLaneCount = document.summary.passedExternalOracleLaneCount
            ?? document.passingExternalOracleResults.count
        let blockedLaneCount = document.summary.blockedExternalOracleLaneCount
            ?? document.externalOracleResults.filter { $0.status == "blocked" }.count
        let failedLaneCount = document.summary.failedExternalOracleLaneCount
            ?? failedLanes.filter { $0.status != "blocked" }.count
        return RunReviewSignoffCard(
            domain: "Oracle",
            title: "Retained Signoff Oracle Dashboard",
            status: document.status,
            passed: document.provesRetainedExternalOracleInfrastructureReadiness,
            stageID: artifact.stageID,
            artifact: artifact,
            primaryMetrics: [
                RunReviewSignoffMetric(label: "Suite", value: document.suiteID),
                RunReviewSignoffMetric(label: "Lanes", value: "\(document.externalOracleResults.count)"),
                RunReviewSignoffMetric(label: "Passed", value: "\(passedLaneCount)"),
                RunReviewSignoffMetric(label: "Blocked", value: "\(blockedLaneCount)"),
                RunReviewSignoffMetric(label: "Failed", value: "\(failedLaneCount)"),
            ],
            detailSections: retainedSignoffDetailSections(document),
            issues: Array(
                (
                    retainedSignoffLaneIssues(document.externalOracleResults)
                        + retainedSignoffFailureIssues(document.failures)
                ).prefix(12)
            )
        )
    }

    private func generatedLayoutCorpusDetailSections(
        document: XcircuiteGeneratedLayoutSignoffCorpusReport,
        readyReadinessCount: Int,
        evidenceRefCount: Int,
        missingEvidenceCount: Int
    ) -> [RunReviewSignoffDetailSection] {
        [
            RunReviewSignoffDetailSection(
                title: "Corpus Summary",
                rows: [
                    RunReviewSignoffDetailRow(
                        label: document.suiteID,
                        metrics: oracleCompactMetrics([
                            ("Status", document.status.rawValue),
                            ("Cases", "\(document.summary.caseCount)"),
                            ("Passed", "\(document.summary.passedCaseCount)"),
                            ("Failed", "\(document.summary.failedCaseCount)"),
                            ("Oracle ready", "\(readyReadinessCount)"),
                            ("Evidence refs", "\(evidenceRefCount)"),
                            ("Missing ready evidence", "\(missingEvidenceCount)"),
                            ("Standard layouts", "\(document.summary.standardLayoutArtifactCount)"),
                            ("Signoff artifacts", "\(document.summary.signoffArtifactCount)"),
                        ])
                    ),
                ]
            ),
            generatedLayoutCorpusCoverageSection(document.summary),
            generatedLayoutCorpusCaseDisagreementSection(document.caseResults),
            generatedLayoutCorpusOracleReadinessSection(document.caseResults),
            generatedLayoutCorpusEvidenceRefSection(document.caseResults),
            generatedLayoutCorpusStageSection(document.caseResults),
            generatedLayoutCorpusArtifactRefSection(document.caseResults),
        ].compactMap { $0 }
    }

    private func generatedLayoutCorpusCoverageSection(
        _ summary: XcircuiteGeneratedLayoutSignoffCorpusReport.Summary
    ) -> RunReviewSignoffDetailSection? {
        let familyRows = summary.stageFamilyCounts.keys.sorted().map { family in
            RunReviewSignoffDetailRow(
                label: family,
                metrics: [RunReviewSignoffMetric(label: "Stages", value: "\(summary.stageFamilyCounts[family] ?? 0)")]
            )
        }
        let tagRows = [
            RunReviewSignoffDetailRow(
                label: "Coverage Tags",
                metrics: oracleCompactMetrics([
                    ("Required", oracleJoined(summary.requiredCoverageTags)),
                    ("Covered", oracleJoined(summary.coveredCoverageTags)),
                    ("Missing", oracleJoined(summary.missingCoverageTags)),
                ])
            ),
        ]
        let rows = tagRows + familyRows
        guard !rows.isEmpty else {
            return nil
        }
        return RunReviewSignoffDetailSection(title: "Corpus Coverage", rows: rows)
    }

    private func generatedLayoutCorpusCaseDisagreementSection(
        _ cases: [XcircuiteGeneratedLayoutSignoffCorpusReport.CaseResult]
    ) -> RunReviewSignoffDetailSection? {
        let rows = cases.filter {
            $0.status != .passed || !$0.runStatusMatches || !$0.diagnostics.isEmpty
        }.prefix(12).map { caseResult in
            RunReviewSignoffDetailRow(
                label: caseResult.caseID,
                metrics: oracleCompactMetrics([
                    ("Status", caseResult.status.rawValue),
                    ("Run", caseResult.runStatus.rawValue),
                    ("Expected", caseResult.expectedRunStatus.rawValue),
                    ("Run matches", "\(caseResult.runStatusMatches)"),
                    ("Diagnostics", "\(caseResult.diagnostics.count)"),
                    ("Tags", oracleJoined(caseResult.coverageTags)),
                ])
            )
        }
        guard !rows.isEmpty else {
            return nil
        }
        return RunReviewSignoffDetailSection(title: "Case Disagreements", rows: Array(rows))
    }

    private func generatedLayoutCorpusOracleReadinessSection(
        _ cases: [XcircuiteGeneratedLayoutSignoffCorpusReport.CaseResult]
    ) -> RunReviewSignoffDetailSection? {
        let rows = cases.flatMap { caseResult in
            caseResult.oracleReadiness.map { readiness in
                RunReviewSignoffDetailRow(
                    label: "\(caseResult.caseID):\(readiness.domain.rawValue)",
                    metrics: oracleCompactMetrics([
                        ("Domain", readiness.domain.rawValue),
                        ("Backend", readiness.backendID),
                        ("Status", readiness.status.rawValue),
                        ("Evidence refs", "\(readiness.evidenceRefs.count)"),
                        ("Reason", readiness.reason),
                    ])
                )
            }
        }.prefix(18)
        guard !rows.isEmpty else {
            return nil
        }
        return RunReviewSignoffDetailSection(title: "Oracle Readiness", rows: Array(rows))
    }

    private func generatedLayoutCorpusEvidenceRefSection(
        _ cases: [XcircuiteGeneratedLayoutSignoffCorpusReport.CaseResult]
    ) -> RunReviewSignoffDetailSection? {
        let rows = cases.flatMap { caseResult in
            caseResult.oracleReadiness.flatMap { readiness in
                readiness.evidenceRefs.enumerated().map { index, evidence in
                    RunReviewSignoffDetailRow(
                        label: "\(caseResult.caseID):\(readiness.domain.rawValue):\(index + 1)",
                        metrics: oracleCompactMetrics([
                            ("Role", evidence.role),
                            ("Path", evidence.path),
                            ("Kind", evidence.kind),
                            ("Format", evidence.format),
                            ("SHA", evidence.sha256),
                            ("Bytes", evidence.byteCount.map(String.init)),
                        ])
                    )
                }
            }
        }.prefix(18)
        guard !rows.isEmpty else {
            return nil
        }
        return RunReviewSignoffDetailSection(title: "Oracle Evidence Refs", rows: Array(rows))
    }

    private func generatedLayoutCorpusStageSection(
        _ cases: [XcircuiteGeneratedLayoutSignoffCorpusReport.CaseResult]
    ) -> RunReviewSignoffDetailSection? {
        let rows = cases.flatMap { caseResult in
            caseResult.stageResults.map { stage in
                RunReviewSignoffDetailRow(
                    label: "\(caseResult.caseID):\(stage.stageID)",
                    metrics: oracleCompactMetrics([
                        ("Family", stage.family.rawValue),
                        ("Status", stage.status.rawValue),
                        ("Expected", stage.expectedStatus?.rawValue),
                        ("Matches", "\(stage.statusMatches)"),
                        ("Gates", "\(stage.gateResults.count)"),
                        ("Artifacts", "\(stage.artifactRefs.count)"),
                        ("Diagnostics", "\(stage.diagnostics.count)"),
                    ])
                )
            }
        }.prefix(18)
        guard !rows.isEmpty else {
            return nil
        }
        return RunReviewSignoffDetailSection(title: "Case Stage Results", rows: Array(rows))
    }

    private func generatedLayoutCorpusArtifactRefSection(
        _ cases: [XcircuiteGeneratedLayoutSignoffCorpusReport.CaseResult]
    ) -> RunReviewSignoffDetailSection? {
        let rows = cases.flatMap { caseResult in
            (caseResult.sourceArtifactRefs + caseResult.signoffArtifactRefs).map { reference in
                RunReviewSignoffDetailRow(
                    label: "\(caseResult.caseID):\(reference.role.rawValue)",
                    metrics: artifactReferenceMetrics(reference)
                )
            }
        }.prefix(18)
        guard !rows.isEmpty else {
            return nil
        }
        return RunReviewSignoffDetailSection(title: "Case Artifact Refs", rows: Array(rows))
    }

    private func generatedLayoutCorpusCaseIssues(
        _ cases: [XcircuiteGeneratedLayoutSignoffCorpusReport.CaseResult]
    ) -> [RunReviewSignoffIssue] {
        cases.flatMap { caseResult in
            var issues: [RunReviewSignoffIssue] = []
            if caseResult.status != .passed || !caseResult.runStatusMatches {
                issues.append(
                    RunReviewSignoffIssue(
                        severity: "error",
                        label: "\(caseResult.caseID):case-disagreement",
                        count: caseResult.diagnostics.count,
                        message: "status=\(caseResult.status.rawValue) run=\(caseResult.runStatus.rawValue) expected=\(caseResult.expectedRunStatus.rawValue)",
                        detailRows: [
                            RunReviewSignoffDetailRow(
                                label: "Case",
                                metrics: oracleCompactMetrics([
                                    ("Run", caseResult.runID),
                                    ("Status", caseResult.status.rawValue),
                                    ("Run status", caseResult.runStatus.rawValue),
                                    ("Expected", caseResult.expectedRunStatus.rawValue),
                                    ("Tags", oracleJoined(caseResult.coverageTags)),
                                ])
                            ),
                        ]
                    )
                )
            }
            issues.append(contentsOf: caseResult.diagnostics.map { diagnostic in
                RunReviewSignoffIssue(
                    severity: diagnostic.severity.rawValue,
                    label: "\(caseResult.caseID):\(diagnostic.code)",
                    message: diagnostic.message,
                    detailRows: [
                        RunReviewSignoffDetailRow(
                            label: "Diagnostic",
                            metrics: oracleCompactMetrics([
                                ("Case", caseResult.caseID),
                                ("Code", diagnostic.code),
                                ("Severity", diagnostic.severity.rawValue),
                            ])
                        ),
                    ]
                )
            })
            return issues
        }
    }

    private func generatedLayoutCorpusReadinessIssues(
        _ cases: [XcircuiteGeneratedLayoutSignoffCorpusReport.CaseResult]
    ) -> [RunReviewSignoffIssue] {
        cases.flatMap { caseResult in
            caseResult.oracleReadiness.compactMap { readiness in
                if readiness.status != .ready || readiness.evidenceRefs.isEmpty {
                    return RunReviewSignoffIssue(
                        severity: readiness.status == .ready ? "warning" : "error",
                        label: "\(caseResult.caseID):\(readiness.domain.rawValue):oracle-readiness",
                        count: readiness.evidenceRefs.count,
                        message: readiness.reason,
                        detailRows: [
                            RunReviewSignoffDetailRow(
                                label: "Oracle Readiness",
                                metrics: oracleCompactMetrics([
                                    ("Domain", readiness.domain.rawValue),
                                    ("Backend", readiness.backendID),
                                    ("Status", readiness.status.rawValue),
                                    ("Evidence refs", "\(readiness.evidenceRefs.count)"),
                                ])
                            ),
                        ]
                    )
                }
                return nil
            }
        }
    }

    private func generatedLayoutCorpusStageIssues(
        _ cases: [XcircuiteGeneratedLayoutSignoffCorpusReport.CaseResult]
    ) -> [RunReviewSignoffIssue] {
        cases.flatMap { caseResult in
            caseResult.stageResults.flatMap { stage in
                var issues: [RunReviewSignoffIssue] = []
                if !stage.statusMatches {
                    let expectedStatus = stage.expectedStatus?.rawValue ?? "unspecified"
                    issues.append(
                        RunReviewSignoffIssue(
                            severity: "error",
                            label: "\(caseResult.caseID):\(stage.stageID):stage-disagreement",
                            message: "status=\(stage.status.rawValue) expected=\(expectedStatus)",
                            detailRows: [
                                RunReviewSignoffDetailRow(
                                    label: "Stage",
                                    metrics: oracleCompactMetrics([
                                        ("Family", stage.family.rawValue),
                                        ("Status", stage.status.rawValue),
                                        ("Expected", stage.expectedStatus?.rawValue),
                                        ("Gates", "\(stage.gateResults.count)"),
                                    ])
                                ),
                            ]
                        )
                    )
                }
                for gate in stage.gateResults where gate.status != .passed {
                    issues.append(
                        RunReviewSignoffIssue(
                            severity: "warning",
                            label: "\(caseResult.caseID):\(stage.stageID):\(gate.gateID)",
                            count: gate.diagnostics.count,
                            message: "gate \(gate.gateID) is \(gate.status.rawValue)",
                            detailRows: [
                                RunReviewSignoffDetailRow(
                                    label: "Gate",
                                    metrics: oracleCompactMetrics([
                                        ("Status", gate.status.rawValue),
                                        ("Diagnostics", "\(gate.diagnostics.count)"),
                                    ])
                                ),
                            ]
                        )
                    )
                }
                return issues
            }
        }
    }

    private func retainedSignoffDetailSections(
        _ document: XcircuiteRetainedSignoffReport
    ) -> [RunReviewSignoffDetailSection] {
        [
            RunReviewSignoffDetailSection(
                title: "Retained Dashboard",
                rows: [
                    RunReviewSignoffDetailRow(
                        label: document.suiteID,
                        metrics: oracleCompactMetrics([
                            ("Status", document.status),
                            ("Dashboard", document.summary.dashboardStatus),
                            ("External oracle", document.summary.externalOracleStatus),
                            ("Assessment", document.summary.externalOracleAssessmentStatus),
                            ("Lanes", document.summary.externalOracleLaneCount.map(String.init)),
                            ("Passed", document.summary.passedExternalOracleLaneCount.map(String.init)),
                            ("Blocked", document.summary.blockedExternalOracleLaneCount.map(String.init)),
                            ("Failed", document.summary.failedExternalOracleLaneCount.map(String.init)),
                        ])
                    ),
                ]
            ),
            retainedSignoffLaneSection(document.externalOracleResults),
            retainedSignoffLaneReportSection(document.externalOracleResults),
            retainedSignoffFailureSection(document.failures),
        ].compactMap { $0 }
    }

    private func retainedSignoffLaneSection(
        _ lanes: [XcircuiteRetainedSignoffReport.ExternalOracleResult]
    ) -> RunReviewSignoffDetailSection? {
        let rows = lanes.map { lane in
            RunReviewSignoffDetailRow(
                label: lane.domain,
                metrics: oracleCompactMetrics([
                    ("Status", lane.status),
                    ("Backend", lane.oracleBackendID),
                    ("Meets criteria", lane.assessmentPassed.map(String.init)),
                    ("Cases", lane.caseCount.map(String.init)),
                    ("Passed", lane.passedCaseCount.map(String.init)),
                    ("Failed", lane.failedCaseCount.map(String.init)),
                    ("Pass rate", lane.passRate.map(formatted)),
                    ("Agreement", lane.oracleAgreementRate.map(formatted)),
                    ("Readiness failures", lane.readinessFailureCount.map(String.init)),
                    ("Probes", oracleJoined(lane.requiredProbeIDs ?? [])),
                ])
            )
        }
        guard !rows.isEmpty else {
            return nil
        }
        return RunReviewSignoffDetailSection(title: "External Oracle Lanes", rows: rows)
    }

    private func retainedSignoffLaneReportSection(
        _ lanes: [XcircuiteRetainedSignoffReport.ExternalOracleResult]
    ) -> RunReviewSignoffDetailSection? {
        let rows = lanes.compactMap { lane -> RunReviewSignoffDetailRow? in
            guard let report = lane.report else {
                return nil
            }
            return RunReviewSignoffDetailRow(
                label: lane.domain,
                metrics: oracleCompactMetrics([
                    ("Status", lane.status),
                    ("Path", report.path),
                    ("SHA", report.digest.hexadecimalValue),
                    ("Bytes", String(report.byteCount)),
                ])
            )
        }
        guard !rows.isEmpty else {
            return nil
        }
        return RunReviewSignoffDetailSection(title: "Lane Report Refs", rows: rows)
    }

    private func retainedSignoffFailureSection(
        _ failures: [XcircuiteRetainedSignoffReport.Failure]
    ) -> RunReviewSignoffDetailSection? {
        let rows = failures.map { failure in
            RunReviewSignoffDetailRow(
                label: failure.code ?? "retained-signoff-failure",
                metrics: oracleCompactMetrics([
                    ("Message", failure.message),
                    ("Reason", failure.reason),
                ])
            )
        }
        guard !rows.isEmpty else {
            return nil
        }
        return RunReviewSignoffDetailSection(title: "Retained Failures", rows: rows)
    }

    private func retainedSignoffLaneIssues(
        _ lanes: [XcircuiteRetainedSignoffReport.ExternalOracleResult]
    ) -> [RunReviewSignoffIssue] {
        lanes.compactMap { lane in
                guard !lane.provesRetainedExternalOracleReadiness else {
                    return nil
                }
            return RunReviewSignoffIssue(
                severity: lane.status == "blocked" ? "warning" : "error",
                label: "\(lane.domain):retained-oracle-lane",
                count: lane.failedCaseCount,
                message: "status=\(lane.status) backend=\(lane.oracleBackendID ?? lane.domain)",
                detailRows: [
                    RunReviewSignoffDetailRow(
                        label: "External Oracle Lane",
                        metrics: oracleCompactMetrics([
                            ("Meets criteria", lane.assessmentPassed.map(String.init)),
                            ("Cases", lane.caseCount.map(String.init)),
                            ("Failed", lane.failedCaseCount.map(String.init)),
                            ("Pass rate", lane.passRate.map(formatted)),
                            ("Agreement", lane.oracleAgreementRate.map(formatted)),
                            ("Readiness failures", lane.readinessFailureCount.map(String.init)),
                        ])
                    ),
                ]
            )
        }
    }

    private func retainedSignoffFailureIssues(
        _ failures: [XcircuiteRetainedSignoffReport.Failure]
    ) -> [RunReviewSignoffIssue] {
        failures.map { failure in
            RunReviewSignoffIssue(
                severity: "error",
                label: failure.code ?? "retained-signoff-failure",
                message: failure.message ?? failure.reason ?? "Retained signoff report recorded a failure.",
                detailRows: [
                    RunReviewSignoffDetailRow(
                        label: "Failure",
                        metrics: oracleCompactMetrics([
                            ("Code", failure.code),
                            ("Reason", failure.reason),
                        ])
                    ),
                ]
            )
        }
    }

    private func artifactReferenceMetrics(
        _ reference: FlowArtifactBinding
    ) -> [RunReviewSignoffMetric] {
        oracleCompactMetrics([
            ("Artifact", reference.artifactID),
            ("Role", reference.role.rawValue),
            ("Path", reference.path),
            ("Kind", reference.kind.rawValue),
            ("Format", reference.format.rawValue),
            ("Digest", reference.digest.algorithm.rawValue),
            ("SHA", reference.digest.hexadecimalValue),
            ("Bytes", String(reference.byteCount)),
        ])
    }

    private func oracleCompactMetrics(
        _ pairs: [(label: String, value: String?)]
    ) -> [RunReviewSignoffMetric] {
        pairs.compactMap { pair in
            guard let value = pair.value, !value.isEmpty else {
                return nil
            }
            return RunReviewSignoffMetric(label: pair.label, value: value)
        }
    }

    private func oracleJoined(_ values: [String]) -> String? {
        guard !values.isEmpty else {
            return nil
        }
        return values.prefix(8).joined(separator: ", ")
    }
}
