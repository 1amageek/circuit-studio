import Foundation
import Testing
import LayoutCore
import LayoutTech
import LayoutVerify
@testable import CircuitStudioApp
@testable import CircuitStudioCore
@testable import SchematicEditor

@Suite("HeadlessRoundTripService Tests")
struct HeadlessRoundTripServiceTests {

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func cmosInverterCompletesHeadlessRoundTripWithArtifacts() async throws {
        let testbench = Testbench(
            name: "Transient",
            analysisCommands: [
                .tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9)),
            ]
        )
        let pexIR = PEXParasiticIR(
            version: "1.0",
            cornerID: "tt_25c_1v0",
            elements: [
                PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 1.0),
                PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 2e-15),
            ]
        )

        let roundTrip = try await runRoundTrip(
            rootName: "cmos-round-trip",
            runID: "cmos-inverter-round-trip",
            title: "CMOS inverter headless round trip",
            schematic: SchematicPreview.cmosInverterViewModel().document,
            testbench: testbench,
            postLayoutCommand: .tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9)),
            pexIR: pexIR
        )

        try assertCompletedRoundTrip(roundTrip)
    }

    @Test(.enabled(if: PostLayoutOracleService.ngspiceAvailable()), .timeLimit(.minutes(6)))
    @MainActor
    func cmosInverterRoundTripCrossChecksAgainstNgspiceOracle() async throws {
        let testbench = Testbench(
            name: "Transient",
            analysisCommands: [.tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9))]
        )
        // Heavier output load so the post-layout edges are RC-smoothed and the raw
        // max|ΔV| cross-tool comparison is robust (sharp logic edges otherwise put a
        // large instantaneous ΔV at the transition for sub-ps cross-tool skew).
        let pexIR = PEXParasiticIR(
            version: "1.0",
            cornerID: "tt_25c_1v0",
            elements: [
                PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 1.0),
                PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 50e-15),
            ]
        )
        let roundTrip = try await runRoundTrip(
            rootName: "cmos-oracle",
            runID: "cmos-inverter-oracle",
            title: "CMOS inverter round trip with ngspice oracle",
            schematic: SchematicPreview.cmosInverterViewModel().document,
            testbench: testbench,
            postLayoutCommand: .tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9)),
            pexIR: pexIR,
            oracleProbes: ["out"]
        )
        defer { removeTemporaryRoot(roundTrip.projectRoot) }

        let stage = try #require(
            roundTrip.result.manifest.stages.first { $0.name == "post-layout-oracle" },
            "the oracle stage must run when ngspice is available"
        )
        #expect(stage.status == .passed, "CoreSpice vs ngspice — \(stage.message)")
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func voltageDividerCompletesHeadlessRoundTripWithArtifacts() async throws {
        let testbench = Testbench(
            name: "Operating Point",
            analysisCommands: [.op]
        )
        let pexIR = PEXParasiticIR(
            version: "1.0",
            cornerID: "tt_25c_1v0",
            elements: [
                PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 0.5),
                PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 1e-15),
            ]
        )
        let schematic = SchematicPreview.voltageDividerViewModel().document

        let roundTrip = try await runRoundTrip(
            rootName: "voltage-divider-round-trip",
            runID: "voltage-divider-round-trip",
            title: "Voltage divider headless round trip",
            schematic: schematic,
            testbench: testbench,
            postLayoutCommand: .op,
            pexIR: pexIR
        )

        try assertCompletedRoundTrip(roundTrip)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func resistorDividerCompletesHeadlessRoundTripWithArtifacts() async throws {
        let pexIR = PEXParasiticIR(
            version: "1.0",
            cornerID: "tt_25c_1v0",
            elements: [
                PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 0.75),
                PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 1.5e-15),
            ]
        )

        let roundTrip = try await runRoundTrip(
            rootName: "resistor-divider-round-trip",
            runID: "resistor-divider-round-trip",
            title: "Resistor divider headless round trip",
            schematic: SchematicPreview.voltageDividerViewModel().document,
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: pexIR
        )

        try assertCompletedRoundTrip(roundTrip)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func rcLowPassCompletesHeadlessRoundTripWithArtifacts() async throws {
        let command = AnalysisCommand.tran(TranSpec(stopTime: 20e-6, stepTime: 0.1e-6))
        let pexIR = PEXParasiticIR(
            version: "1.0",
            cornerID: "tt_25c_1v0",
            elements: [
                PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 0.25),
                PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 2e-15),
            ]
        )

        let roundTrip = try await runRoundTrip(
            rootName: "rc-low-pass-round-trip",
            runID: "rc-low-pass-round-trip",
            title: "RC low-pass headless round trip",
            schematic: SchematicPreview.rcLowPassViewModel().document,
            testbench: Testbench(name: "Transient", analysisCommands: [command]),
            postLayoutCommand: command,
            pexIR: pexIR
        )

        try assertCompletedRoundTrip(roundTrip)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func voltageDividerCompletesRoundTripWithImportedSignoffReview() async throws {
        let root = try makeTemporaryRoot("voltage-divider-imported-signoff")
        defer { removeTemporaryRoot(root) }

        let drcLogURL = root.appending(path: "golden-drc.log")
        let lvsLogURL = root.appending(path: "golden-lvs.log")
        let pexManifestURL = root.appending(path: "pex-manifest.json")
        try """
        [INFO] rule=DRC_CLEAN message="clean drc"
        SIGNOFF_RESULT status=pass
        """.write(to: drcLogURL, atomically: true, encoding: .utf8)
        try """
        [INFO] rule=LVS_MATCH message="clean lvs"
        SIGNOFF_RESULT status=pass
        """.write(to: lvsLogURL, atomically: true, encoding: .utf8)
        try """
        {"status":"success"}
        """.write(to: pexManifestURL, atomically: true, encoding: .utf8)

        let review = try ExternalSignoffArtifactService().load(logs: [
            ExternalSignoffLogArtifact(kind: .drc, toolName: "imported-drc", logURL: drcLogURL, success: true),
            ExternalSignoffLogArtifact(kind: .lvs, toolName: "imported-lvs", logURL: lvsLogURL, success: true),
        ])
        let configuration = makeConfiguration(
            projectRoot: root,
            runID: "voltage-divider-imported-signoff",
            title: "Voltage divider imported signoff round trip",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: smallPEXIR(),
            pexArtifactPaths: [pexManifestURL.path(percentEncoded: false)],
            externalSignoffReview: review
        )

        let result = try await HeadlessRoundTripService().run(
            schematic: SchematicPreview.voltageDividerViewModel().document,
            configuration: configuration
        )

        #expect(result.manifest.isRoundTripComplete)
        #expect(result.manifest.isReadyForPEX)
        #expect(result.externalSignoff?.isReadyForPEX == true)
        #expect(result.externalSignoff?.reports.map(\.toolName) == ["imported-drc", "imported-lvs"])
        #expect(result.manifest.artifacts.contains {
            $0.kind == "external-signoff-log"
                && $0.sourcePath == drcLogURL.path(percentEncoded: false)
                && $0.path.contains("input-artifacts/signoff/")
        })
        #expect(result.manifest.artifacts.contains {
            $0.kind == "external-signoff-log"
                && $0.sourcePath == lvsLogURL.path(percentEncoded: false)
                && $0.path.contains("input-artifacts/signoff/")
        })
        #expect(result.manifest.artifacts.contains {
            $0.kind == "pex-artifact"
                && $0.sourcePath == pexManifestURL.path(percentEncoded: false)
                && $0.path.contains("input-artifacts/pex/")
        })
        #expect(result.manifest.artifacts.contains {
            $0.kind == "external-signoff-review"
                && $0.sourcePath?.hasSuffix(".xcircuite/signoff/external-signoff-review.json") == true
                && $0.path.contains("input-artifacts/signoff/")
        })
        #expect(!result.manifest.artifacts.map(\.path).contains { $0.hasSuffix("mock-drc.log") })

        let storedReview = try ExternalSignoffReviewStore().load(forProjectAt: root)
        #expect(storedReview.approvedBy == "layout-reviewer")
        #expect(storedReview.isReadyForPEX)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func postLayoutComparisonMismatchWritesNotComparableArtifact() async throws {
        let root = try makeTemporaryRoot("comparison-mismatch")
        defer { removeTemporaryRoot(root) }

        let configuration = makeConfiguration(
            projectRoot: root,
            runID: "comparison-mismatch",
            title: "Comparison mismatch artifact",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .dcSweep(DCSweepSpec(source: "V1", startValue: 0, stopValue: 1, stepValue: 0.5)),
            pexIR: smallPEXIR(),
            externalSignoffCommands: try makeSignoffCommands(in: root)
        )

        _ = try await HeadlessRoundTripService().run(
            schematic: SchematicPreview.voltageDividerViewModel().document,
            configuration: configuration
        )

        let manifest = try loadManifest(projectRoot: root, runID: "comparison-mismatch")
        #expect(manifest.isRoundTripComplete)
        #expect(manifest.stages.first { $0.name == "post-layout-comparison" }?.status == .passed)
        #expect(manifest.artifacts.map(\.path).contains { $0.hasSuffix("post-layout-comparison.json") })
        let comparisonURL = try #require(manifest.artifacts.first {
            $0.kind == "post-layout-comparison"
        }).path
        let comparisonData = try Data(contentsOf: artifactURL(
            path: comparisonURL,
            projectRoot: root,
            runID: "comparison-mismatch"
        ))
        let comparison = try JSONDecoder().decode(PostLayoutComparisonReport.self, from: comparisonData)
        #expect(comparison.status == "not-comparable")
        #expect(comparison.diagnostics.contains { $0.contains("Sweep variable mismatch") })
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func postLayoutComparisonWriteFailureWritesManifest() async throws {
        let root = try makeTemporaryRoot("comparison-write-failure")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "comparison-write-failure")
        try FileManager.default.createDirectory(
            at: runDirectory.appending(path: "post-layout-comparison.json"),
            withIntermediateDirectories: true
        )
        let configuration = makeConfiguration(
            projectRoot: root,
            runID: "comparison-write-failure",
            title: "Comparison write failure manifest",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: smallPEXIR(),
            externalSignoffCommands: try makeSignoffCommands(in: root)
        )

        do {
            _ = try await HeadlessRoundTripService().run(
                schematic: SchematicPreview.voltageDividerViewModel().document,
                configuration: configuration
            )
            Issue.record("Expected post-layout comparison write failure")
        } catch {
            #expect(error.localizedDescription.contains("Failed to write headless flow manifest"))
        }

        let manifest = try loadManifest(projectRoot: root, runID: "comparison-write-failure")
        assertFailureManifest(
            manifest,
            failedStage: "post-layout-comparison",
            skippedStages: [],
            isReadyForPEX: true
        )
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func postLayoutComparisonLimitsRejectNotComparableReportAndWriteManifest() async throws {
        let root = try makeTemporaryRoot("comparison-limit-not-comparable")
        defer { removeTemporaryRoot(root) }

        let configuration = makeConfiguration(
            projectRoot: root,
            runID: "comparison-limit-not-comparable",
            title: "Comparison limit not comparable manifest",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .dcSweep(DCSweepSpec(source: "V1", startValue: 0, stopValue: 1, stepValue: 0.5)),
            pexIR: smallPEXIR(),
            postLayoutComparisonLimits: PostLayoutComparisonLimits(maxAbsoluteDelta: 1.0),
            externalSignoffCommands: try makeSignoffCommands(in: root)
        )

        do {
            _ = try await HeadlessRoundTripService().run(
                schematic: SchematicPreview.voltageDividerViewModel().document,
                configuration: configuration
            )
            Issue.record("Expected post-layout comparison limit failure")
        } catch {
            #expect(error.localizedDescription.contains("Post-layout comparison exceeded configured limits"))
        }

        let manifest = try loadManifest(projectRoot: root, runID: "comparison-limit-not-comparable")
        assertFailureManifest(
            manifest,
            failedStage: "post-layout-comparison",
            skippedStages: [],
            isReadyForPEX: true
        )
        #expect(manifest.stages.first { $0.name == "post-layout-comparison" }?.message?.contains("not comparable") == true)
        #expect(manifest.artifacts.map(\.path).contains { $0.hasSuffix("post-layout-comparison.json") })
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func postLayoutComparisonLimitsRejectNumericDeltaAndWriteManifest() async throws {
        let root = try makeTemporaryRoot("comparison-limit-delta")
        defer { removeTemporaryRoot(root) }

        let configuration = makeConfiguration(
            projectRoot: root,
            runID: "comparison-limit-delta",
            title: "Comparison limit delta manifest",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: smallPEXIR(),
            postLayoutComparisonLimits: PostLayoutComparisonLimits(maxAbsoluteDelta: 0),
            externalSignoffCommands: try makeSignoffCommands(in: root)
        )

        do {
            _ = try await HeadlessRoundTripService().run(
                schematic: SchematicPreview.voltageDividerViewModel().document,
                configuration: configuration
            )
            Issue.record("Expected post-layout comparison numeric limit failure")
        } catch {
            #expect(error.localizedDescription.contains("Post-layout comparison exceeded configured limits"))
        }

        let manifest = try loadManifest(projectRoot: root, runID: "comparison-limit-delta")
        assertFailureManifest(
            manifest,
            failedStage: "post-layout-comparison",
            skippedStages: [],
            isReadyForPEX: true
        )
        #expect(manifest.stages.first { $0.name == "post-layout-comparison" }?.message?.contains("absolute delta") == true)

        let comparisonURL = try #require(manifest.artifacts.first {
            $0.kind == "post-layout-comparison"
        }).path
        let comparisonData = try Data(contentsOf: artifactURL(
            path: comparisonURL,
            projectRoot: root,
            runID: "comparison-limit-delta"
        ))
        let comparison = try JSONDecoder().decode(PostLayoutComparisonReport.self, from: comparisonData)
        #expect(comparison.status == "compared")
        #expect(comparison.gateStatus == "failed")
        #expect(comparison.comparisonLimits == PostLayoutComparisonLimits(maxAbsoluteDelta: 0))
        #expect(comparison.gateViolations.contains { $0.contains("absolute delta") })
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func postLayoutComparisonLimitsPersistPassingGatePolicy() async throws {
        let root = try makeTemporaryRoot("comparison-limit-pass")
        defer { removeTemporaryRoot(root) }

        let limits = PostLayoutComparisonLimits(maxAbsoluteDelta: 1.0, maxRelativeDelta: 1.0)
        let configuration = makeConfiguration(
            projectRoot: root,
            runID: "comparison-limit-pass",
            title: "Comparison limit pass manifest",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: smallPEXIR(),
            postLayoutComparisonLimits: limits,
            externalSignoffCommands: try makeSignoffCommands(in: root)
        )

        _ = try await HeadlessRoundTripService().run(
            schematic: SchematicPreview.voltageDividerViewModel().document,
            configuration: configuration
        )

        let manifest = try loadManifest(projectRoot: root, runID: "comparison-limit-pass")
        #expect(manifest.isRoundTripComplete)
        #expect(manifest.stages.first { $0.name == "post-layout-comparison" }?.status == .passed)
        #expect(manifest.stages.first { $0.name == "post-layout-comparison" }?.message == "passed")

        let comparisonURL = try #require(manifest.artifacts.first {
            $0.kind == "post-layout-comparison"
        }).path
        let comparisonData = try Data(contentsOf: artifactURL(
            path: comparisonURL,
            projectRoot: root,
            runID: "comparison-limit-pass"
        ))
        let comparison = try JSONDecoder().decode(PostLayoutComparisonReport.self, from: comparisonData)
        #expect(comparison.comparisonLimits == limits)
        #expect(comparison.gateStatus == "passed")
        #expect(comparison.gateViolations.isEmpty)
    }

    @Test func bottleneckHistoryAggregatesRoundTripManifests() throws {
        let root = try makeTemporaryRoot("bottleneck-history")
        defer { removeTemporaryRoot(root) }

        let completedManifest = HeadlessRoundTripService.Manifest(
            runID: "completed",
            title: "Completed run",
            createdAt: Date(timeIntervalSince1970: 1_000),
            isRoundTripComplete: true,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(
                    name: "net-extraction",
                    status: .passed,
                    durationSeconds: 0.1
                ),
                HeadlessRoundTripService.Stage(
                    name: "post-layout-simulation",
                    status: .passed,
                    durationSeconds: 1.5
                ),
            ],
            artifacts: [],
            bottleneckSummary: HeadlessRoundTripService.BottleneckSummary(
                totalMeasuredDurationSeconds: 1.6,
                longestStageName: "post-layout-simulation",
                longestStageDurationSeconds: 1.5,
                failedStageName: nil,
                recommendations: []
            )
        )
        let failedManifest = HeadlessRoundTripService.Manifest(
            runID: "failed",
            title: "Failed run",
            createdAt: Date(timeIntervalSince1970: 2_000),
            isRoundTripComplete: false,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(
                    name: "post-layout-simulation",
                    status: .passed,
                    durationSeconds: 0.5
                ),
                HeadlessRoundTripService.Stage(
                    name: "post-layout-comparison",
                    status: .failed,
                    durationSeconds: 0.2
                ),
            ],
            artifacts: [],
            bottleneckSummary: HeadlessRoundTripService.BottleneckSummary(
                totalMeasuredDurationSeconds: 0.7,
                longestStageName: "post-layout-simulation",
                longestStageDurationSeconds: 0.5,
                failedStageName: "post-layout-comparison",
                recommendations: []
            )
        )

        try writeManifest(completedManifest, projectRoot: root, runID: "completed")
        try writeManifest(failedManifest, projectRoot: root, runID: "failed")

        let summary = try RoundTripBottleneckHistoryService().summarize(forProjectAt: root)
        let postLayoutSimulation = try #require(summary.stageSummaries.first {
            $0.stageName == "post-layout-simulation"
        })

        #expect(summary.runCount == 2)
        #expect(summary.failedRunCount == 1)
        #expect(summary.mostFrequentFailedStageName == "post-layout-comparison")
        #expect(summary.mostExpensiveStageName == "post-layout-simulation")
        #expect(postLayoutSimulation.observedCount == 2)
        #expect(postLayoutSimulation.totalDurationSeconds == 2.0)
        #expect(postLayoutSimulation.maxDurationSeconds == 1.5)
        #expect(summary.recommendations.count == 2)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func invalidPostLayoutComparisonLimitsFailBeforeRunArtifacts() async throws {
        let root = try makeTemporaryRoot("comparison-invalid-limit")
        defer { removeTemporaryRoot(root) }

        let configuration = makeConfiguration(
            projectRoot: root,
            runID: "comparison-invalid-limit",
            title: "Comparison invalid limit",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: smallPEXIR(),
            postLayoutComparisonLimits: PostLayoutComparisonLimits(maxAbsoluteDelta: .nan),
            externalSignoffCommands: try makeSignoffCommands(in: root)
        )

        try await expectInvalidDesign(
            "Invalid max absolute delta limit: nan.",
            operation: {
                _ = try await HeadlessRoundTripService().run(
                    schematic: SchematicPreview.voltageDividerViewModel().document,
                    configuration: configuration
                )
            }
        )

        let manifestURL = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "comparison-invalid-limit")
            .appending(path: "round-trip-manifest.json")
        #expect(!FileManager.default.fileExists(atPath: manifestURL.path(percentEncoded: false)))
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func invalidRunIDFailsBeforeRunArtifacts() async throws {
        let root = try makeTemporaryRoot("invalid-run-id")
        defer { removeTemporaryRoot(root) }

        let configuration = makeConfiguration(
            projectRoot: root,
            runID: "../escaped-run",
            title: "Invalid run ID",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: smallPEXIR(),
            externalSignoffCommands: try makeSignoffCommands(in: root)
        )

        try await expectInvalidDesign(
            "Invalid run ID: use only letters, numbers, '.', '_', or '-', and do not use '.' or '..'.",
            operation: {
                _ = try await HeadlessRoundTripService().run(
                    schematic: SchematicPreview.voltageDividerViewModel().document,
                    configuration: configuration
                )
            }
        )

        let flowRunsDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
        #expect(!FileManager.default.fileExists(atPath: flowRunsDirectory.path(percentEncoded: false)))
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func capturedSiblingArtifactDoesNotUseRunDirectoryPrefixMatch() async throws {
        let root = try makeTemporaryRoot("capture-prefix")
        defer { removeTemporaryRoot(root) }

        let runID = "capture-prefix"
        let siblingDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "\(runID)-sibling")
        try FileManager.default.createDirectory(at: siblingDirectory, withIntermediateDirectories: true)
        let pexManifestURL = siblingDirectory.appending(path: "pex-manifest.json")
        try """
        {"status":"success"}
        """.write(to: pexManifestURL, atomically: true, encoding: .utf8)

        let configuration = makeConfiguration(
            projectRoot: root,
            runID: runID,
            title: "Capture prefix isolation",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: smallPEXIR(),
            pexArtifactPaths: [pexManifestURL.path(percentEncoded: false)],
            externalSignoffCommands: try makeSignoffCommands(in: root)
        )

        let result = try await HeadlessRoundTripService().run(
            schematic: SchematicPreview.voltageDividerViewModel().document,
            configuration: configuration
        )
        let pexArtifact = try #require(result.manifest.artifacts.first {
            $0.kind == "pex-artifact"
        })

        #expect(pexArtifact.sourcePath == pexManifestURL.path(percentEncoded: false))
        #expect(pexArtifact.path.contains("input-artifacts/pex/"))
        #expect(!pexArtifact.path.hasPrefix("/"))
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func designArtifactDirectoryFailureWritesReviewableManifest() async throws {
        let root = try makeTemporaryRoot("capture-directory")
        defer { removeTemporaryRoot(root) }

        let designArtifactDirectory = root.appending(path: "design-artifacts")
        try FileManager.default.createDirectory(at: designArtifactDirectory, withIntermediateDirectories: true)
        try "not capturable\n".write(
            to: designArtifactDirectory.appending(path: "nested.txt"),
            atomically: true,
            encoding: .utf8
        )

        let configuration = makeConfiguration(
            projectRoot: root,
            runID: "capture-directory",
            title: "Capture directory failure manifest",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: smallPEXIR(),
            designArtifactPaths: [designArtifactDirectory.path(percentEncoded: false)]
        )

        do {
            _ = try await HeadlessRoundTripService().run(
                schematic: SchematicPreview.voltageDividerViewModel().document,
                configuration: configuration
            )
            Issue.record("Expected design artifact directory capture failure")
        } catch StudioError.projectLoadFailed(let message) {
            #expect(message == "Input artifact must be a regular file: \(designArtifactDirectory.path(percentEncoded: false))")
        } catch {
            Issue.record("Expected project load failure, got \(error)")
        }

        let manifest = try loadManifest(projectRoot: root, runID: "capture-directory")
        #expect(!manifest.isRoundTripComplete)
        #expect(!manifest.isReadyForPEX)
        #expect(manifest.artifacts.isEmpty)
        #expect(manifest.stages.first { $0.name == "input-artifact-capture" }?.status == .failed)
        #expect(manifest.stages.first { $0.name == "net-extraction" }?.status == .skipped)
        #expect(manifest.stages.first { $0.name == "post-layout-comparison" }?.status == .skipped)
        #expect(manifest.bottleneckSummary?.failedStageName == "input-artifact-capture")
        #expect(manifest.bottleneckSummary?.recommendations.contains {
            $0.contains("configured design, signoff, and PEX artifact paths")
        } == true)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func symlinkedInRunArtifactTargetingExternalFileIsCaptured() async throws {
        let root = try makeTemporaryRoot("capture-symlink")
        defer { removeTemporaryRoot(root) }

        let runID = "capture-symlink"
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: runID)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let externalDirectory = root.appending(path: "external-artifacts")
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        let externalArtifactURL = externalDirectory.appending(path: "external-pex.log")
        try "external pex log\n".write(to: externalArtifactURL, atomically: true, encoding: .utf8)

        let symlinkURL = runDirectory.appending(path: "linked-pex.log")
        try FileManager.default.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: externalArtifactURL
        )

        let configuration = makeConfiguration(
            projectRoot: root,
            runID: runID,
            title: "Capture symlink isolation",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: smallPEXIR(),
            pexArtifactPaths: [symlinkURL.path(percentEncoded: false)],
            externalSignoffCommands: try makeSignoffCommands(in: root)
        )

        let result = try await HeadlessRoundTripService().run(
            schematic: SchematicPreview.voltageDividerViewModel().document,
            configuration: configuration
        )
        let pexArtifact = try #require(result.manifest.artifacts.first {
            $0.kind == "pex-artifact"
        })

        #expect(pexArtifact.sourcePath == symlinkURL.path(percentEncoded: false))
        #expect(pexArtifact.path.contains("input-artifacts/pex/"))
        #expect(!pexArtifact.path.hasPrefix("/"))
        let capturedContents = try String(
            contentsOf: artifactURL(path: pexArtifact.path, projectRoot: root, runID: runID),
            encoding: .utf8
        )
        #expect(capturedContents == "external pex log\n")
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func prePEXGateFailureWritesManifest() async throws {
        let root = try makeTemporaryRoot("pre-pex-failure")
        defer { removeTemporaryRoot(root) }

        let commands = try makeSignoffCommands(
            in: root,
            drcContents: """
            #!/bin/sh
            printf '[ERROR] rule=DRC_FAIL message="drc failed"\\n'
            exit 2
            """,
            lvsContents: """
            #!/bin/sh
            printf '[INFO] rule=LVS_MATCH message="clean lvs"\\n'
            printf 'SIGNOFF_RESULT status=pass\\n'
            exit 0
            """
        )
        let configuration = makeConfiguration(
            projectRoot: root,
            runID: "pre-pex-failure",
            title: "Pre-PEX failure manifest",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: smallPEXIR(),
            externalSignoffCommands: commands
        )

        try await expectInvalidDesign(
            "Pre-PEX verification gate failed.",
            operation: {
                _ = try await HeadlessRoundTripService().run(
                    schematic: SchematicPreview.voltageDividerViewModel().document,
                    configuration: configuration
                )
            }
        )

        let manifest = try loadManifest(projectRoot: root, runID: "pre-pex-failure")
        assertFailureManifest(
            manifest,
            failedStage: "external-signoff",
            skippedStages: ["pex-injection", "post-layout-simulation"],
            isReadyForPEX: false
        )
        #expect(manifest.stages.first { $0.name == "external-signoff" }?.status == .failed)
        #expect(manifest.stages.first { $0.name == "pre-pex-verification" }?.status == .failed)
        #expect(manifest.artifacts.map(\.path).contains { $0.hasSuffix("drc-mock-drc.log") })
        #expect(manifest.artifacts.contains {
            $0.kind == "external-signoff-review"
                && $0.sourcePath?.hasSuffix(".xcircuite/signoff/external-signoff-review.json") == true
                && $0.path.contains("input-artifacts/signoff/")
        })
        #expect(manifest.artifacts.contains {
            $0.kind == "pre-layout-simulation-report"
                && $0.path.hasSuffix("pre-layout-simulation.json")
        })
        #expect(manifest.artifacts.contains {
            $0.kind == "pre-layout-waveform"
                && $0.path.hasSuffix("pre-layout-waveform.csv")
        })
        let layoutArtifact = try #require(manifest.artifacts.first { $0.kind == "layout-document" })
        let designUnitArtifact = try #require(manifest.artifacts.first { $0.kind == "design-unit" })
        let verificationArtifact = try #require(manifest.artifacts.first { $0.kind == "physical-verification-report" })
        #expect(FileManager.default.fileExists(atPath: artifactURL(
            path: layoutArtifact.path,
            projectRoot: root,
            runID: "pre-pex-failure"
        ).path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: artifactURL(
            path: designUnitArtifact.path,
            projectRoot: root,
            runID: "pre-pex-failure"
        ).path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: artifactURL(
            path: verificationArtifact.path,
            projectRoot: root,
            runID: "pre-pex-failure"
        ).path(percentEncoded: false)))

        let verificationData = try Data(contentsOf: artifactURL(
            path: verificationArtifact.path,
            projectRoot: root,
            runID: "pre-pex-failure"
        ))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let verificationReport = try decoder.decode(DesignFlowVerificationReport.self, from: verificationData)
        #expect(verificationReport.status == "failed")
        #expect(!verificationReport.readyForPEX)
        #expect(verificationReport.externalSignoff?.readyForPEX == false)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func emptyPEXIRFailureWritesManifest() async throws {
        let root = try makeTemporaryRoot("empty-pex-failure")
        defer { removeTemporaryRoot(root) }

        let configuration = makeConfiguration(
            projectRoot: root,
            runID: "empty-pex-failure",
            title: "Empty PEX failure manifest",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: PEXParasiticIR(version: "1.0", cornerID: "tt_25c_1v0", elements: []),
            externalSignoffCommands: try makeSignoffCommands(in: root)
        )

        try await expectInvalidDesign(
            "Headless round trip requires non-empty PEX IR.",
            operation: {
                _ = try await HeadlessRoundTripService().run(
                    schematic: SchematicPreview.voltageDividerViewModel().document,
                    configuration: configuration
                )
            }
        )

        let manifest = try loadManifest(projectRoot: root, runID: "empty-pex-failure")
        assertFailureManifest(
            manifest,
            failedStage: "pex-injection",
            skippedStages: ["post-layout-simulation"],
            isReadyForPEX: true
        )
        #expect(manifest.artifacts.map(\.path).contains { $0.hasSuffix("post-layout.cir") })
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func postLayoutSimulationFailureWritesManifest() async throws {
        let root = try makeTemporaryRoot("post-layout-failure")
        defer { removeTemporaryRoot(root) }

        let configuration = makeConfiguration(
            projectRoot: root,
            runID: "post-layout-failure",
            title: "Post-layout failure manifest",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .dcSweep(DCSweepSpec(source: "V1", startValue: 0, stopValue: 1, stepValue: 0)),
            pexIR: smallPEXIR(),
            externalSignoffCommands: try makeSignoffCommands(in: root)
        )

        do {
            _ = try await HeadlessRoundTripService().run(
                schematic: SchematicPreview.voltageDividerViewModel().document,
                configuration: configuration
            )
            Issue.record("Expected post-layout simulation failure")
        } catch {
            #expect(error.localizedDescription.contains("DC sweep step cannot be zero"))
        }

        let manifest = try loadManifest(projectRoot: root, runID: "post-layout-failure")
        assertFailureManifest(
            manifest,
            failedStage: "post-layout-simulation",
            skippedStages: [],
            isReadyForPEX: true
        )
        #expect(manifest.stages.first { $0.name == "pex-injection" }?.status == .passed)
    }

    private struct RoundTripOutput {
        var result: HeadlessRoundTripService.Result
        var projectRoot: URL
    }

    @MainActor
    private func runRoundTrip(
        rootName: String,
        runID: String,
        title: String,
        schematic: SchematicDocument,
        testbench: Testbench,
        postLayoutCommand: AnalysisCommand,
        pexIR: PEXParasiticIR,
        oracleProbes: [String]? = nil
    ) async throws -> RoundTripOutput {
        let root = try makeTemporaryRoot(rootName)
        let configuration = makeConfiguration(
            projectRoot: root,
            runID: runID,
            title: title,
            testbench: testbench,
            postLayoutCommand: postLayoutCommand,
            pexIR: pexIR,
            externalSignoffCommands: try makeSignoffCommands(in: root),
            oracleProbes: oracleProbes
        )

        do {
            let result = try await HeadlessRoundTripService().run(
                schematic: schematic,
                configuration: configuration
            )
            return RoundTripOutput(result: result, projectRoot: root)
        } catch {
            recordRoundTripFailure(projectRoot: root, runID: runID)
            do {
                let preserved = URL(filePath: "/tmp/rt-fail-\(runID)-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: root, to: preserved)
                Issue.record("Preserved failing project at \(preserved.path)")
            } catch {
                Issue.record("Could not preserve failing project: \(error)")
            }
            removeTemporaryRoot(root)
            throw error
        }
    }

    private func assertCompletedRoundTrip(_ roundTrip: RoundTripOutput) throws {
        defer { removeTemporaryRoot(roundTrip.projectRoot) }

        let result = roundTrip.result

        if !result.verification.isReadyForPEX {
            Issue.record("DRC: \(String(describing: result.verification.drc))")
            Issue.record("LVS: \(String(describing: result.verification.lvs))")
        }

        #expect(result.manifest.isRoundTripComplete)
        #expect(result.manifest.isReadyForPEX)
        #expect(result.manifest.bottleneckSummary?.failedStageName == nil)
        #expect(result.manifest.bottleneckSummary?.longestStageName != nil)
        #expect((result.manifest.bottleneckSummary?.totalMeasuredDurationSeconds ?? 0) > 0)
        #expect(result.verification.isReadyForPEX)
        #expect(result.verification.drc.passed)
        #expect(result.externalSignoff?.isReadyForPEX == true)
        #expect(result.preLayoutResult.status == .completed)
        #expect(result.postLayoutResult.status == .completed)
        #expect(Set(result.manifest.stages.map(\.name)).isSuperset(of: [
            "input-artifact-capture",
            "net-extraction",
            "netlist-generation",
            "pre-layout-simulation",
            "auto-layout",
            "pre-pex-verification",
            "pex-injection",
            "post-layout-simulation",
        ]))
        #expect(result.manifest.stages.allSatisfy { $0.status == .passed })
        #expect(result.manifest.stages.filter { $0.status != .skipped }.allSatisfy { ($0.durationSeconds ?? -1) >= 0 })
        #expect(FileManager.default.fileExists(atPath: result.manifestURL.path(percentEncoded: false)))

        let artifactPaths = result.manifest.artifacts.map(\.path)
        #expect(artifactPaths.allSatisfy { !$0.hasPrefix("/") })
        #expect(result.manifest.artifacts.allSatisfy { $0.sha256.count == 64 })
        #expect(result.manifest.artifacts.allSatisfy { $0.byteCount > 0 })
        #expect(artifactPaths.contains { $0.hasSuffix("pre-layout.cir") })
        #expect(artifactPaths.contains { $0.hasSuffix("pre-layout-simulation.json") })
        #expect(artifactPaths.contains { $0.hasSuffix("pre-layout-waveform.csv") })
        #expect(artifactPaths.contains { $0.hasSuffix("post-layout.cir") })
        #expect(artifactPaths.contains { $0.hasSuffix("post-layout-simulation.json") })
        #expect(artifactPaths.contains { $0.hasSuffix("post-layout-waveform.csv") })
        #expect(artifactPaths.contains { $0.hasSuffix("post-layout-comparison.json") })
        #expect(artifactPaths.contains { $0.hasSuffix("drc-mock-drc.log") })
        #expect(artifactPaths.contains { $0.hasSuffix("lvs-mock-lvs.log") })
        #expect(artifactPaths.contains { $0.hasSuffix("external-signoff-review.json") })
        #expect(result.manifest.artifacts.contains {
            $0.kind == "external-signoff-review"
                && $0.sourcePath?.hasSuffix(".xcircuite/signoff/external-signoff-review.json") == true
                && $0.path.contains("input-artifacts/signoff/")
        })
        for artifact in result.manifest.artifacts {
            let artifactURL = artifactURL(path: artifact.path, manifestURL: result.manifestURL)
            let digest = try RoundTripArtifactDigest.compute(url: artifactURL)
            #expect(artifact.sha256 == digest.sha256)
            #expect(artifact.byteCount == digest.byteCount)
        }

        let comparisonURL = try #require(result.manifest.artifacts.first {
            $0.kind == "post-layout-comparison"
        }).path
        let comparisonData = try Data(contentsOf: artifactURL(
            path: comparisonURL,
            manifestURL: result.manifestURL
        ))
        let comparison = try JSONDecoder().decode(PostLayoutComparisonReport.self, from: comparisonData)
        #expect(comparison.status == "compared")
        #expect(!comparison.comparedVariables.isEmpty)

        let manifestData = try Data(contentsOf: result.manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(HeadlessRoundTripService.Manifest.self, from: manifestData)
        #expect(manifest == result.manifest)

        let review = try ExternalSignoffReviewStore().load(forProjectAt: roundTrip.projectRoot)
        #expect(review.approvedBy == "layout-reviewer")
        #expect(review.isReadyForPEX)
    }

    private func assertFailureManifest(
        _ manifest: HeadlessRoundTripService.Manifest,
        failedStage: String,
        skippedStages: [String],
        isReadyForPEX: Bool
    ) {
        #expect(!manifest.isRoundTripComplete)
        #expect(manifest.isReadyForPEX == isReadyForPEX)
        #expect(manifest.stages.first { $0.name == failedStage }?.status == .failed)
        #expect(manifest.bottleneckSummary?.failedStageName == failedStage)
        #expect(manifest.bottleneckSummary?.recommendations.isEmpty == false)
        for skippedStage in skippedStages {
            #expect(manifest.stages.first { $0.name == skippedStage }?.status == .skipped)
        }
        #expect(manifest.artifacts.first?.path.isEmpty == false)
    }

    @MainActor
    private func expectInvalidDesign(
        _ message: String,
        operation: @MainActor () async throws -> Void
    ) async throws {
        do {
            try await operation()
            Issue.record("Expected invalid design error")
        } catch StudioError.invalidDesign(let actualMessage) {
            #expect(actualMessage == message)
        } catch {
            Issue.record("Expected invalid design error, got \(error)")
        }
    }

    private func makeConfiguration(
        projectRoot: URL,
        runID: String,
        title: String,
        testbench: Testbench,
        postLayoutCommand: AnalysisCommand,
        pexIR: PEXParasiticIR,
        designArtifactPaths: [String] = [],
        pexArtifactPaths: [String] = [],
        postLayoutComparisonLimits: PostLayoutComparisonLimits? = nil,
        externalSignoffCommands: [ExternalSignoffCommand] = [],
        externalSignoffReview: ExternalSignoffReview? = nil,
        oracleProbes: [String]? = nil
    ) -> HeadlessRoundTripService.Configuration {
        HeadlessRoundTripService.Configuration(
            projectRoot: projectRoot,
            runID: runID,
            title: title,
            testbench: testbench,
            postLayoutCommand: postLayoutCommand,
            pexIR: pexIR,
            designArtifactPaths: designArtifactPaths,
            pexArtifactPaths: pexArtifactPaths,
            postLayoutComparisonLimits: postLayoutComparisonLimits,
            externalSignoffCommands: externalSignoffCommands,
            externalSignoffReview: externalSignoffReview,
            approvedBy: "layout-reviewer",
            approvedAt: Date(timeIntervalSince1970: 2_000),
            createdAt: Date(timeIntervalSince1970: 1_000),
            oracleProbes: oracleProbes
        )
    }

    private func smallPEXIR() -> PEXParasiticIR {
        PEXParasiticIR(
            version: "1.0",
            cornerID: "tt_25c_1v0",
            elements: [
                PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 0.5),
                PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 1e-15),
            ]
        )
    }

    private func makeSignoffCommands(
        in root: URL,
        drcContents: String = """
        #!/bin/sh
        printf '[INFO] rule=DRC_CLEAN message="clean drc"\\n'
        printf 'SIGNOFF_RESULT status=pass\\n'
        exit 0
        """,
        lvsContents: String = """
        #!/bin/sh
        printf '[INFO] rule=LVS_MATCH message="clean lvs"\\n'
        printf 'SIGNOFF_RESULT status=pass\\n'
        exit 0
        """
    ) throws -> [ExternalSignoffCommand] {
        let drcExecutable = try writeExecutable(named: "mock-drc", in: root, contents: drcContents)
        let lvsExecutable = try writeExecutable(named: "mock-lvs", in: root, contents: lvsContents)
        return [
            ExternalSignoffCommand(
                kind: .drc,
                toolName: "mock-drc",
                executablePath: drcExecutable.path(percentEncoded: false)
            ),
            ExternalSignoffCommand(
                kind: .lvs,
                toolName: "mock-lvs",
                executablePath: lvsExecutable.path(percentEncoded: false)
            ),
        ]
    }

    private func loadManifest(
        projectRoot: URL,
        runID: String
    ) throws -> HeadlessRoundTripService.Manifest {
        let manifestURL = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: runID)
            .appending(path: "round-trip-manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HeadlessRoundTripService.Manifest.self, from: data)
    }

    private func recordRoundTripFailure(projectRoot: URL, runID: String) {
        do {
            let manifest = try loadManifest(projectRoot: projectRoot, runID: runID)
            let stages = manifest.stages.map { stage in
                [
                    stage.name,
                    stage.status.rawValue,
                    stage.message ?? "",
                ].joined(separator: ":")
            }.joined(separator: " | ")
            Issue.record("Round-trip failure stages: \(stages)")
            if let verification = try readPrePEXVerification(from: manifest, projectRoot: projectRoot) {
                Issue.record("Pre-PEX DRC: \(String(describing: verification.drc))")
                Issue.record("Pre-PEX LVS: \(String(describing: verification.lvs))")
            }
            recordDRCViolations(from: manifest, projectRoot: projectRoot)
        } catch {
            Issue.record("Round-trip failure manifest could not be loaded: \(error)")
        }
    }

    private func readPrePEXVerification(
        from manifest: HeadlessRoundTripService.Manifest,
        projectRoot: URL
    ) throws -> DesignFlowVerificationReport? {
        guard let artifact = manifest.artifacts.first(where: { $0.kind == "physical-verification-report" }) else {
            return nil
        }
        let url = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: manifest.runID)
            .appending(path: artifact.path)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DesignFlowVerificationReport.self, from: data)
    }

    private func recordDRCViolations(from manifest: HeadlessRoundTripService.Manifest, projectRoot: URL) {
        do {
            guard let artifact = manifest.artifacts.first(where: { $0.kind == "layout-document" }) else {
                return
            }
            let url = projectRoot
                .appending(path: ".xcircuite")
                .appending(path: "runs")
                .appending(path: manifest.runID)
                .appending(path: artifact.path)
            let data = try Data(contentsOf: url)
            let layout = try JSONDecoder().decode(LayoutDocument.self, from: data)
            let result = LayoutDRCService().run(document: layout, tech: .sampleProcess())
            let summary = result.violations.prefix(20).map { violation in
                let layerName = violation.layer.map { "\($0.name)/\($0.purpose)" } ?? "<no-layer>"
                return [
                    violation.kind.rawValue,
                    layerName,
                    violation.message,
                    String(describing: violation.region),
                ].joined(separator: " | ")
            }.joined(separator: " || ")
            Issue.record("Pre-PEX DRC details: \(summary)")
        } catch {
            Issue.record("Pre-PEX DRC details could not be loaded: \(error)")
        }
    }

    private func writeManifest(
        _ manifest: HeadlessRoundTripService.Manifest,
        projectRoot: URL,
        runID: String
    ) throws {
        let runDirectory = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: runID)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: runDirectory.appending(path: "round-trip-manifest.json"))
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioHeadlessRoundTripServiceTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }

    private func writeExecutable(named name: String, in root: URL, contents: String) throws -> URL {
        let url = root.appending(path: name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path(percentEncoded: false)
        )
        return url
    }

    private func artifactURL(path: String, projectRoot: URL, runID: String) -> URL {
        let manifestURL = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: runID)
            .appending(path: "round-trip-manifest.json")
        return artifactURL(path: path, manifestURL: manifestURL)
    }

    private func artifactURL(path: String, manifestURL: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(filePath: path)
        }
        return manifestURL.deletingLastPathComponent().appending(path: path)
    }
}
