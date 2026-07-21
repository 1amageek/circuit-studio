import Foundation
import CircuiteFoundation
import DesignFlowKernel
import Testing
import LayoutCore
import ToolQualification
@testable import CircuitStudioApp
@testable import CircuitStudioCore
@testable import SchematicEditor

@Suite("DesignFlowService Tests", .serialized)
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

    @Test(.timeLimit(.minutes(2)))
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

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func technologyPackageLoadsAndInjectsProcessConfig() async throws {
        let workspaceURL = try DesignFlowServiceTestSupport.rootFixtureURL("technology-package", extension: "json")
        let service = DesignFlowService()

        let packageResult = try await service.execute(DesignFlowCommand(
            kind: .loadTechnologyPackage,
            technologyPackagePath: workspaceURL.path(percentEncoded: false)
        ))
        #expect(packageResult.technologyPackageID == "virtual45-golden-flow")
        #expect(packageResult.validationDiagnostics?.isEmpty == true)

        let package = try service.loadTechnologyPackage(workspaceURL)
        #expect(package.processConfiguration?.effectiveParameters()["vdd"] == 1.0)
        #expect(package.processConfiguration?.resolveIncludes == true)
        let tech = try TechnologyPackageLayoutTechResolver().resolve(package: package)
        #expect(tech.layerDefinition(for: .init(name: "ACTIVE", purpose: "drawing")) != nil)

        let netlist = try await service.execute(DesignFlowCommand(
            kind: .generateFixtureNetlist,
            fixtureName: "voltage-divider",
            technologyPackagePath: workspaceURL.path(percentEncoded: false)
        ))
        #expect(netlist.technologyPackageID == "virtual45-golden-flow")
        #expect(netlist.netlist?.contains(".lib \"models/core.lib\" tt") == true)
        #expect(netlist.netlist?.contains(".include \"models/passives.inc\"") == true)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRunsFixtureRoundTripWithTechnologyPackage() async throws {
        let workspaceURL = try DesignFlowServiceTestSupport.rootFixtureURL("technology-package", extension: "json")
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("technology-package-round-trip")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }

        let roundTrip = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .runFixtureRoundTrip,
            fixtureName: "voltage-divider",
            projectRootPath: root.path(percentEncoded: false),
            runID: "technology-package-voltage-divider",
            approveSignoff: true,
            maxAbsoluteDelta: 1.0e-3,
            maxRelativeDelta: 2.0,
            technologyPackagePath: workspaceURL.path(percentEncoded: false)
        ))

        #expect(roundTrip.readyForPEX == true)
        #expect(roundTrip.technologyPackageID == "virtual45-golden-flow")
        #expect(roundTrip.pexCornerID == "tt_25c_1v0")
        let manifest = try #require(roundTrip.manifestPath).loadManifest()
        #expect(manifest.artifacts.contains { $0.kind == "design-spec" && $0.path.hasSuffix("technology-package.json") })
        #expect(manifest.artifacts.contains { $0.kind == "external-signoff-log" })
        #expect(manifest.artifacts.contains { $0.kind == "pex-artifact" })
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRunsDesignSpecNetlistSimulationAndRoundTrip() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("design-spec-round-trip")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let specURL = root.appending(path: "agent-resistor-divider.json")
        let embeddedLimits = PostLayoutComparisonLimits(maxAbsoluteDelta: 1.0e-3, maxRelativeDelta: 2.0)
        try DesignFlowServiceTestSupport.writeDesignSpec(
            DesignFlowServiceTestSupport.agentResistorDividerSpec(postLayoutComparisonLimits: embeddedLimits),
            to: specURL
        )
        let drcLogURL = root.appending(path: "imported-drc.log")
        let lvsLogURL = root.appending(path: "imported-lvs.log")
        try """
        [INFO] rule=DRC_CLEAN message="clean drc"
        SIGNOFF_RESULT status=pass
        """.write(to: drcLogURL, atomically: true, encoding: .utf8)
        try """
        [INFO] rule=LVS_MATCH message="clean lvs"
        SIGNOFF_RESULT status=pass
        """.write(to: lvsLogURL, atomically: true, encoding: .utf8)

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
            approveSignoff: true,
            signoffDRCLogPath: drcLogURL.path(percentEncoded: false),
            signoffLVSLogPath: lvsLogURL.path(percentEncoded: false)
        ))
        #expect(roundTrip.designName == "agent-resistor-divider")
        #expect(roundTrip.runID == "agent-resistor-divider-run")
        #expect(roundTrip.readyForPEX == true)
        #expect(roundTrip.comparisonLimitsConfigured == true)
        #expect(roundTrip.manifestPath?.hasSuffix("round-trip-manifest.json") == true)
        let manifest = try #require(roundTrip.manifestPath).loadManifest()
        #expect(manifest.artifacts.contains { $0.kind == "external-signoff-log" })
        #expect(manifest.stages.contains { $0.name == "external-signoff" })
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

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIAppliesDesignEditAndWritesAuditArtifacts() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("design-edit")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let inputURL = root.appending(path: "input.json")
        let scriptURL = root.appending(path: "edits.json")
        let outputURL = root.appending(path: "edited.json")
        try DesignFlowServiceTestSupport.writeDesignSpec(
            DesignFlowServiceTestSupport.agentResistorDividerSpec(),
            to: inputURL
        )
        try DesignFlowServiceTestSupport.writeDesignEditScript(DesignFlowDesignEditScript(edits: [
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

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIAppliesLayoutEditAndWritesAuditArtifacts() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("layout-edit")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
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
        try DesignFlowServiceTestSupport.writeLayoutDocument(layout, to: inputURL)
        try DesignFlowServiceTestSupport.writeLayoutEditScript(DesignFlowLayoutEditScript(edits: [
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

        let diff = try DesignFlowServiceTestSupport.loadLayoutDiff(URL(filePath: diffPath))
        #expect(diff.addedNets == ["TOP:out"])
        #expect(diff.addedShapes == [shapeID])
        #expect(diff.addedPins == ["TOP:OUT"])
        #expect(diff.addedLabels == ["TOP:out"])
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRunsLayoutTrustAndWritesArtifacts() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("layout-trust")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let workspaceURL = try DesignFlowServiceTestSupport.rootFixtureURL("technology-package", extension: "json")
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
        try DesignFlowServiceTestSupport.writeLayoutDocument(layout, to: layoutURL)

        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .runLayoutTrust,
            projectRootPath: root.path(percentEncoded: false),
            runID: "layout-trust-run",
            technologyPackagePath: workspaceURL.path(percentEncoded: false),
            layoutDocumentPath: layoutURL.path(percentEncoded: false)
        ))

        #expect(result.readyForPEX == nil)
        #expect(result.technologyPackageID == "virtual45-golden-flow")
        #expect(result.layoutTrustPassed == true)
        #expect(result.layoutTrustReport?.passed == true)
        #expect(result.layoutTrustReport?.ownedShapeCount == 1)
        let reportPath = try #require(result.layoutTrustReportPath)
        #expect(FileManager.default.fileExists(atPath: reportPath))
        #expect(reportPath.hasSuffix(".xcircuite/runs/layout-trust-run/layout/layout-trust-report.json"))
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRejectsLayoutTrustWithoutTechnologyPackage() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("layout-trust-missing-tech")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let layoutURL = root.appending(path: "layout.json")
        try DesignFlowServiceTestSupport.writeLayoutDocument(trustedLayoutDocument(), to: layoutURL)

        await #expect(throws: DesignFlowCommandError.missingTechnologyPackagePath) {
            _ = try await DesignFlowService().execute(DesignFlowCommand(
                kind: .runLayoutTrust,
                projectRootPath: root.path(percentEncoded: false),
                runID: "layout-trust-run",
                layoutDocumentPath: layoutURL.path(percentEncoded: false)
            ))
        }

        let reportURL = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "layout-trust-run")
            .appending(path: "layout")
            .appending(path: "layout-trust-report.json")
        #expect(!FileManager.default.fileExists(atPath: reportURL.path(percentEncoded: false)))
    }

    @Test(.timeLimit(.minutes(2)))
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

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRunsVerificationOnlyAndWritesReportArtifact() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("verification-only")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let workspaceURL = try DesignFlowServiceTestSupport.rootFixtureURL("technology-package", extension: "json")
        let layoutURL = root.appending(path: "layout.json")
        let designUnitURL = root.appending(path: "design-unit.json")
        let service = DesignFlowService()
        let fixture = try DesignFlowFixtureLibrary.fixture(named: "voltage-divider")
        let layoutOutput = try service.generateLayout(DesignFlowLayoutGenerationRequest(
            schematic: fixture.schematic,
            catalog: .standard()
        ))
        try DesignFlowServiceTestSupport.writeLayoutDocument(layoutOutput.document, to: layoutURL)
        try DesignFlowServiceTestSupport.writeDesignUnit(layoutOutput.designUnit, to: designUnitURL)

        let result = try await service.execute(DesignFlowCommand(
            kind: .runVerification,
            fixtureName: "voltage-divider",
            projectRootPath: root.path(percentEncoded: false),
            runID: "verification-run",
            approveSignoff: true,
            technologyPackagePath: workspaceURL.path(percentEncoded: false),
            layoutDocumentPath: layoutURL.path(percentEncoded: false),
            designUnitPath: designUnitURL.path(percentEncoded: false)
        ))

        #expect(result.fixtureName == "voltage-divider")
        #expect(result.technologyPackageID == "virtual45-golden-flow")
        #expect(result.readyForPEX == true)
        #expect(result.layoutTrustPassed == true)
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

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRejectsVerificationWithoutTechnologyPackage() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("verification-missing-tech")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let layoutURL = root.appending(path: "layout.json")
        let designUnitURL = root.appending(path: "design-unit.json")
        let service = DesignFlowService()
        let fixture = try DesignFlowFixtureLibrary.fixture(named: "voltage-divider")
        let layoutOutput = try service.generateLayout(DesignFlowLayoutGenerationRequest(
            schematic: fixture.schematic,
            catalog: .standard()
        ))
        try DesignFlowServiceTestSupport.writeLayoutDocument(layoutOutput.document, to: layoutURL)
        try DesignFlowServiceTestSupport.writeDesignUnit(layoutOutput.designUnit, to: designUnitURL)

        await #expect(throws: DesignFlowCommandError.missingTechnologyPackagePath) {
            _ = try await service.execute(DesignFlowCommand(
                kind: .runVerification,
                fixtureName: "voltage-divider",
                projectRootPath: root.path(percentEncoded: false),
                runID: "verification-run",
                layoutDocumentPath: layoutURL.path(percentEncoded: false),
                designUnitPath: designUnitURL.path(percentEncoded: false)
            ))
        }

        let reportURL = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "verification-run")
            .appending(path: "reports")
            .appending(path: "physical-verification.json")
        #expect(!FileManager.default.fileExists(atPath: reportURL.path(percentEncoded: false)))
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRejectsEscapingRunIDBeforeDesignEditWrites() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("design-edit-invalid-run-id")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let inputURL = root.appending(path: "input.json")
        let scriptURL = root.appending(path: "edits.json")
        let outputURL = root.appending(path: "edited.json")
        try DesignFlowServiceTestSupport.writeDesignSpec(
            DesignFlowServiceTestSupport.agentResistorDividerSpec(),
            to: inputURL
        )
        try DesignFlowServiceTestSupport.writeDesignEditScript(DesignFlowDesignEditScript(edits: [
            DesignFlowDesignEdit(kind: .setComponentParameters, componentName: "R2", parameters: ["r": 3000]),
        ]), to: scriptURL)

        await expectInvalidRunIDFailure {
            _ = try await DesignFlowService().execute(DesignFlowCommand(
                kind: .applyDesignEdit,
                designSpecPath: inputURL.path(percentEncoded: false),
                projectRootPath: root.path(percentEncoded: false),
                runID: "../escape",
                editScriptPath: scriptURL.path(percentEncoded: false),
                outputDesignSpecPath: outputURL.path(percentEncoded: false)
            ))
        }

        #expect(!FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: escapedRunArtifactDirectory(root).path(percentEncoded: false)))
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRejectsEscapingRunIDBeforeLayoutEditWrites() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("layout-edit-invalid-run-id")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let inputURL = root.appending(path: "layout.json")
        let scriptURL = root.appending(path: "layout-edits.json")
        let outputURL = root.appending(path: "edited-layout.json")
        let netID = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
        try DesignFlowServiceTestSupport.writeLayoutDocument(trustedLayoutDocument(), to: inputURL)
        try DesignFlowServiceTestSupport.writeLayoutEditScript(DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(kind: .addNet, cellName: "TOP", netID: netID, netName: "guard"),
        ]), to: scriptURL)

        await expectInvalidRunIDFailure {
            _ = try await DesignFlowService().execute(DesignFlowCommand(
                kind: .applyLayoutEdit,
                projectRootPath: root.path(percentEncoded: false),
                runID: "../escape",
                editScriptPath: scriptURL.path(percentEncoded: false),
                layoutDocumentPath: inputURL.path(percentEncoded: false),
                outputLayoutDocumentPath: outputURL.path(percentEncoded: false)
            ))
        }

        #expect(!FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: escapedRunArtifactDirectory(root).path(percentEncoded: false)))
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRejectsEscapingRunIDBeforeLayoutTrustArtifacts() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("layout-trust-invalid-run-id")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let layoutURL = root.appending(path: "layout.json")
        try DesignFlowServiceTestSupport.writeLayoutDocument(trustedLayoutDocument(), to: layoutURL)

        await expectInvalidRunIDFailure {
            _ = try await DesignFlowService().execute(DesignFlowCommand(
                kind: .runLayoutTrust,
                projectRootPath: root.path(percentEncoded: false),
                runID: "../escape",
                layoutDocumentPath: layoutURL.path(percentEncoded: false)
            ))
        }

        #expect(!FileManager.default.fileExists(atPath: escapedRunArtifactDirectory(root).path(percentEncoded: false)))
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRejectsEscapingRunIDBeforeVerificationArtifacts() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("verification-invalid-run-id")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let layoutURL = root.appending(path: "layout.json")
        let designUnitURL = root.appending(path: "design-unit.json")
        let service = DesignFlowService()
        let fixture = try DesignFlowFixtureLibrary.fixture(named: "voltage-divider")
        let layoutOutput = try service.generateLayout(DesignFlowLayoutGenerationRequest(
            schematic: fixture.schematic,
            catalog: .standard()
        ))
        try DesignFlowServiceTestSupport.writeLayoutDocument(layoutOutput.document, to: layoutURL)
        try DesignFlowServiceTestSupport.writeDesignUnit(layoutOutput.designUnit, to: designUnitURL)

        await expectInvalidRunIDFailure {
            _ = try await service.execute(DesignFlowCommand(
                kind: .runVerification,
                fixtureName: "voltage-divider",
                projectRootPath: root.path(percentEncoded: false),
                runID: "../escape",
                layoutDocumentPath: layoutURL.path(percentEncoded: false),
                designUnitPath: designUnitURL.path(percentEncoded: false)
            ))
        }

        #expect(!FileManager.default.fileExists(atPath: escapedRunArtifactDirectory(root).path(percentEncoded: false)))
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRecordsApprovalInCanonicalRunLedger() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("stage-approval")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }

        let request = FlowOperationRequest(
            workspaceID: try await RunReviewTestSupport.workspaceID(projectRoot: root),
            runID: "approval-run",
            intent: "Command API approval",
            stages: [
                FlowStageDefinition(
                    stageID: "post-layout-comparison",
                    displayName: "Post-layout comparison",
                    requiresApproval: true
                ),
            ]
        )
        let blocked = try await RunReviewTestSupport.orchestrator(projectRoot: root).run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [RunReviewPassingExecutor(stageID: "post-layout-comparison")]
        )
        #expect(blocked.status == .blocked)

        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .approveGate,
            projectRootPath: root.path(percentEncoded: false),
            runID: "approval-run",
            approvalStageID: "post-layout-comparison",
            approvalReviewer: "layout-reviewer",
            approvalVerdict: .approved,
            approvalNote: "Reviewed comparison evidence"
        ))

        #expect(result.approvalRecord?.stageID == "post-layout-comparison")
        #expect(result.approvalRecord?.verdict == .approved)
        #expect(result.approvalRecord?.reviewer == "layout-reviewer")
        #expect(result.approvalRecord?.note == "Reviewed comparison evidence")

        let review = try await RunReviewService().loadRun(runID: "approval-run", projectRoot: root)
        #expect(review.stages.first?.approval == result.approvalRecord)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRecordsFailureSuggestedActionSelection() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("failure-action-selection")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "failure-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        try await DesignFlowServiceTestSupport.createCanonicalRunLedger(
            projectRoot: root,
            runID: "failure-run"
        )
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try DesignFlowServiceTestSupport.writeHeadlessManifest(HeadlessRoundTripService.Manifest(
            runID: "failure-run",
            title: "Failure run",
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            isRoundTripComplete: false,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "post-layout-comparison", status: .failed),
            ],
            artifacts: [],
            bottleneckSummary: HeadlessRoundTripService.BottleneckSummary(
                totalMeasuredDurationSeconds: 0.2,
                longestStageName: "post-layout-comparison",
                longestStageDurationSeconds: 0.2,
                failedStageName: "post-layout-comparison",
                recommendations: []
            )
        ), to: manifestURL)

        let failureEnvelope = FlowRunnerFailureEnvelope(
            errorKind: "runtime",
            errorType: "RuntimeTestError",
            message: "Post-layout comparison exceeded configured limits.",
            runID: "failure-run",
            projectRoot: root.path(percentEncoded: false),
            manifest: manifestURL.path(percentEncoded: false),
            stage: "post-layout-comparison",
            recommendation: "Inspect the failed run.",
            nextActions: [
                FlowRunNextAction(
                    actionID: "review-flow-runner-failure",
                    kind: "reviewFlowRunnerFailure",
                    stageID: "post-layout-comparison",
                    severity: .error,
                    reason: "Inspect the failed stage and persisted artifacts.",
                    diagnosticCodes: ["runtime"],
                    suggestedActions: [
                        FlowRunSuggestedAction(
                            id: "review-flow-runner-failure",
                            readiness: .ready,
                            operation: .reviewRun,
                            runID: "failure-run",
                            reason: "Load the failed run review from its persisted manifest."
                        ),
                    ]
                ),
            ]
        )
        let failureEnvelopeURL = runDirectory.appending(path: "flow-runner-failure.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(failureEnvelope).write(to: failureEnvelopeURL, options: .atomic)

        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .selectFailureSuggestedAction,
            failureEnvelopePath: failureEnvelopeURL.path(percentEncoded: false),
            suggestedActionID: "review-flow-runner-failure",
            approvalReviewer: "agent-1"
        ))

        let actionLogPath = try #require(result.actionLogPath)
        #expect(FileManager.default.fileExists(atPath: actionLogPath))
        #expect(actionLogPath.hasSuffix(".xcircuite/runs/failure-run/actions.jsonl"))
        #expect(result.runID == "failure-run")
        #expect(result.manifestPath == manifestURL.path(percentEncoded: false))
        #expect(result.selectedSuggestedAction?.actor.identifier == "agent-1")
        #expect(result.selectedSuggestedAction?.nextActionID == "review-flow-runner-failure")
        #expect(result.selectedSuggestedAction?.action.id == "review-flow-runner-failure")
        #expect(result.roundTripReview?.suggestedActionSelections.count == 1)
        #expect(result.message?.hasPrefix("round-trip-suggested-action-selection-") == true)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIDispatchesSelectedFailureSuggestedReviewAction() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("failure-action-dispatch")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "failure-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        try await DesignFlowServiceTestSupport.createCanonicalRunLedger(
            projectRoot: root,
            runID: "failure-run"
        )
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try DesignFlowServiceTestSupport.writeHeadlessManifest(HeadlessRoundTripService.Manifest(
            runID: "failure-run",
            title: "Failure run",
            createdAt: Date(timeIntervalSince1970: 1_700_000_210),
            isRoundTripComplete: false,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "post-layout-comparison", status: .failed),
            ],
            artifacts: [],
            bottleneckSummary: HeadlessRoundTripService.BottleneckSummary(
                totalMeasuredDurationSeconds: 0.2,
                longestStageName: "post-layout-comparison",
                longestStageDurationSeconds: 0.2,
                failedStageName: "post-layout-comparison",
                recommendations: []
            )
        ), to: manifestURL)

        let failureEnvelope = FlowRunnerFailureEnvelope(
            errorKind: "runtime",
            errorType: "RuntimeTestError",
            message: "Post-layout comparison exceeded configured limits.",
            runID: "failure-run",
            projectRoot: root.path(percentEncoded: false),
            manifest: manifestURL.path(percentEncoded: false),
            stage: "post-layout-comparison",
            recommendation: "Inspect the failed run.",
            nextActions: [
                FlowRunNextAction(
                    actionID: "review-flow-runner-failure",
                    kind: "reviewFlowRunnerFailure",
                    stageID: "post-layout-comparison",
                    severity: .error,
                    reason: "Inspect the failed stage and persisted artifacts.",
                    diagnosticCodes: ["runtime"],
                    suggestedActions: [
                        FlowRunSuggestedAction(
                            id: "review-flow-runner-failure",
                            readiness: .ready,
                            operation: .reviewRun,
                            runID: "failure-run",
                            reason: "Load the failed run review from its persisted manifest."
                        ),
                    ]
                ),
            ]
        )
        _ = try await RoundTripActionLogService().recordSuggestedActionSelection(
            from: failureEnvelope,
            actionID: "review-flow-runner-failure",
            reviewer: "agent-1"
        )

        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .runSelectedSuggestedAction,
            projectRootPath: root.path(percentEncoded: false),
            runID: "failure-run",
            suggestedActionID: "review-flow-runner-failure"
        ))

        #expect(result.kind == .reviewRoundTrip)
        #expect(result.roundTripReview?.runID == "failure-run")
        #expect(result.roundTripReview?.status == .failed)
        #expect(result.roundTripReview?.suggestedActionSelections.count == 1)
        #expect(result.roundTripReview?.suggestedActionSelections.first?.action.id == "review-flow-runner-failure")
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRejectsUnsupportedSelectedFailureSuggestedOperation() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("failure-action-dispatch-reject")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "failure-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        try await DesignFlowServiceTestSupport.createCanonicalRunLedger(
            projectRoot: root,
            runID: "failure-run"
        )
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try DesignFlowServiceTestSupport.writeHeadlessManifest(HeadlessRoundTripService.Manifest(
            runID: "failure-run",
            title: "Failure run",
            createdAt: Date(timeIntervalSince1970: 1_700_000_220),
            isRoundTripComplete: false,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "post-layout-comparison", status: .failed),
            ],
            artifacts: []
        ), to: manifestURL)

        let failureEnvelope = FlowRunnerFailureEnvelope(
            errorKind: "runtime",
            errorType: "RuntimeTestError",
            message: "Post-layout comparison exceeded configured limits.",
            runID: "failure-run",
            projectRoot: root.path(percentEncoded: false),
            manifest: manifestURL.path(percentEncoded: false),
            stage: "post-layout-comparison",
            recommendation: "Inspect the failed run.",
            nextActions: [
                FlowRunNextAction(
                    actionID: "run-unsupported",
                    kind: "runUnsupported",
                    stageID: "post-layout-comparison",
                    severity: .error,
                    reason: "This command must not be dispatched.",
                    suggestedActions: [
                        FlowRunSuggestedAction(
                            id: "unsupported-operation",
                            readiness: .ready,
                            operation: .executeCandidatePlan,
                            runID: "failure-run",
                            reason: "Unsupported operation."
                        ),
                    ]
                ),
            ]
        )
        _ = try await RoundTripActionLogService().recordSuggestedActionSelection(
            from: failureEnvelope,
            actionID: "unsupported-operation",
            reviewer: "agent-1"
        )

        await #expect(throws: RoundTripSelectedSuggestedActionResolutionError.self) {
            try await DesignFlowService().execute(DesignFlowCommand(
                kind: .runSelectedSuggestedAction,
                projectRootPath: root.path(percentEncoded: false),
                runID: "failure-run",
                suggestedActionID: "unsupported-operation"
            ))
        }
    }

    @MainActor
    private func expectInvalidRunIDFailure(_ operation: @MainActor () async throws -> Void) async {
        do {
            try await operation()
            Issue.record("Expected invalid run ID to fail before writing artifacts.")
        } catch {
            #expect(error.localizedDescription.contains("Invalid run ID"))
        }
    }

    private func escapedRunArtifactDirectory(_ root: URL) -> URL {
        root
            .appending(path: ".xcircuite")
            .appending(path: "escape")
    }

    private func trustedLayoutDocument() -> LayoutDocument {
        let cellID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let netID = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
        let shapeID = UUID(uuidString: "00000000-0000-0000-0000-000000000403")!
        return LayoutDocument(
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
    }

}
