import Foundation
import Testing
import LayoutCore
@testable import CircuitStudioApp
@testable import CircuitStudioCore
@testable import SchematicEditor

@Suite("DesignFlowService Tests")
struct DesignFlowServiceTests {
    @Test
    @MainActor
    func unifiedFixtureLibraryProvidesCLIAndAPIFixtures() throws {
        #expect(DesignFlowFixtureLibrary.defaultFixtureName == "voltage-divider")
        #expect(DesignFlowFixtureLibrary.fixtureNames == [
            "cmos-inverter",
            "rc-low-pass",
            "voltage-divider",
            "resistor-divider",
        ])

        for name in DesignFlowFixtureLibrary.fixtureNames {
            let fixture = try DesignFlowFixtureLibrary.fixture(named: name)
            #expect(fixture.name == name)
            #expect(!fixture.schematic.components.isEmpty)
            #expect(!fixture.testbench.analysisCommands.isEmpty)
            #expect(!fixture.pexIR.elements.isEmpty)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIListsFixturesGeneratesNetlistAndRunsSimulation() async throws {
        let service = DesignFlowService()
        let fixtureList = try await service.execute(.listFixtures())

        #expect(fixtureList.fixtureNames == DesignFlowFixtureLibrary.fixtureNames)

        let netlist = try await service.execute(DesignFlowCommand(
            kind: .generateFixtureNetlist,
            fixtureName: "voltage-divider"
        ))
        #expect(netlist.fixtureName == "voltage-divider")
        #expect(netlist.netlist?.contains(".op") == true)

        let simulation = try await service.execute(DesignFlowCommand(
            kind: .runFixtureSimulation,
            fixtureName: "voltage-divider"
        ))
        #expect(simulation.simulationStatus == "completed")
        #expect(simulation.netlist?.contains(".op") == true)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func technologyPackageLoadsAndInjectsProcessConfig() async throws {
        let packageURL = try rootFixtureURL("technology-package", extension: "json")
        let service = DesignFlowService()

        let packageResult = try await service.execute(DesignFlowCommand(
            kind: .loadTechnologyPackage,
            technologyPackagePath: packageURL.path(percentEncoded: false)
        ))
        #expect(packageResult.technologyPackageID == "virtual45-golden-flow")
        #expect(packageResult.validationDiagnostics?.isEmpty == true)

        let package = try service.loadTechnologyPackage(packageURL)
        #expect(package.processConfiguration?.effectiveParameters()["vdd"] == 1.0)
        #expect(package.processConfiguration?.resolveIncludes == true)
        let tech = try TechnologyPackageLayoutTechResolver().resolve(package: package)
        #expect(tech.layerDefinition(for: .init(name: "ACTIVE", purpose: "drawing")) != nil)

        let netlist = try await service.execute(DesignFlowCommand(
            kind: .generateFixtureNetlist,
            fixtureName: "voltage-divider",
            technologyPackagePath: packageURL.path(percentEncoded: false)
        ))
        #expect(netlist.technologyPackageID == "virtual45-golden-flow")
        #expect(netlist.netlist?.contains(".lib \"models/core.lib\" tt") == true)
        #expect(netlist.netlist?.contains(".include \"models/passives.inc\"") == true)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIRunsFixtureRoundTripWithTechnologyPackage() async throws {
        let packageURL = try rootFixtureURL("technology-package", extension: "json")
        let root = try makeTemporaryRoot("technology-package-round-trip")
        defer { removeTemporaryRoot(root) }

        let roundTrip = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .runFixtureRoundTrip,
            fixtureName: "voltage-divider",
            projectRootPath: root.path(percentEncoded: false),
            runID: "technology-package-voltage-divider",
            approveSignoff: true,
            maxAbsoluteDelta: 1.0e-3,
            maxRelativeDelta: 2.0,
            technologyPackagePath: packageURL.path(percentEncoded: false)
        ))

        #expect(roundTrip.readyForPEX == true)
        #expect(roundTrip.technologyPackageID == "virtual45-golden-flow")
        #expect(roundTrip.pexCornerID == "tt_25c_1v0")
        let manifest = try #require(roundTrip.manifestPath).loadManifest()
        #expect(manifest.artifacts.contains { $0.kind == "design-spec" && $0.path.hasSuffix("technology-package.json") })
        #expect(manifest.artifacts.contains { $0.kind == "external-signoff-log" })
        #expect(manifest.artifacts.contains { $0.kind == "pex-artifact" })
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIRunsDesignSpecNetlistSimulationAndRoundTrip() async throws {
        let root = try makeTemporaryRoot("design-spec-round-trip")
        defer { removeTemporaryRoot(root) }
        let specURL = root.appending(path: "agent-resistor-divider.json")
        let embeddedLimits = PostLayoutComparisonLimits(maxAbsoluteDelta: 1.0e-3, maxRelativeDelta: 2.0)
        try writeDesignSpec(agentResistorDividerSpec(postLayoutComparisonLimits: embeddedLimits), to: specURL)

        let service = DesignFlowService()
        let netlist = try await service.execute(DesignFlowCommand(
            kind: .generateDesignNetlist,
            designSpecPath: specURL.path(percentEncoded: false)
        ))
        #expect(netlist.designName == "agent-resistor-divider")
        #expect(netlist.netlist?.contains("R1 vin out 1k") == true)
        #expect(netlist.netlist?.contains(".op") == true)

        let simulation = try await service.execute(DesignFlowCommand(
            kind: .runDesignSimulation,
            designSpecPath: specURL.path(percentEncoded: false)
        ))
        #expect(simulation.designName == "agent-resistor-divider")
        #expect(simulation.simulationStatus == "completed")

        let roundTrip = try await service.execute(DesignFlowCommand(
            kind: .runDesignRoundTrip,
            designSpecPath: specURL.path(percentEncoded: false),
            projectRootPath: root.path(percentEncoded: false),
            runID: "agent-resistor-divider-run",
            approveSignoff: true
        ))
        #expect(roundTrip.designName == "agent-resistor-divider")
        #expect(roundTrip.runID == "agent-resistor-divider-run")
        #expect(roundTrip.readyForPEX == true)
        #expect(roundTrip.comparisonLimitsConfigured == true)
        #expect(roundTrip.manifestPath?.hasSuffix("round-trip-manifest.json") == true)
        let manifest = try #require(roundTrip.manifestPath).loadManifest()
        #expect(!manifest.artifacts.contains { $0.kind == "external-signoff-log" })
        #expect(!manifest.stages.contains { $0.name == "external-signoff" })
        #expect(manifest.artifacts.contains {
            $0.kind == "design-spec"
                && $0.path.contains("input-artifacts/design/")
                && $0.sourcePath == specURL.path(percentEncoded: false)
        })
        let comparisonPath = try #require(manifest.artifacts.first { $0.kind == "post-layout-comparison" }?.path)
        #expect(!comparisonPath.hasPrefix("/"))
        let comparisonData = try Data(contentsOf: artifactURL(
            path: comparisonPath,
            manifestPath: try #require(roundTrip.manifestPath)
        ))
        let comparison = try JSONDecoder().decode(PostLayoutComparisonReport.self, from: comparisonData)
        #expect(comparison.comparisonLimits == embeddedLimits)

        let encoded = try JSONEncoder().encode(roundTrip)
        let decoded = try JSONDecoder().decode(DesignFlowCommandResult.self, from: encoded)
        #expect(decoded.designName == roundTrip.designName)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIAppliesDesignEditAndWritesAuditArtifacts() async throws {
        let root = try makeTemporaryRoot("design-edit")
        defer { removeTemporaryRoot(root) }
        let inputURL = root.appending(path: "input.json")
        let scriptURL = root.appending(path: "edits.json")
        let outputURL = root.appending(path: "edited.json")
        try writeDesignSpec(agentResistorDividerSpec(), to: inputURL)
        try writeDesignEditScript(DesignFlowDesignEditScript(edits: [
            DesignFlowDesignEdit(
                kind: .setComponentParameters,
                componentName: "R2",
                parameters: ["r": 3000]
            ),
            DesignFlowDesignEdit(
                kind: .renameComponent,
                componentName: "R2",
                newComponentName: "RLOAD"
            ),
        ]), to: scriptURL)

        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .applyDesignEdit,
            designSpecPath: inputURL.path(percentEncoded: false),
            projectRootPath: root.path(percentEncoded: false),
            runID: "edit-run",
            editScriptPath: scriptURL.path(percentEncoded: false),
            outputDesignSpecPath: outputURL.path(percentEncoded: false)
        ))

        #expect(result.designSpecPath == outputURL.path(percentEncoded: false))
        let actionLogPath = try #require(result.actionLogPath)
        let diffPath = try #require(result.designDiffPath)
        #expect(FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: actionLogPath))
        #expect(FileManager.default.fileExists(atPath: diffPath))

        let editedSpec = try DesignFlowService().loadDesignSpec(outputURL)
        #expect(editedSpec.components.contains {
            $0.name == "RLOAD" && $0.parameters["r"] == 3000
        })
        #expect(editedSpec.nets.contains {
            $0.terminals.contains(DesignFlowDesignSpec.Terminal(component: "RLOAD", port: "pos"))
        })

        let simulation = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .runDesignSimulation,
            designSpecPath: outputURL.path(percentEncoded: false)
        ))
        #expect(simulation.simulationStatus == "completed")
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIAppliesLayoutEditAndWritesAuditArtifacts() async throws {
        let root = try makeTemporaryRoot("layout-edit")
        defer { removeTemporaryRoot(root) }
        let inputURL = root.appending(path: "layout.json")
        let scriptURL = root.appending(path: "layout-edits.json")
        let outputURL = root.appending(path: "edited-layout.json")
        let cellID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let netID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let shapeID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let pinID = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
        let labelID = UUID(uuidString: "00000000-0000-0000-0000-000000000105")!
        let layout = LayoutDocument(
            name: "AgentLayout",
            cells: [LayoutCell(id: cellID, name: "TOP")],
            topCellID: cellID
        )
        try writeLayoutDocument(layout, to: inputURL)
        try writeLayoutEditScript(DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(
                kind: .addNet,
                cellName: "TOP",
                netID: netID,
                netName: "out"
            ),
            DesignFlowLayoutEdit(
                kind: .addRectShape,
                cellName: "TOP",
                elementID: shapeID,
                netName: "out",
                layerName: "M1",
                x: 0,
                y: 0,
                width: 2,
                height: 1,
                properties: ["lvs.net": "out"]
            ),
            DesignFlowLayoutEdit(
                kind: .addPin,
                cellName: "TOP",
                elementID: pinID,
                netName: "out",
                layerName: "M1",
                x: 1,
                y: 0.5,
                width: 0.5,
                height: 0.5,
                pinName: "OUT"
            ),
            DesignFlowLayoutEdit(
                kind: .addLabel,
                cellName: "TOP",
                elementID: labelID,
                netName: "out",
                layerName: "M1",
                x: 1,
                y: 0.5,
                labelText: "out"
            ),
        ]), to: scriptURL)

        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .applyLayoutEdit,
            projectRootPath: root.path(percentEncoded: false),
            runID: "layout-edit-run",
            editScriptPath: scriptURL.path(percentEncoded: false),
            layoutDocumentPath: inputURL.path(percentEncoded: false),
            outputLayoutDocumentPath: outputURL.path(percentEncoded: false)
        ))

        #expect(result.layoutDocumentPath == outputURL.path(percentEncoded: false))
        let actionLogPath = try #require(result.actionLogPath)
        let diffPath = try #require(result.layoutDiffPath)
        #expect(FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: actionLogPath))
        #expect(FileManager.default.fileExists(atPath: diffPath))

        let edited = try DesignFlowService().loadLayoutDocument(outputURL)
        let top = try #require(edited.cells.first)
        #expect(top.nets.contains { $0.name == "out" && $0.id == netID })
        #expect(top.shapes.contains { $0.id == shapeID && $0.netID == netID })
        #expect(top.pins.contains { $0.id == pinID && $0.name == "OUT" && $0.netID == netID })
        #expect(top.labels.contains { $0.id == labelID && $0.text == "out" && $0.netID == netID })

        let diff = try loadLayoutDiff(URL(filePath: diffPath))
        #expect(diff.addedNets == ["TOP:out"])
        #expect(diff.addedShapes == [shapeID])
        #expect(diff.addedPins == ["TOP:OUT"])
        #expect(diff.addedLabels == ["TOP:out"])
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIRunsLayoutTrustAndWritesArtifacts() async throws {
        let root = try makeTemporaryRoot("layout-trust")
        defer { removeTemporaryRoot(root) }
        let layoutURL = root.appending(path: "layout.json")
        let cellID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let netID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let shapeID = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!
        let layout = LayoutDocument(
            name: "TrustedLayout",
            cells: [
                LayoutCell(
                    id: cellID,
                    name: "TOP",
                    shapes: [
                        LayoutShape(
                            id: shapeID,
                            layer: LayoutLayerID(name: "M1", purpose: "drawing"),
                            netID: netID,
                            geometry: .rect(LayoutRect(
                                origin: LayoutPoint(x: 0, y: 0),
                                size: LayoutSize(width: 2, height: 1)
                            ))
                        ),
                    ],
                    nets: [LayoutNet(id: netID, name: "out")]
                ),
            ],
            topCellID: cellID
        )
        try writeLayoutDocument(layout, to: layoutURL)

        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .runLayoutTrust,
            projectRootPath: root.path(percentEncoded: false),
            runID: "layout-trust-run",
            layoutDocumentPath: layoutURL.path(percentEncoded: false)
        ))

        #expect(result.readyForPEX == true)
        #expect(result.layoutTrustReport?.passed == true)
        #expect(result.layoutTrustReport?.ownedShapeCount == 1)
        let reportPath = try #require(result.layoutTrustReportPath)
        #expect(FileManager.default.fileExists(atPath: reportPath))
        #expect(reportPath.hasSuffix(".xcircuite/runs/layout-trust-run/layout/layout-trust-report.json"))
    }

    @Test(.timeLimit(.minutes(1)))
    func layoutEditRejectsRemovingReferencedNet() throws {
        let cellID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let netID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
        let shapeID = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!
        let layout = LayoutDocument(
            name: "ReferencedNetLayout",
            cells: [
                LayoutCell(
                    id: cellID,
                    name: "TOP",
                    shapes: [
                        LayoutShape(
                            id: shapeID,
                            layer: LayoutLayerID(name: "M1", purpose: "drawing"),
                            netID: netID,
                            geometry: .rect(LayoutRect(
                                origin: LayoutPoint(x: 0, y: 0),
                                size: LayoutSize(width: 1, height: 1)
                            ))
                        ),
                    ],
                    nets: [LayoutNet(id: netID, name: "out")]
                ),
            ],
            topCellID: cellID
        )
        let script = DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(kind: .removeNet, cellName: "TOP", netName: "out"),
        ])

        #expect(throws: DesignFlowLayoutEditError.netInUse("out")) {
            try DesignFlowLayoutEditService().apply(script: script, to: layout)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIRunsVerificationOnlyAndWritesReportArtifact() async throws {
        let root = try makeTemporaryRoot("verification-only")
        defer { removeTemporaryRoot(root) }
        let layoutURL = root.appending(path: "layout.json")
        let designUnitURL = root.appending(path: "design-unit.json")
        let service = DesignFlowService()
        let fixture = try DesignFlowFixtureLibrary.fixture(named: "voltage-divider")
        let layoutOutput = try service.generateLayout(DesignFlowLayoutGenerationRequest(
            schematic: fixture.schematic,
            catalog: .standard()
        ))
        try writeLayoutDocument(layoutOutput.document, to: layoutURL)
        try writeDesignUnit(layoutOutput.designUnit, to: designUnitURL)

        let result = try await service.execute(DesignFlowCommand(
            kind: .runVerification,
            fixtureName: "voltage-divider",
            projectRootPath: root.path(percentEncoded: false),
            runID: "verification-run",
            layoutDocumentPath: layoutURL.path(percentEncoded: false),
            designUnitPath: designUnitURL.path(percentEncoded: false)
        ))

        #expect(result.fixtureName == "voltage-divider")
        #expect(result.readyForPEX == true)
        let reportPath = try #require(result.verificationReportPath)
        let layoutTrustReportPath = try #require(result.layoutTrustReportPath)
        #expect(FileManager.default.fileExists(atPath: reportPath))
        #expect(FileManager.default.fileExists(atPath: layoutTrustReportPath))
        #expect(reportPath.hasSuffix(".xcircuite/runs/verification-run/reports/physical-verification.json"))
        #expect(layoutTrustReportPath.hasSuffix(".xcircuite/runs/verification-run/layout/layout-trust-report.json"))
        #expect(result.verificationReport?.status == "passed")
        #expect(result.verificationReport?.layoutTrust?.passed == true)
        #expect(result.layoutTrustReport?.passed == true)
        #expect(result.verificationReport?.drc.passed == true)
        #expect(result.verificationReport?.lvs.passed == true)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIApprovesGateAndWritesAuditRecord() async throws {
        let root = try makeTemporaryRoot("gate-approval")
        defer { removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: "approval-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try Data(#"{"status":"compared","gateStatus":"passed"}"#.utf8).write(to: comparisonURL, options: .atomic)
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeHeadlessManifest(HeadlessRoundTripService.Manifest(
            runID: "approval-run",
            title: "Approval run",
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            isRoundTripComplete: true,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "post-layout-comparison", status: .passed),
            ],
            artifacts: [
                try roundTripArtifact(
                    kind: "post-layout-comparison",
                    url: comparisonURL
                ),
            ]
        ), to: manifestURL)

        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .approveGate,
            projectRootPath: root.path(percentEncoded: false),
            runID: "approval-run",
            roundTripManifestPath: manifestURL.path(percentEncoded: false),
            approvalGateID: .postLayoutComparison,
            approvalReviewer: "layout-reviewer",
            approvalPolicy: "strict-post-layout-comparison",
            approvalNote: "Reviewed comparison artifact",
            waiverIDs: ["W-007"]
        ))

        let recordPath = try #require(result.approvalRecordPath)
        #expect(FileManager.default.fileExists(atPath: recordPath))
        #expect(result.approvalRecord?.gateID == .postLayoutComparison)
        #expect(result.approvalRecord?.decision == .approved)
        #expect(result.approvalRecord?.reviewer == "layout-reviewer")
        #expect(result.approvalRecord?.waiverIDs == ["W-007"])
        #expect(result.approvalRecord?.targetArtifactKind == "post-layout-comparison")
        #expect(result.approvalRecord?.targetArtifactPathBase == .runDirectory)
        #expect(result.approvalRecord?.targetArtifactPath == comparisonURL.lastPathComponent)
        #expect(result.approvalRecord?.targetArtifactSHA256.count == 64)
        #expect(result.approvalRecord?.manifestSHA256?.count == 64)
        #expect(result.approvalRecord?.lineage?.parentRunID == "approval-run")

        let review = try RoundTripReviewService().loadReview(manifestURL: manifestURL)
        #expect(review.approvals.count == 1)
        #expect(review.approvals.first?.gateID == .postLayoutComparison)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIRejectsEscapingGateApprovalArtifactPath() async throws {
        let root = try makeTemporaryRoot("gate-approval-escape")
        defer { removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: "approval-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let outsideURL = runDirectory
            .deletingLastPathComponent()
            .appending(path: "outside-comparison.json")
        try Data(#"{"status":"compared","gateStatus":"passed"}"#.utf8).write(to: outsideURL, options: .atomic)

        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeHeadlessManifest(HeadlessRoundTripService.Manifest(
            runID: "approval-run",
            title: "Escaping approval run",
            createdAt: Date(timeIntervalSince1970: 1_700_000_150),
            isRoundTripComplete: true,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "post-layout-comparison", status: .passed),
            ],
            artifacts: [
                try roundTripArtifact(
                    kind: "post-layout-comparison",
                    url: outsideURL,
                    path: "../outside-comparison.json"
                ),
            ]
        ), to: manifestURL)

        do {
            _ = try await DesignFlowService().execute(DesignFlowCommand(
                kind: .approveGate,
                projectRootPath: root.path(percentEncoded: false),
                runID: "approval-run",
                roundTripManifestPath: manifestURL.path(percentEncoded: false),
                approvalGateID: .postLayoutComparison,
                approvalReviewer: "layout-reviewer"
            ))
            Issue.record("Expected escaping artifact path to fail gate approval.")
        } catch let error as FlowRunGovernanceError {
            if case .invalidArtifactPath(let message) = error {
                #expect(message.contains("escapes"))
            } else {
                Issue.record("Expected invalid artifact path error, got \(error).")
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIRejectsAbsoluteManifestArtifactPath() async throws {
        let root = try makeTemporaryRoot("gate-approval-absolute-artifact")
        defer { removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: "approval-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try Data(#"{"status":"compared","gateStatus":"passed"}"#.utf8).write(to: comparisonURL, options: .atomic)
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeHeadlessManifest(HeadlessRoundTripService.Manifest(
            runID: "approval-run",
            title: "Absolute artifact approval run",
            createdAt: Date(timeIntervalSince1970: 1_700_000_175),
            isRoundTripComplete: true,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "post-layout-comparison", status: .passed),
            ],
            artifacts: [
                try roundTripArtifact(
                    kind: "post-layout-comparison",
                    url: comparisonURL,
                    path: comparisonURL.path(percentEncoded: false)
                ),
            ]
        ), to: manifestURL)

        do {
            _ = try await DesignFlowService().execute(DesignFlowCommand(
                kind: .approveGate,
                projectRootPath: root.path(percentEncoded: false),
                runID: "approval-run",
                roundTripManifestPath: manifestURL.path(percentEncoded: false),
                approvalGateID: .postLayoutComparison,
                approvalReviewer: "layout-reviewer"
            ))
            Issue.record("Expected absolute manifest artifact path to fail gate approval.")
        } catch let error as FlowRunGovernanceError {
            if case .invalidArtifactPath(let message) = error {
                #expect(message.contains("absolute"))
            } else {
                Issue.record("Expected invalid artifact path error, got \(error).")
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIRejectsGateApprovalForInvalidManifestRunID() async throws {
        let root = try makeTemporaryRoot("gate-approval-invalid-run")
        defer { removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: "approval-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try Data(#"{"status":"compared","gateStatus":"passed"}"#.utf8).write(to: comparisonURL, options: .atomic)
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeHeadlessManifest(HeadlessRoundTripService.Manifest(
            runID: "../escape",
            title: "Invalid approval run",
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            isRoundTripComplete: true,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "post-layout-comparison", status: .passed),
            ],
            artifacts: [
                try roundTripArtifact(
                    kind: "post-layout-comparison",
                    url: comparisonURL
                ),
            ]
        ), to: manifestURL)

        do {
            _ = try await DesignFlowService().execute(DesignFlowCommand(
                kind: .approveGate,
                projectRootPath: root.path(percentEncoded: false),
                roundTripManifestPath: manifestURL.path(percentEncoded: false),
                approvalGateID: .postLayoutComparison,
                approvalReviewer: "layout-reviewer"
            ))
            Issue.record("Expected invalid manifest run ID to fail gate approval.")
        } catch let error as FlowRunGovernanceError {
            #expect(error == .invalidRunID("../escape"))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIRejectsPrePEXApprovalWithoutVerificationArtifact() async throws {
        let root = try makeTemporaryRoot("gate-approval-missing-pre-pex")
        defer { removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: "approval-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try Data(#"{"status":"compared","gateStatus":"passed"}"#.utf8).write(to: comparisonURL, options: .atomic)
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeHeadlessManifest(HeadlessRoundTripService.Manifest(
            runID: "approval-run",
            title: "Missing pre-PEX approval target",
            createdAt: Date(timeIntervalSince1970: 1_700_000_300),
            isRoundTripComplete: true,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "pre-pex-verification", status: .passed),
                HeadlessRoundTripService.Stage(name: "post-layout-comparison", status: .passed),
            ],
            artifacts: [
                try roundTripArtifact(
                    kind: "post-layout-comparison",
                    url: comparisonURL
                ),
            ]
        ), to: manifestURL)

        do {
            _ = try await DesignFlowService().execute(DesignFlowCommand(
                kind: .approveGate,
                projectRootPath: root.path(percentEncoded: false),
                runID: "approval-run",
                roundTripManifestPath: manifestURL.path(percentEncoded: false),
                approvalGateID: .prePEXVerification,
                approvalReviewer: "layout-reviewer"
            ))
            Issue.record("Expected missing pre-PEX verification artifact to fail gate approval.")
        } catch let error as FlowRunGovernanceError {
            #expect(error == .missingArtifactForGate(.prePEXVerification))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIApprovesPhysicalVerificationReportGates() async throws {
        let root = try makeTemporaryRoot("gate-approval-physical-verification")
        defer { removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: "approval-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let verificationURL = runDirectory.appending(path: "physical-verification.json")
        try Data(#"{"status":"passed","readyForPEX":true}"#.utf8).write(to: verificationURL, options: .atomic)
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try writeHeadlessManifest(HeadlessRoundTripService.Manifest(
            runID: "approval-run",
            title: "Physical verification approval run",
            createdAt: Date(timeIntervalSince1970: 1_700_000_350),
            isRoundTripComplete: true,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "pre-pex-verification", status: .passed),
            ],
            artifacts: [
                try roundTripArtifact(
                    kind: "physical-verification-report",
                    url: verificationURL
                ),
            ]
        ), to: manifestURL)

        let prePEXResult = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .approveGate,
            projectRootPath: root.path(percentEncoded: false),
            runID: "approval-run",
            roundTripManifestPath: manifestURL.path(percentEncoded: false),
            approvalGateID: .prePEXVerification,
            approvalReviewer: "layout-reviewer"
        ))
        let physicalResult = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .approveGate,
            projectRootPath: root.path(percentEncoded: false),
            runID: "approval-run",
            roundTripManifestPath: manifestURL.path(percentEncoded: false),
            approvalGateID: .physicalVerification,
            approvalReviewer: "layout-reviewer"
        ))

        #expect(prePEXResult.approvalRecord?.targetArtifactPath == verificationURL.lastPathComponent)
        #expect(prePEXResult.approvalRecord?.targetArtifactPathBase == .runDirectory)
        #expect(prePEXResult.approvalRecord?.gateID == .prePEXVerification)
        #expect(physicalResult.approvalRecord?.targetArtifactPath == verificationURL.lastPathComponent)
        #expect(physicalResult.approvalRecord?.targetArtifactPathBase == .runDirectory)
        #expect(physicalResult.approvalRecord?.gateID == .physicalVerification)
        let review = try RoundTripReviewService().loadReview(manifestURL: manifestURL)
        #expect(review.approvals.map(\.gateID).sorted { $0.rawValue < $1.rawValue } == [
            .physicalVerification,
            .prePEXVerification,
        ])
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIRejectsUnsafeDesignSpecNamesAndDuplicateTerminals() async throws {
        let root = try makeTemporaryRoot("invalid-design-spec")
        defer { removeTemporaryRoot(root) }
        let base = agentResistorDividerSpec()
        let service = DesignFlowService()

        let unsafeNameURL = root.appending(path: "unsafe-name.json")
        try writeDesignSpec(DesignFlowDesignSpec(
            name: "../escaped",
            title: base.title,
            components: base.components,
            nets: base.nets,
            analyses: base.analyses,
            pexIR: try base.pexIR?.normalizedCore()
        ), to: unsafeNameURL)

        await #expect(throws: DesignFlowDesignSpecError.invalidDesignName("../escaped")) {
            try await service.execute(DesignFlowCommand(
                kind: .generateDesignNetlist,
                designSpecPath: unsafeNameURL.path(percentEncoded: false)
            ))
        }

        let duplicateTerminalURL = root.appending(path: "duplicate-terminal.json")
        try writeDesignSpec(DesignFlowDesignSpec(
            name: "duplicate-terminal",
            title: base.title,
            components: base.components,
            nets: base.nets + [
                DesignFlowDesignSpec.Net(
                    name: "vin_copy",
                    terminals: [
                        DesignFlowDesignSpec.Terminal(component: "V1", port: "pos"),
                    ]
                ),
            ],
            analyses: base.analyses,
            pexIR: try base.pexIR?.normalizedCore()
        ), to: duplicateTerminalURL)

        await #expect(throws: DesignFlowDesignSpecError.duplicateTerminal(
            component: "V1",
            port: "pos",
            firstNet: "vin",
            secondNet: "vin_copy"
        )) {
            try await service.execute(DesignFlowCommand(
                kind: .generateDesignNetlist,
                designSpecPath: duplicateTerminalURL.path(percentEncoded: false)
            ))
        }

        let unsupportedSchemaURL = root.appending(path: "unsupported-schema.json")
        try writeDesignSpec(DesignFlowDesignSpec(
            name: "unsupported-schema",
            schemaVersion: 2,
            title: base.title,
            components: base.components,
            nets: base.nets,
            analyses: base.analyses,
            pexIR: try base.pexIR?.normalizedCore()
        ), to: unsupportedSchemaURL)

        await #expect(throws: DesignFlowDesignSpecError.unsupportedSchemaVersion(2)) {
            try await service.execute(DesignFlowCommand(
                kind: .generateDesignNetlist,
                designSpecPath: unsupportedSchemaURL.path(percentEncoded: false)
            ))
        }

        let wrongPrefixURL = root.appending(path: "wrong-prefix.json")
        try writeDesignSpec(DesignFlowDesignSpec(
            name: "wrong_prefix",
            title: base.title,
            components: [
                DesignFlowDesignSpec.Component(
                    name: "X1",
                    deviceKindID: "resistor",
                    parameters: ["r": 1_000]
                ),
                DesignFlowDesignSpec.Component(
                    name: "R2",
                    deviceKindID: "resistor",
                    parameters: ["r": 1_000]
                ),
                DesignFlowDesignSpec.Component(
                    name: "V1",
                    deviceKindID: "vsource",
                    parameters: ["dc": 5.0]
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
                        DesignFlowDesignSpec.Terminal(component: "X1", port: "pos"),
                    ]
                ),
            ],
            analyses: base.analyses,
            pexIR: try base.pexIR?.normalizedCore()
        ), to: wrongPrefixURL)

        await #expect(throws: DesignFlowDesignSpecError.invalidComponentPrefix(
            component: "X1",
            deviceKindID: "resistor",
            expectedPrefix: "R"
        )) {
            try await service.execute(DesignFlowCommand(
                kind: .generateDesignNetlist,
                designSpecPath: wrongPrefixURL.path(percentEncoded: false)
            ))
        }

        let unknownParameterURL = root.appending(path: "unknown-parameter.json")
        try writeDesignSpec(DesignFlowDesignSpec(
            name: "unknown_parameter",
            title: base.title,
            components: [
                DesignFlowDesignSpec.Component(
                    name: "R1",
                    deviceKindID: "resistor",
                    parameters: ["resistance": 1_000]
                ),
            ],
            nets: [],
            analyses: base.analyses,
            pexIR: try base.pexIR?.normalizedCore()
        ), to: unknownParameterURL)

        await #expect(throws: DesignFlowDesignSpecError.unknownParameter(
            component: "R1",
            parameter: "resistance"
        )) {
            try await service.execute(DesignFlowCommand(
                kind: .generateDesignNetlist,
                designSpecPath: unknownParameterURL.path(percentEncoded: false)
            ))
        }

        let unknownPresetURL = root.appending(path: "unknown-preset.json")
        try writeDesignSpec(DesignFlowDesignSpec(
            name: "unknown_preset",
            title: base.title,
            components: [
                DesignFlowDesignSpec.Component(
                    name: "M1",
                    deviceKindID: "nmos_l1",
                    parameters: ["w": 1.0e-6, "l": 1.0e-6],
                    modelPresetID: "missing_preset"
                ),
            ],
            nets: [],
            analyses: base.analyses,
            pexIR: try base.pexIR?.normalizedCore()
        ), to: unknownPresetURL)

        await #expect(throws: DesignFlowDesignSpecError.unknownModelPresetID("missing_preset")) {
            try await service.execute(DesignFlowCommand(
                kind: .generateDesignNetlist,
                designSpecPath: unknownPresetURL.path(percentEncoded: false)
            ))
        }

        let missingRequiredParameterURL = root.appending(path: "missing-required-parameter.json")
        try writeDesignSpec(DesignFlowDesignSpec(
            name: "missing_required_parameter",
            title: base.title,
            components: [
                DesignFlowDesignSpec.Component(
                    name: "R1",
                    deviceKindID: "resistor"
                ),
            ],
            nets: [],
            analyses: base.analyses,
            pexIR: try base.pexIR?.normalizedCore()
        ), to: missingRequiredParameterURL)

        await #expect(throws: DesignFlowDesignSpecError.missingRequiredParameter(
            component: "R1",
            parameter: "r"
        )) {
            try await service.execute(DesignFlowCommand(
                kind: .generateDesignNetlist,
                designSpecPath: missingRequiredParameterURL.path(percentEncoded: false)
            ))
        }

        let outOfRangeParameterURL = root.appending(path: "out-of-range-parameter.json")
        try writeDesignSpec(DesignFlowDesignSpec(
            name: "out_of_range_parameter",
            title: base.title,
            components: [
                DesignFlowDesignSpec.Component(
                    name: "R1",
                    deviceKindID: "resistor",
                    parameters: ["r": 0]
                ),
            ],
            nets: [],
            analyses: base.analyses,
            pexIR: try base.pexIR?.normalizedCore()
        ), to: outOfRangeParameterURL)

        await #expect(throws: DesignFlowDesignSpecError.parameterOutOfRange(
            component: "R1",
            parameter: "r"
        )) {
            try await service.execute(DesignFlowCommand(
                kind: .generateDesignNetlist,
                designSpecPath: outOfRangeParameterURL.path(percentEncoded: false)
            ))
        }

        let unsupportedModelURL = root.appending(path: "unsupported-model.json")
        try writeDesignSpec(DesignFlowDesignSpec(
            name: "unsupported_model",
            title: base.title,
            components: [
                DesignFlowDesignSpec.Component(
                    name: "R1",
                    deviceKindID: "resistor",
                    parameters: ["r": 1_000],
                    modelPresetID: "generic_nmos"
                ),
            ],
            nets: [],
            analyses: base.analyses,
            pexIR: try base.pexIR?.normalizedCore()
        ), to: unsupportedModelURL)

        await #expect(throws: DesignFlowDesignSpecError.unsupportedComponentModel(
            component: "R1",
            deviceKindID: "resistor"
        )) {
            try await service.execute(DesignFlowCommand(
                kind: .generateDesignNetlist,
                designSpecPath: unsupportedModelURL.path(percentEncoded: false)
            ))
        }

        let incompatiblePresetURL = root.appending(path: "incompatible-preset.json")
        try writeDesignSpec(DesignFlowDesignSpec(
            name: "incompatible_preset",
            title: base.title,
            components: [
                DesignFlowDesignSpec.Component(
                    name: "M1",
                    deviceKindID: "nmos_l1",
                    parameters: ["w": 1.0e-6, "l": 1.0e-6],
                    modelPresetID: "generic_pmos"
                ),
            ],
            nets: [],
            analyses: base.analyses,
            pexIR: try base.pexIR?.normalizedCore()
        ), to: incompatiblePresetURL)

        await #expect(throws: DesignFlowDesignSpecError.incompatibleModelPresetID(
            component: "M1",
            modelPresetID: "generic_pmos",
            expectedModelType: "NMOS",
            actualModelType: "PMOS"
        )) {
            try await service.execute(DesignFlowCommand(
                kind: .generateDesignNetlist,
                designSpecPath: incompatiblePresetURL.path(percentEncoded: false)
            ))
        }

        let ambiguousModelURL = root.appending(path: "ambiguous-model.json")
        try writeDesignSpec(DesignFlowDesignSpec(
            name: "ambiguous_model",
            title: base.title,
            components: [
                DesignFlowDesignSpec.Component(
                    name: "M1",
                    deviceKindID: "nmos_l1",
                    parameters: ["w": 1.0e-6, "l": 1.0e-6],
                    modelPresetID: "generic_nmos",
                    modelName: "CUSTOM_NMOS"
                ),
            ],
            nets: [],
            analyses: base.analyses,
            pexIR: try base.pexIR?.normalizedCore()
        ), to: ambiguousModelURL)

        await #expect(throws: DesignFlowDesignSpecError.ambiguousComponentModel(component: "M1")) {
            try await service.execute(DesignFlowCommand(
                kind: .generateDesignNetlist,
                designSpecPath: ambiguousModelURL.path(percentEncoded: false)
            ))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func designSpecNormalizesInlinePEXUnitsAndRejectsInvalidPEX() async throws {
        let root = try makeTemporaryRoot("inline-pex-spec")
        defer { removeTemporaryRoot(root) }
        let service = DesignFlowService()

        let scaledPEXURL = root.appending(path: "scaled-pex.json")
        try writeDesignSpecJSON(
            agentResistorDividerSpecJSON(
                pexUnits: """
                "units": {
                  "resistance": "kohm",
                  "capacitance": "fF",
                  "coordinate": "um"
                },
                """,
                pexElements: """
                {
                  "id": "r_out",
                  "kind": "resistor",
                  "nodeA": "out",
                  "nodeB": "out_pex",
                  "value": 0.001
                },
                {
                  "id": "c_out",
                  "kind": "capacitor",
                  "nodeA": "out_pex",
                  "value": 2.0
                }
                """
            ),
            to: scaledPEXURL
        )
        let scaledDesign = try service.loadDesignSpec(scaledPEXURL).build()
        #expect(scaledDesign.pexIR?.units == .canonical)
        #expect(scaledDesign.pexIR?.elements.first { $0.id == "r_out" }?.value == 1.0)
        #expect(scaledDesign.pexIR?.elements.first { $0.id == "c_out" }?.value == 2.0e-15)

        let missingNodeURL = root.appending(path: "missing-node.json")
        try writeDesignSpecJSON(
            agentResistorDividerSpecJSON(
                pexUnits: "",
                pexElements: """
                {
                  "id": "r_out",
                  "kind": "resistor",
                  "nodeA": "out",
                  "value": 0.5
                }
                """
            ),
            to: missingNodeURL
        )
        await #expect(throws: DesignFlowDesignSpecError.missingPEXElementNodeB("r_out", "resistor")) {
            try await service.execute(DesignFlowCommand(
                kind: .generateDesignNetlist,
                designSpecPath: missingNodeURL.path(percentEncoded: false)
            ))
        }

        let unsupportedUnitURL = root.appending(path: "unsupported-unit.json")
        try writeDesignSpecJSON(
            agentResistorDividerSpecJSON(
                pexUnits: """
                "units": {
                  "resistance": "mohm",
                  "capacitance": "F",
                  "coordinate": "um"
                },
                """,
                pexElements: """
                {
                  "id": "r_out",
                  "kind": "resistor",
                  "nodeA": "out",
                  "nodeB": "out_pex",
                  "value": 0.5
                }
                """
            ),
            to: unsupportedUnitURL
        )
        await #expect(throws: DesignFlowDesignSpecError.unsupportedPEXResistanceUnit("mohm")) {
            try await service.execute(DesignFlowCommand(
                kind: .generateDesignNetlist,
                designSpecPath: unsupportedUnitURL.path(percentEncoded: false)
            ))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIRunsFixtureRoundTripAndSummarizesBottlenecks() async throws {
        let root = try makeTemporaryRoot("command-round-trip")
        defer { removeTemporaryRoot(root) }

        let service = DesignFlowService()
        let roundTrip = try await service.execute(DesignFlowCommand(
            kind: .runFixtureRoundTrip,
            fixtureName: "resistor-divider",
            projectRootPath: root.path(percentEncoded: false),
            runID: "command-api-round-trip",
            approveSignoff: true,
            maxAbsoluteDelta: 1.0e-3,
            maxRelativeDelta: 1.0e-3,
            relativeDeltaDenominatorFloor: 0.1
        ))

        #expect(roundTrip.fixtureName == "resistor-divider")
        #expect(roundTrip.runID == "command-api-round-trip")
        #expect(roundTrip.readyForPEX == true)
        #expect(roundTrip.manifestPath?.hasSuffix("round-trip-manifest.json") == true)
        let manifest = try #require(roundTrip.manifestPath).loadManifest()
        let comparisonPath = try #require(manifest.artifacts.first { $0.kind == "post-layout-comparison" }?.path)
        let comparisonData = try Data(contentsOf: artifactURL(
            path: comparisonPath,
            manifestPath: try #require(roundTrip.manifestPath)
        ))
        let comparison = try JSONDecoder().decode(PostLayoutComparisonReport.self, from: comparisonData)
        #expect(comparison.comparisonLimits?.relativeDeltaDenominatorFloor == 0.1)
        #expect(roundTrip.pexElementCount == 2)
        #expect(roundTrip.bottleneckSummary?.totalMeasuredDurationSeconds ?? 0 >= 0)
        #expect(roundTrip.bottleneckSummary?.longestStageName != nil)

        let history = try await service.execute(DesignFlowCommand(
            kind: .summarizeBottlenecks,
            projectRootPath: root.path(percentEncoded: false)
        ))

        #expect(history.bottleneckHistory?.runCount == 1)
        #expect(history.bottleneckHistory?.mostExpensiveStageName != nil)

        let encoded = try JSONEncoder().encode(roundTrip)
        let decoded = try JSONDecoder().decode(DesignFlowCommandResult.self, from: encoded)
        #expect(decoded.manifestPath == roundTrip.manifestPath)
        #expect(decoded.runID == roundTrip.runID)
        #expect(decoded.bottleneckSummary == roundTrip.bottleneckSummary)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIRejectsIncompleteSignoffPairAndInvalidLimits() async throws {
        let service = DesignFlowService()
        let invalidRoot = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioDesignFlowServiceTests-invalid-command-\(UUID().uuidString)")
        let invalidRunIDRoot = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioDesignFlowServiceTests-invalid-run-id-\(UUID().uuidString)")
        defer { removeTemporaryRoot(invalidRoot) }
        defer { removeTemporaryRoot(invalidRunIDRoot) }

        await #expect(throws: DesignFlowCommandError.incompleteSignoffLogPair) {
            try await service.execute(DesignFlowCommand(
                kind: .runFixtureRoundTrip,
                fixtureName: "voltage-divider",
                signoffDRCLogPath: "/tmp/drc.log"
            ))
        }

        do {
            _ = try await service.execute(DesignFlowCommand(
                kind: .runFixtureRoundTrip,
                fixtureName: "voltage-divider",
                projectRootPath: invalidRoot.path(percentEncoded: false),
                maxAbsoluteDelta: .nan
            ))
            Issue.record("Expected invalid comparison limits to throw.")
        } catch DesignFlowCommandError.invalidComparisonLimits(let diagnostics) {
            #expect(!diagnostics.isEmpty)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: invalidRoot.path(percentEncoded: false)))

        do {
            _ = try await service.execute(DesignFlowCommand(
                kind: .runFixtureRoundTrip,
                fixtureName: "voltage-divider",
                projectRootPath: invalidRoot.path(percentEncoded: false),
                variableComparisonLimits: [
                    PostLayoutVariableComparisonLimit(variableName: "V(out)"),
                ]
            ))
            Issue.record("Expected invalid variable comparison limits to throw.")
        } catch DesignFlowCommandError.invalidComparisonLimits(let diagnostics) {
            #expect(diagnostics.contains { $0.contains("V(out)") })
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: invalidRoot.path(percentEncoded: false)))

        do {
            _ = try await service.execute(DesignFlowCommand(
                kind: .runFixtureRoundTrip,
                fixtureName: "voltage-divider",
                projectRootPath: invalidRunIDRoot.path(percentEncoded: false),
                runID: "../escaped-run",
                approveSignoff: true,
                pexManifestPath: "/definitely/missing/pex-manifest.json",
                signoffDRCLogPath: "/tmp/drc.log"
            ))
            Issue.record("Expected invalid run ID to throw.")
        } catch StudioError.invalidDesign(let message) {
            #expect(message.contains("Invalid run ID"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: invalidRunIDRoot.path(percentEncoded: false)))
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func unifiedAPIRunsHeadlessRoundTrip() async throws {
        let root = try makeTemporaryRoot("round-trip")
        defer { removeTemporaryRoot(root) }

        let service = DesignFlowService()
        let configuration = HeadlessRoundTripService.Configuration(
            projectRoot: root,
            runID: "api-round-trip",
            title: "API round trip",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: PEXParasiticIR(
                version: "1.0",
                cornerID: "tt_25c_1v0",
                elements: [
                    PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 0.5),
                    PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 1e-15),
                ]
            ),
            externalSignoffCommands: try makeSignoffCommands(in: root),
            approvedBy: "api-reviewer",
            approvedAt: Date(timeIntervalSince1970: 2_000),
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        let result = try await service.runRoundTrip(DesignFlowRoundTripRequest(
            schematic: SchematicPreview.voltageDividerViewModel().document,
            configuration: configuration
        ))
        let bottlenecks = try service.summarizeBottlenecks(projectRoot: root)

        #expect(result.manifest.isRoundTripComplete)
        #expect(result.manifest.isReadyForPEX)
        #expect(result.manifest.stages.allSatisfy { $0.status == .passed })
        #expect(bottlenecks.runCount == 1)
        #expect(bottlenecks.mostExpensiveStageName != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func unifiedAPIRunsSchematicSimulation() async throws {
        let service = DesignFlowService()
        let result = try await service.runSchematicSimulation(DesignFlowSchematicSimulationRequest(
            schematic: SchematicPreview.voltageDividerViewModel().document,
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op])
        ))

        #expect(result.netlist.contains(".op"))
        #expect(result.simulationResult.status == .completed)
        #expect(result.simulationResult.waveform != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func unifiedAPIGeneratesLayoutAndRunsPrePEXVerification() throws {
        let service = DesignFlowService()
        let schematic = SchematicPreview.voltageDividerViewModel().document

        let layout = try service.generateLayout(DesignFlowLayoutGenerationRequest(
            schematic: schematic,
            catalog: .standard()
        ))
        let verification = service.runPrePEXVerification(DesignFlowPrePEXVerificationRequest(
            schematic: schematic,
            layout: layout.document,
            tech: layout.tech,
            designUnit: layout.designUnit,
            catalog: .standard()
        ))

        #expect(layout.unroutedNets.isEmpty)
        #expect(verification.drc.passed)
        #expect(verification.lvs.passed)
        #expect(verification.isReadyForPEX)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func unifiedAPIGeneratesRCLowPassLayoutAndRunsPrePEXVerification() throws {
        let service = DesignFlowService()
        let schematic = SchematicPreview.rcLowPassViewModel().document

        let layout = try service.generateLayout(DesignFlowLayoutGenerationRequest(
            schematic: schematic,
            catalog: .standard()
        ))
        let verification = service.runPrePEXVerification(DesignFlowPrePEXVerificationRequest(
            schematic: schematic,
            layout: layout.document,
            tech: layout.tech,
            designUnit: layout.designUnit,
            catalog: .standard()
        ))

        if !verification.isReadyForPEX {
            Issue.record("DRC: \(verification.drc)")
            Issue.record("LVS: \(verification.lvs)")
        }

        #expect(layout.unroutedNets.isEmpty)
        #expect(verification.drc.passed)
        #expect(verification.lvs.passed)
        #expect(verification.isReadyForPEX)
    }

    @Test(.timeLimit(.minutes(1)))
    func unifiedAPIRunsPostLayoutSimulationAndComparison() async throws {
        let service = DesignFlowService()
        let baseNetlist = """
        * Voltage divider fixture
        V1 vin 0 1
        R1 vin out 1000
        R2 out 0 1000
        .op
        .end
        """
        let parasitics = PEXParasiticIR(
            version: "1.0",
            cornerID: "tt_25c_1v0",
            elements: [
                PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 0.5),
                PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 1e-15),
            ]
        )

        let preLayoutResult = try await service.runSPICESimulation(DesignFlowSPICESimulationRequest(
            source: baseNetlist,
            fileName: nil
        ))
        let postLayoutNetlist = service.buildPostLayoutNetlist(
            baseNetlist: baseNetlist,
            parasitics: parasitics
        )
        let postLayoutResult = try await service.runPostLayoutSimulation(DesignFlowPostLayoutSimulationRequest(
            baseNetlist: baseNetlist,
            parasitics: parasitics,
            command: .op
        ))
        let comparison = service.comparePostLayout(
            preLayoutResult: preLayoutResult,
            postLayoutResult: postLayoutResult,
            limits: PostLayoutComparisonLimits(maxAbsoluteDelta: 1.0e-3)
        )

        #expect(postLayoutNetlist.contains("* --- Extracted parasitics ---"))
        #expect(postLayoutResult.status == .completed)
        #expect(comparison.status == "compared")
        #expect(comparison.gateStatus == "passed")
    }

    @Test func unifiedAPILoadsPEXInputWithArtifactPaths() throws {
        let manifestURL = try fixtureURL(
            "manifest",
            extension: "json",
            subdirectory: "pex/golden-voltage-divider"
        )

        let input = try DesignFlowService().loadPEXInput(
            manifestURL: manifestURL,
            cornerID: "ss_125c_0v9"
        )

        #expect(input.ir.cornerID == "ss_125c_0v9")
        #expect(input.ir.elements.count == 3)
        #expect(input.artifactPaths.contains { $0.hasSuffix("manifest.json") })
        #expect(input.artifactPaths.contains { $0.hasSuffix("ss_125c_0v9.json") })
        #expect(input.artifactPaths.contains { $0.hasSuffix("voltage-divider.spef") })
        #expect(input.artifactPaths.contains { $0.hasSuffix("extraction.log") })
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func commandAPIRunsPEXExtractionThroughBackendAdapter() async throws {
        let root = try makeTemporaryRoot("pex-extraction-command")
        defer { removeTemporaryRoot(root) }
        let runDirectory = root.appending(path: "pex-runs").appending(path: "mock-run")
        try writePEXArtifacts(runDirectory: runDirectory)
        let configURL = root.appending(path: "pex-config.json")
        try "{}".write(to: configURL, atomically: true, encoding: .utf8)
        let executable = try writeExecutable(
            named: "mock-pexengine",
            in: root,
            contents: """
            #!/bin/sh
            printf '{"artifacts":{"manifestURL":"%s"}}\\n' "\(runDirectory.appending(path: "manifest.json").path(percentEncoded: false))"
            exit 0
            """
        )

        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .runPEXExtraction,
            pexCornerID: "tt_25c_1v0",
            pexConfigPath: configURL.path(percentEncoded: false),
            pexExecutablePath: executable.path(percentEncoded: false)
        ))

        #expect(result.kind == .runPEXExtraction)
        #expect(result.pexManifestPath == runDirectory.appending(path: "manifest.json").path(percentEncoded: false))
        #expect(result.pexCornerID == "tt_25c_1v0")
        #expect(result.pexElementCount == 1)
        #expect(result.message == "mock-pexengine")
    }

    @Test(.timeLimit(.minutes(1)))
    func sharedPEXExtractionAPIProducesInjectablePostLayoutNetlist() throws {
        let root = try makeTemporaryRoot("pex-extraction-shared-api")
        defer { removeTemporaryRoot(root) }
        let runDirectory = root.appending(path: "pex-runs").appending(path: "mock-run")
        try writePEXArtifacts(runDirectory: runDirectory)
        let configURL = root.appending(path: "pex-config.json")
        try "{}".write(to: configURL, atomically: true, encoding: .utf8)
        let executable = try writeExecutable(
            named: "mock-pexengine",
            in: root,
            contents: """
            #!/bin/sh
            printf '{"artifacts":{"manifestURL":"%s"}}\\n' "\(runDirectory.appending(path: "manifest.json").path(percentEncoded: false))"
            exit 0
            """
        )

        let service = DesignFlowService()
        let extraction = try service.runPEXExtraction(DesignFlowPEXExtractionRequest(
            configURL: configURL,
            workingDirectory: root,
            cornerID: "tt_25c_1v0",
            executablePath: executable.path(percentEncoded: false)
        ))
        let postLayoutNetlist = service.buildPostLayoutNetlist(
            baseNetlist: """
            * Base
            V1 out 0 1
            .op
            .end
            """,
            parasitics: extraction.ir
        )

        #expect(extraction.commandResult?.exitCode == 0)
        #expect(extraction.manifestURL == runDirectory.appending(path: "manifest.json"))
        #expect(extraction.ir.elements.count == 1)
        #expect(postLayoutNetlist.contains("* --- Extracted parasitics ---"))
        #expect(postLayoutNetlist.contains("RPEX_r_out out 0 12"))
        #expect(!postLayoutNetlist.contains("top.spef"))
    }

    private func makeSignoffCommands(in root: URL) throws -> [ExternalSignoffCommand] {
        let drc = try writeExecutable(
            named: "mock-drc",
            in: root,
            contents: """
            #!/bin/sh
            printf '[INFO] rule=DRC_CLEAN message="clean drc"\\n'
            exit 0
            """
        )
        let lvs = try writeExecutable(
            named: "mock-lvs",
            in: root,
            contents: """
            #!/bin/sh
            printf '[INFO] rule=LVS_MATCH message="clean lvs"\\n'
            exit 0
            """
        )

        return [
            ExternalSignoffCommand(
                kind: .drc,
                toolName: "mock-drc",
                executablePath: drc.path(percentEncoded: false)
            ),
            ExternalSignoffCommand(
                kind: .lvs,
                toolName: "mock-lvs",
                executablePath: lvs.path(percentEncoded: false)
            ),
        ]
    }

    private func writePEXArtifacts(runDirectory: URL) throws {
        let rawDirectory = runDirectory.appending(path: "raw").appending(path: "tt_25c_1v0")
        let irDirectory = runDirectory.appending(path: "ir")
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: irDirectory, withIntermediateDirectories: true)
        try "mock spef".write(to: rawDirectory.appending(path: "top.spef"), atomically: true, encoding: .utf8)
        try "mock log".write(to: rawDirectory.appending(path: "extraction.log"), atomically: true, encoding: .utf8)
        try """
        {
          "version": "1.0",
          "cornerID": { "value": "tt_25c_1v0" },
          "units": { "resistance": "ohm", "capacitance": "F", "coordinate": "um" },
          "nets": [],
          "elements": [
            {
              "id": "r_out",
              "kind": "resistor",
              "nodeA": { "netName": { "value": "out" }, "nodeName": { "value": "out" } },
              "nodeB": { "netName": { "value": "0" }, "nodeName": { "value": "0" } },
              "value": 12.0,
              "source": "extracted"
            }
          ],
          "metadata": {}
        }
        """.write(to: irDirectory.appending(path: "tt_25c_1v0.json"), atomically: true, encoding: .utf8)
        try """
        {
          "version": 2,
          "runID": { "value": "00000000-0000-0000-0000-000000000300" },
          "requestHash": { "value": "fixture" },
          "backendID": "mock-pexengine",
          "status": "success",
          "startedAt": "2026-05-07T00:00:00Z",
          "finishedAt": "2026-05-07T00:00:01Z",
          "corners": [
            {
              "cornerID": { "value": "tt_25c_1v0" },
              "status": "success",
              "artifactIDs": ["raw-tt", "ir-tt", "log-tt"]
            }
          ],
          "artifacts": [
            {
              "id": "raw-tt",
              "kind": "rawOutput",
              "stage": "backendExecution",
              "cornerID": { "value": "tt_25c_1v0" },
              "relativePath": { "value": "raw/tt_25c_1v0/top.spef" },
              "createdAt": "2026-05-07T00:00:00Z",
              "status": "available"
            },
            {
              "id": "ir-tt",
              "kind": "parasiticIR",
              "stage": "persistence",
              "cornerID": { "value": "tt_25c_1v0" },
              "relativePath": { "value": "ir/tt_25c_1v0.json" },
              "createdAt": "2026-05-07T00:00:00Z",
              "status": "available"
            },
            {
              "id": "log-tt",
              "kind": "log",
              "stage": "backendExecution",
              "cornerID": { "value": "tt_25c_1v0" },
              "relativePath": { "value": "raw/tt_25c_1v0/extraction.log" },
              "createdAt": "2026-05-07T00:00:00Z",
              "status": "available"
            }
          ],
          "warnings": []
        }
        """.write(to: runDirectory.appending(path: "manifest.json"), atomically: true, encoding: .utf8)
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

    private func fixtureURL(_ name: String, extension ext: String, subdirectory: String) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: ext,
            subdirectory: subdirectory
        ) else {
            throw StudioError.projectLoadFailed("Missing fixture: Fixtures/\(subdirectory)/\(name).\(ext)")
        }
        return url
    }

    private func rootFixtureURL(_ name: String, extension ext: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw StudioError.projectLoadFailed("Missing fixture: Fixtures/\(name).\(ext)")
        }
        return url
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioDesignFlowServiceTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeDesignSpec(_ spec: DesignFlowDesignSpec, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(spec)
        try data.write(to: url, options: .atomic)
    }

    private func writeDesignEditScript(_ script: DesignFlowDesignEditScript, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(script)
        try data.write(to: url, options: .atomic)
    }

    private func writeLayoutDocument(_ layout: LayoutDocument, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(layout)
        try data.write(to: url, options: .atomic)
    }

    private func writeDesignUnit(_ designUnit: DesignUnit, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(designUnit)
        try data.write(to: url, options: .atomic)
    }

    private func writeHeadlessManifest(_ manifest: HeadlessRoundTripService.Manifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    private func roundTripArtifact(
        kind: String,
        url: URL,
        path: String? = nil
    ) throws -> HeadlessRoundTripService.Artifact {
        let digest = try RoundTripArtifactDigest.compute(url: url)
        return HeadlessRoundTripService.Artifact(
            kind: kind,
            path: path ?? url.lastPathComponent,
            sha256: digest.sha256,
            byteCount: digest.byteCount
        )
    }

    private func writeLayoutEditScript(_ script: DesignFlowLayoutEditScript, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(script)
        try data.write(to: url, options: .atomic)
    }

    private func loadLayoutDiff(_ url: URL) throws -> DesignFlowLayoutDiff {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DesignFlowLayoutDiff.self, from: data)
    }

    private func writeDesignSpecJSON(_ json: String, to url: URL) throws {
        try Data(json.utf8).write(to: url, options: .atomic)
    }

    private func agentResistorDividerSpec(
        postLayoutComparisonLimits: PostLayoutComparisonLimits? = nil
    ) -> DesignFlowDesignSpec {
        DesignFlowDesignSpec(
            name: "agent-resistor-divider",
            title: "Agent resistor divider",
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
            ],
            postLayoutComparisonLimits: postLayoutComparisonLimits,
            pexIR: PEXParasiticIR(
                version: "1.0",
                cornerID: "tt_25c_1v0",
                elements: [
                    PEXParasiticElement(
                        id: "r_out",
                        kind: .resistor,
                        nodeA: "out",
                        nodeB: "out_pex",
                        value: 0.5
                    ),
                    PEXParasiticElement(
                        id: "c_out",
                        kind: .capacitor,
                        nodeA: "out_pex",
                        nodeB: nil,
                        value: 1.0e-15
                    ),
                ]
            )
        )
    }

    private func agentResistorDividerSpecJSON(
        pexUnits: String,
        pexElements: String
    ) -> String {
        """
        {
          "schemaVersion": 1,
          "name": "agent_resistor_divider",
          "title": "Agent resistor divider",
          "components": [
            {
              "name": "V1",
              "deviceKindID": "vsource",
              "parameters": {
                "dc": 5.0
              }
            },
            {
              "name": "R1",
              "deviceKindID": "resistor",
              "parameters": {
                "r": 1000.0
              }
            },
            {
              "name": "R2",
              "deviceKindID": "resistor",
              "parameters": {
                "r": 1000.0
              }
            },
            {
              "name": "GND1",
              "deviceKindID": "ground"
            }
          ],
          "nets": [
            {
              "name": "vin",
              "terminals": [
                {
                  "component": "V1",
                  "port": "pos"
                },
                {
                  "component": "R1",
                  "port": "pos"
                }
              ]
            },
            {
              "name": "out",
              "terminals": [
                {
                  "component": "R1",
                  "port": "neg"
                },
                {
                  "component": "R2",
                  "port": "pos"
                }
              ]
            },
            {
              "name": "0",
              "terminals": [
                {
                  "component": "V1",
                  "port": "neg"
                },
                {
                  "component": "R2",
                  "port": "neg"
                },
                {
                  "component": "GND1",
                  "port": "gnd"
                }
              ]
            }
          ],
          "analyses": [
            {
              "kind": "op"
            }
          ],
          "pexIR": {
            "version": "1.0",
            "cornerID": "tt_25c_1v0",
            \(pexUnits)
            "elements": [
              \(pexElements)
            ],
            "diagnostics": []
          }
        }
        """
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
}

private extension String {
    func loadManifest() throws -> HeadlessRoundTripService.Manifest {
        let data = try Data(contentsOf: URL(filePath: self))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HeadlessRoundTripService.Manifest.self, from: data)
    }
}

private func artifactURL(path: String, manifestPath: String) -> URL {
    if path.hasPrefix("/") {
        return URL(filePath: path)
    }
    return URL(filePath: manifestPath).deletingLastPathComponent().appending(path: path)
}
