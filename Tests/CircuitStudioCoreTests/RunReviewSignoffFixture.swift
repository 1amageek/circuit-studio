import Foundation
import CircuiteFoundation
import DesignFlowKernel
import ToolQualification
import Xcircuite
@testable import CircuitStudioApp
@testable import CircuitStudioCore

struct RunReviewSignoffFixture {
    let root: URL
    let outsideRoot: URL
    let runID: String
    let stageID: String
    let rawPrefix: String
    let stageResultPath: String
    let drcPath: String
    let drcLogPath: String
    let drcRepairHintPath: String
    let drcEnvelopePath: String
    let lvsPath: String
    let lvsLogPath: String
    let lvsRepairHintPath: String
    let pexPath: String
    let simulationSummaryPath: String
    let preLayoutWaveformPath: String
    let postLayoutWaveformPath: String
    let symlinkEscapePath: String
    let measurementsPath: String
    let comparisonPath: String
    let designSpecPath: String
    let layoutDocumentPath: String
    let designUnitPath: String
    let generatedLayoutCorpusPath: String
    let retainedSignoffReportPath: String
    let drcOracleLaneReportPath: String
    let waiverSourcePath: String
    let service: RunReviewService
    let review: RunReviewService.RunReview

    @MainActor
    static func make() async throws -> Self {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-signoff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

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
        let generatedLayoutCorpusPath = "\(rawPrefix)/generated-layout-signoff/corpus-report-ready-oracle-evidence.json"
        let retainedSignoffReportPath = "\(rawPrefix)/retained-signoff-report.json"
        let drcOracleLaneReportPath = "\(rawPrefix)/oracle/drc-external-oracle-report.json"
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

        let designSpec = RunReviewTestSupport.reviewVerificationDesignSpec()
        let builtDesign = try designSpec.build()
        let layoutOutput = try DesignFlowService().generateLayout(DesignFlowLayoutGenerationRequest(
            schematic: builtDesign.schematic,
            catalog: .standard()
        ))

        let artifacts = [
            try RunReviewTestSupport.artifactReference(artifactID: "drc-summary", path: drcPath, kind: .report, format: .json),
            try RunReviewTestSupport.artifactReference(artifactID: "drc-raw-log", path: drcLogPath, kind: .report, format: .text),
            try RunReviewTestSupport.artifactReference(artifactID: "drc-repair-hints", path: drcRepairHintPath, kind: .report, format: .json),
            try RunReviewTestSupport.artifactReference(
                artifactID: "evidence-drc-summary-review",
                path: drcEnvelopePath,
                kind: .report,
                format: .json
            ),
            try RunReviewTestSupport.artifactReference(artifactID: "lvs-summary", path: lvsPath, kind: .report, format: .json),
            try RunReviewTestSupport.artifactReference(artifactID: "lvs-raw-log", path: lvsLogPath, kind: .report, format: .text),
            try RunReviewTestSupport.artifactReference(artifactID: "lvs-repair-hints", path: lvsRepairHintPath, kind: .report, format: .json),
            try RunReviewTestSupport.artifactReference(artifactID: "pex-summary", path: pexPath, kind: .report, format: .json),
            try RunReviewTestSupport.artifactReference(
                artifactID: "planning-simulation-summary",
                path: simulationSummaryPath,
                kind: .report,
                format: .json
            ),
            try RunReviewTestSupport.artifactReference(
                artifactID: "pre-layout-waveform",
                path: preLayoutWaveformPath,
                kind: .waveform,
                format: .csv
            ),
            try RunReviewTestSupport.artifactReference(
                artifactID: "post-layout-waveform",
                path: postLayoutWaveformPath,
                kind: .waveform,
                format: .csv
            ),
            try RunReviewTestSupport.artifactReference(
                artifactID: "symlink-escape",
                path: symlinkEscapePath,
                kind: .report,
                format: .text
            ),
            try RunReviewTestSupport.artifactReference(artifactID: "measurements", path: measurementsPath, kind: .measurement, format: .json),
            try RunReviewTestSupport.artifactReference(artifactID: "post-layout-comparison", path: comparisonPath, kind: .report, format: .json),
            try RunReviewTestSupport.artifactReference(artifactID: "design-spec", path: designSpecPath, kind: .other, format: .json),
            try RunReviewTestSupport.artifactReference(artifactID: "layout-document", path: layoutDocumentPath, kind: .layout, format: .json),
            try RunReviewTestSupport.artifactReference(artifactID: "design-unit", path: designUnitPath, kind: .other, format: .json),
            try RunReviewTestSupport.artifactReference(
                artifactID: "generated-layout-signoff-ready-oracle-corpus-report",
                path: generatedLayoutCorpusPath,
                kind: .report,
                format: .json
            ),
            try RunReviewTestSupport.artifactReference(
                artifactID: "retained-signoff-report",
                path: retainedSignoffReportPath,
                kind: .report,
                format: .json
            ),
            try RunReviewTestSupport.artifactReference(
                artifactID: "drc-external-oracle-report",
                path: drcOracleLaneReportPath,
                kind: .report,
                format: .json
            ),
        ]
        let pexManifestURLString = root
            .appending(path: "\(rawPrefix)/pex-artifact-manifest.json")
            .absoluteString
        let pexPayload = Data(
            """
            {
              "manifestURL": "\(pexManifestURLString)",
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
        )
        let payloads: [String: Data] = [
            drcPath: Data(
                """
                {
                  "schemaVersion": 2,
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
            drcEnvelopePath: try RunReviewTestSupport.encodedJSONData(FlowArtifactEnvelope(
                artifactID: "drc-summary",
                role: "drc-summary",
                stageID: stageID,
                reference: try RunReviewTestSupport.artifactReference(
                    artifactID: "drc-summary",
                    path: drcPath
                ),
                evaluationSpec: FlowEvaluationSpec(
                    specID: "drc-summary-evaluation-spec",
                    objective: "Evaluate DRC artifact evidence for repair planning.",
                    criteria: [
                        FlowEvaluationCriterion(
                            criterionID: "drc-active-violation-count",
                            channelID: "drc-active-violation-count",
                            comparator: .equal,
                            target: .scalar(0)
                        ),
                    ],
                    requiredArtifactRoles: ["drc-summary"]
                ),
                observationSet: FlowObservationSet(
                    observationSetID: "drc-summary-observations",
                    specID: "drc-summary-evaluation-spec",
                    channels: [
                        FlowObservationChannel(
                            channelID: "drc-active-violation-count",
                            label: "Active DRC violations",
                            status: .observed,
                            value: .scalar(2),
                            sourceArtifactIDs: ["drc-summary"],
                            confidence: FlowEvidenceConfidence(value: 0.9, calibrated: true)
                        ),
                        FlowObservationChannel(
                            channelID: "drc-magic-oracle-agreement",
                            status: .missing,
                            sourceArtifactIDs: ["drc-summary"],
                            confidence: FlowEvidenceConfidence(value: 0, calibrated: false)
                        ),
                        FlowObservationChannel(
                            channelID: "drc-qualified-calibration",
                            status: .uncalibrated,
                            value: .scalar(0.4),
                            sourceArtifactIDs: ["drc-summary"],
                            confidence: FlowEvidenceConfidence(
                                value: 0.4,
                                posteriorVariance: 0.6,
                                calibrated: false
                            )
                        ),
                    ],
                    confidence: FlowEvidenceConfidence(
                        value: 0.55,
                        posteriorVariance: 0.45,
                        calibrated: false
                    )
                ),
                evaluationResult: FlowEvaluationResult(
                    evaluationID: "drc-summary-evaluation",
                    specID: "drc-summary-evaluation-spec",
                    status: .rejected,
                    likelihood: 0.2,
                    residual: 2,
                    confidence: FlowEvidenceConfidence(
                        value: 0.55,
                        posteriorVariance: 0.45,
                        calibrated: false
                    ),
                    channelResults: [
                        FlowEvaluationChannelResult(
                            criterionID: "drc-active-violation-count",
                            channelID: "drc-active-violation-count",
                            status: .rejected,
                            observedValue: .scalar(2),
                            residual: 2,
                            likelihood: 0.2,
                            confidence: FlowEvidenceConfidence(value: 0.9, calibrated: true)
                        ),
                    ],
                    feedbackSignals: [
                        FlowFeedbackSignal(
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
                            confidence: FlowEvidenceConfidence(value: 0.55, calibrated: false)
                        ),
                    ],
                    summary: "DRC has active violations and incomplete oracle evidence."
                )
            )),
            drcLogPath: Data("DRC_SUMMARY total=2 cell=INVX1\nDRC_DONE\n".utf8),
            drcRepairHintPath: Data(
                """
                {
                  "schemaVersion": 4,
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
                  "unsupportedDiagnosticIndexes": [],
                  "diagnostics": []
                }
                """.utf8
            ),
            lvsPath: Data(
                """
                {
                  "schemaVersion": 2,
                  "reportURL": "\(root.appending(path: lvsPath).absoluteString)",
                  "manifestURL": "\(root.appending(path: "\(rawPrefix)/lvs-artifact-manifest.json").absoluteString)",
                  "summary": {
                    "executionStatus": "completed",
                    "verdict": "mismatch",
                    "readiness": "ready",
                    "blockingReasons": [],
                    "toolName": "native-lvs",
                    "topCell": "INVX1",
                    "layoutInputKind": "layout-netlist",
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
                  "unsupportedDiagnosticIndexes": [],
                  "unsupportedDiagnostics": []
                }
                """.utf8
            ),
            pexPath: pexPayload,
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
            designSpecPath: try RunReviewTestSupport.encodedJSONData(designSpec),
            layoutDocumentPath: try RunReviewTestSupport.encodedJSONData(layoutOutput.document),
            designUnitPath: try RunReviewTestSupport.encodedJSONData(layoutOutput.designUnit),
            generatedLayoutCorpusPath: Data(
                """
                {
                  "schemaVersion": 1,
                  "suiteID": "generated-layout-signoff-ladder",
                  "status": "failed",
                  "summary": {
                    "caseCount": 2,
                    "passedCaseCount": 1,
                    "failedCaseCount": 1,
                    "requiredCoverageTags": ["drc", "lvs", "pex"],
                    "coveredCoverageTags": ["drc", "lvs"],
                    "missingCoverageTags": ["pex"],
                    "stageFamilyCounts": {
                      "drc": 2,
                      "lvs": 2,
                      "pex": 1
                    },
                    "expectedVerdictMismatchCount": 1,
                    "oracleReadinessDeclaredCaseCount": 4,
                    "standardLayoutArtifactCount": 2,
                    "signoffArtifactCount": 5
                  },
                  "caseResults": [
                    {
                      "caseID": "standard-gds-drc-pass",
                      "runID": "run-signoff-pass",
                      "status": "passed",
                      "runStatus": "succeeded",
                      "expectedRunStatus": "succeeded",
                      "runStatusMatches": true,
                      "coverageTags": ["drc", "layout-standard"],
                      "oracleReadiness": [
                        {
                          "domain": "drc",
                          "backendID": "magic",
                          "status": "ready",
                          "reason": "Retained DRC external oracle lane passed.",
                          "evidenceRefs": [
                            {
                              "role": "retained-signoff-report",
                              "path": "\(retainedSignoffReportPath)",
                              "kind": "report",
                              "format": "JSON",
                              "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                              "byteCount": 512
                            },
                            {
                              "role": "drc-external-oracle-report",
                              "path": "\(drcOracleLaneReportPath)",
                              "kind": "report",
                              "format": "JSON",
                              "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                              "byteCount": 128
                            }
                          ]
                        },
                        {
                          "domain": "lvs",
                          "backendID": "netgen",
                          "status": "ready",
                          "reason": "Retained LVS external oracle lane passed.",
                          "evidenceRefs": [
                            {
                              "role": "retained-signoff-report",
                              "path": "\(retainedSignoffReportPath)",
                              "kind": "report",
                              "format": "JSON",
                              "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                              "byteCount": 512
                            }
                          ]
                        }
                      ],
                      "stageResults": [
                        {
                          "stageID": "010-drc",
                          "family": "drc",
                          "status": "succeeded",
                          "expectedStatus": "succeeded",
                          "statusMatches": true,
                          "gateResults": [
                            {
                              "gateID": "native-drc",
                              "status": "passed",
                              "diagnostics": []
                            }
                          ],
                          "artifactRefs": [
                            {
                              "role": "stage-summary",
                              "artifactID": "drc-summary",
                              "stageID": "010-drc",
                              "path": "\(drcPath)",
                              "kind": "report",
                              "format": "json",
                              "sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
                              "byteCount": 256,
                              "integrityStatus": "verified",
                              "integrityMessage": null
                            }
                          ],
                          "diagnostics": []
                        }
                      ],
                      "sourceArtifactRefs": [
                        {
                          "id": "layout-gds",
                          "locator": {
                            "location": {
                              "storage": "workspaceRelative",
                              "value": "\(rawPrefix)/layout.gds"
                            },
                            "role": "output",
                            "kind": "layout",
                            "format": "gds"
                          },
                          "digest": {
                            "algorithm": "sha256",
                            "hexadecimalValue": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
                          },
                          "byteCount": 1024
                        }
                      ],
                      "signoffArtifactRefs": [
                        {
                          "id": "drc-summary",
                          "locator": {
                            "location": {
                              "storage": "workspaceRelative",
                              "value": "\(drcPath)"
                            },
                            "role": "output",
                            "kind": "report",
                            "format": "json"
                          },
                          "digest": {
                            "algorithm": "sha256",
                            "hexadecimalValue": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
                          },
                          "byteCount": 256
                        }
                      ],
                      "diagnostics": []
                    },
                    {
                      "caseID": "standard-gds-lvs-fail",
                      "runID": "run-signoff-lvs-fail",
                      "status": "failed",
                      "runStatus": "failed",
                      "expectedRunStatus": "succeeded",
                      "runStatusMatches": false,
                      "coverageTags": ["lvs", "layout-standard"],
                      "oracleReadiness": [
                        {
                          "domain": "lvs",
                          "backendID": "netgen",
                          "status": "blocked",
                          "reason": "Retained LVS oracle lane has a case-level disagreement.",
                          "evidenceRefs": []
                        },
                        {
                          "domain": "pex",
                          "backendID": "openrcx",
                          "status": "ready",
                          "reason": "Retained PEX oracle lane is ready but evidence refs were not attached.",
                          "evidenceRefs": []
                        }
                      ],
                      "stageResults": [
                        {
                          "stageID": "020-lvs",
                          "family": "lvs",
                          "status": "failed",
                          "expectedStatus": "succeeded",
                          "statusMatches": false,
                          "gateResults": [
                            {
                              "gateID": "native-lvs",
                              "status": "failed",
                              "diagnostics": [
                                {
                                  "severity": "error",
                                  "code": "lvs-device-count-disagreement",
                                  "message": "Layout and schematic device counts disagree."
                                }
                              ]
                            }
                          ],
                          "artifactRefs": [
                            {
                              "role": "stage-summary",
                              "artifactID": "lvs-summary",
                              "stageID": "020-lvs",
                              "path": "\(lvsPath)",
                              "kind": "report",
                              "format": "json",
                              "sha256": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
                              "byteCount": 256,
                              "integrityStatus": "verified",
                              "integrityMessage": null
                            }
                          ],
                          "diagnostics": [
                            {
                              "severity": "error",
                              "code": "lvs-device-count-disagreement",
                              "message": "Layout and schematic device counts disagree."
                            }
                          ]
                        }
                      ],
                      "sourceArtifactRefs": [],
                      "signoffArtifactRefs": [
                        {
                          "id": "lvs-summary",
                          "locator": {
                            "location": {
                              "storage": "workspaceRelative",
                              "value": "\(lvsPath)"
                            },
                            "role": "output",
                            "kind": "report",
                            "format": "json"
                          },
                          "digest": {
                            "algorithm": "sha256",
                            "hexadecimalValue": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
                          },
                          "byteCount": 256
                        }
                      ],
                      "diagnostics": [
                        {
                          "severity": "error",
                          "code": "expected-verdict-mismatch",
                          "message": "Generated layout signoff case failed when success was expected."
                        }
                      ]
                    }
                  ],
                  "suiteSpecArtifact": null,
                  "reportArtifact": null
                }
                """.utf8
            ),
            retainedSignoffReportPath: Data(
                """
                {
                  "schemaVersion": 1,
                  "kind": "retained-signoff-report",
                  "suiteID": "generated-layout-signoff-ladder",
                  "status": "partial",
                  "summary": {
                    "dashboardStatus": "needs-review",
                    "externalOracleStatus": "partial",
                    "externalOracleAssessmentStatus": "partial",
                    "externalOracleLaneCount": 2,
                    "passedExternalOracleLaneCount": 1,
                    "blockedExternalOracleLaneCount": 0,
                    "failedExternalOracleLaneCount": 1
                  },
                  "externalOracleResults": [
                    {
                      "domain": "drc",
                      "status": "passed",
                      "oracleBackendID": "magic",
                      "assessmentPassed": true,
                      "caseCount": 4,
                      "passedCaseCount": 4,
                      "failedCaseCount": 0,
                      "passRate": 1,
                      "oracleAgreementRate": 1,
                      "readinessFailureCount": 0,
                      "requiredProbeIDs": ["drc-clean"],
                      "report": {
                        "id": "drc-external-oracle-report",
                        "locator": {
                          "location": {
                            "storage": "workspaceRelative",
                            "value": "\(drcOracleLaneReportPath)"
                          },
                          "role": "drc-external-oracle-report",
                          "kind": "report",
                          "format": "json"
                        },
                        "digest": {
                          "algorithm": "sha256",
                          "hexadecimalValue": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
                        },
                        "byteCount": 128
                      }
                    },
                    {
                      "domain": "lvs",
                      "status": "failed",
                      "oracleBackendID": "netgen",
                      "assessmentPassed": false,
                      "caseCount": 3,
                      "passedCaseCount": 2,
                      "failedCaseCount": 1,
                      "passRate": 0.667,
                      "oracleAgreementRate": 0.8,
                      "readinessFailureCount": 1,
                      "requiredProbeIDs": ["ports", "devices"],
                      "report": null
                    }
                  ],
                  "failures": [
                    {
                      "code": "lvs-oracle-disagreement",
                      "message": "LVS oracle disagrees on device count.",
                      "reason": "case-level mismatch"
                    }
                  ]
                }
                """.utf8
            ),
            drcOracleLaneReportPath: Data(
                """
                {
                  "status": "passed",
                  "backendID": "magic",
                  "caseCount": 4
                }
                """.utf8
            ),
        ]

        _ = try await RunReviewTestSupport.orchestrator(projectRoot: root).run(
            request: FlowOperationRequest(
                workspaceID: try await RunReviewTestSupport.workspaceID(projectRoot: root),
                runID: runID,
                intent: "Review signoff artifacts",
                stages: [
                    FlowStageDefinition(stageID: stageID, displayName: "Signoff"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                RunReviewPassingExecutor(stageID: stageID, artifacts: artifacts, artifactPayloads: payloads),
            ]
        )
        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-review-signoff-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        let outsideArtifact = outsideRoot.appending(path: "outside.log")
        try Data("outside artifact\n".utf8).write(to: outsideArtifact, options: .atomic)
        let symlinkURL = root.appending(path: symlinkEscapePath)
        try FileManager.default.createDirectory(
            at: symlinkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideArtifact)

        let service = RunReviewService()
        let review = try await service.loadRun(runID: runID, projectRoot: root)
        return Self(
            root: root,
            outsideRoot: outsideRoot,
            runID: runID,
            stageID: stageID,
            rawPrefix: rawPrefix,
            stageResultPath: stageResultPath,
            drcPath: drcPath,
            drcLogPath: drcLogPath,
            drcRepairHintPath: drcRepairHintPath,
            drcEnvelopePath: drcEnvelopePath,
            lvsPath: lvsPath,
            lvsLogPath: lvsLogPath,
            lvsRepairHintPath: lvsRepairHintPath,
            pexPath: pexPath,
            simulationSummaryPath: simulationSummaryPath,
            preLayoutWaveformPath: preLayoutWaveformPath,
            postLayoutWaveformPath: postLayoutWaveformPath,
            symlinkEscapePath: symlinkEscapePath,
            measurementsPath: measurementsPath,
            comparisonPath: comparisonPath,
            designSpecPath: designSpecPath,
            layoutDocumentPath: layoutDocumentPath,
            designUnitPath: designUnitPath,
            generatedLayoutCorpusPath: generatedLayoutCorpusPath,
            retainedSignoffReportPath: retainedSignoffReportPath,
            drcOracleLaneReportPath: drcOracleLaneReportPath,
            waiverSourcePath: waiverSourcePath,
            service: service,
            review: review
        )
    }
}
