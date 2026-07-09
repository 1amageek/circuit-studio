import Foundation
import DesignFlowKernel
import Testing
import LayoutCore
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
        let packageURL = try DesignFlowServiceTestSupport.rootFixtureURL("technology-package", extension: "json")
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

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRunsFixtureRoundTripWithTechnologyPackage() async throws {
        let packageURL = try DesignFlowServiceTestSupport.rootFixtureURL("technology-package", extension: "json")
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
        let packageURL = try DesignFlowServiceTestSupport.rootFixtureURL("technology-package", extension: "json")
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
            technologyPackagePath: packageURL.path(percentEncoded: false),
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
        let packageURL = try DesignFlowServiceTestSupport.rootFixtureURL("technology-package", extension: "json")
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
            technologyPackagePath: packageURL.path(percentEncoded: false),
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
    func commandAPIApprovesGateAndWritesAuditRecord() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("gate-approval")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "approval-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try writeGateApprovalComparisonReport(to: comparisonURL)
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try DesignFlowServiceTestSupport.writeHeadlessManifest(HeadlessRoundTripService.Manifest(
            runID: "approval-run",
            title: "Approval run",
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            isRoundTripComplete: true,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "post-layout-comparison", status: .passed),
            ],
            artifacts: [
                try DesignFlowServiceTestSupport.roundTripArtifact(
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

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIApprovesExplicitTargetAsRunRelativeRecord() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("gate-approval-explicit-target")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "approval-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try writeGateApprovalComparisonReport(to: comparisonURL)
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try DesignFlowServiceTestSupport.writeHeadlessManifest(HeadlessRoundTripService.Manifest(
            runID: "approval-run",
            title: "Explicit target approval run",
            createdAt: Date(timeIntervalSince1970: 1_700_000_125),
            isRoundTripComplete: true,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "post-layout-comparison", status: .passed),
            ],
            artifacts: [
                try DesignFlowServiceTestSupport.roundTripArtifact(
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
            approvalTargetPath: comparisonURL.path(percentEncoded: false),
            approvalReviewer: "layout-reviewer"
        ))

        #expect(result.approvalRecord?.targetArtifactPathBase == .runDirectory)
        #expect(result.approvalRecord?.targetArtifactPath == "post-layout-comparison.json")
        #expect(result.approvalRecord?.targetArtifactKind == nil)
        let review = try RoundTripReviewService().loadReview(manifestURL: manifestURL)
        #expect(review.diagnostics.isEmpty)
        #expect(review.approvals.count == 1)
        #expect(review.approvals.first?.targetArtifactPathBase == .runDirectory)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRejectsExplicitGateApprovalTargetOutsideRunDirectory() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("gate-approval-explicit-target-escape")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "approval-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try writeGateApprovalComparisonReport(to: comparisonURL)
        let outsideURL = root.appending(path: "outside-comparison.json")
        try writeGateApprovalComparisonReport(to: outsideURL)
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try DesignFlowServiceTestSupport.writeHeadlessManifest(HeadlessRoundTripService.Manifest(
            runID: "approval-run",
            title: "Explicit target escape approval run",
            createdAt: Date(timeIntervalSince1970: 1_700_000_130),
            isRoundTripComplete: true,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "post-layout-comparison", status: .passed),
            ],
            artifacts: [
                try DesignFlowServiceTestSupport.roundTripArtifact(
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
                approvalGateID: .postLayoutComparison,
                approvalTargetPath: outsideURL.path(percentEncoded: false),
                approvalReviewer: "layout-reviewer"
            ))
            Issue.record("Expected explicit approval target outside the run directory to fail.")
        } catch let error as FlowRunGovernanceError {
            if case .invalidArtifactPath(let message) = error {
                #expect(message.contains("outside"))
            } else {
                Issue.record("Expected invalid artifact path error, got \(error).")
            }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRecordsFailureSuggestedCommandSelection() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("failure-command-selection")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "failure-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
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
                    suggestedCommands: [
                        FlowRunSuggestedCommand(
                            commandID: "circuit-studio-flow-runner.review-round-trip",
                            readiness: .ready,
                            executable: "swift",
                            arguments: [
                                "run",
                                "--quiet",
                                "circuit-studio-flow-runner",
                                "--review-round-trip",
                                "--manifest",
                                manifestURL.path(percentEncoded: false),
                                "--json",
                            ],
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
            kind: .selectFailureSuggestedCommand,
            failureEnvelopePath: failureEnvelopeURL.path(percentEncoded: false),
            suggestedCommandID: "circuit-studio-flow-runner.review-round-trip",
            approvalReviewer: "agent-1"
        ))

        let actionLogPath = try #require(result.actionLogPath)
        #expect(FileManager.default.fileExists(atPath: actionLogPath))
        #expect(actionLogPath.hasSuffix(".xcircuite/runs/failure-run/actions.jsonl"))
        #expect(result.runID == "failure-run")
        #expect(result.manifestPath == manifestURL.path(percentEncoded: false))
        #expect(result.selectedSuggestedCommand?.actor.identifier == "agent-1")
        #expect(result.selectedSuggestedCommand?.nextActionID == "review-flow-runner-failure")
        #expect(result.selectedSuggestedCommand?.commandID == "circuit-studio-flow-runner.review-round-trip")
        #expect(result.roundTripReview?.suggestedCommandSelections.count == 1)
        #expect(result.message?.hasPrefix("round-trip-suggested-command-selection-") == true)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIDispatchesSelectedFailureSuggestedReviewCommand() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("failure-command-dispatch")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "failure-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
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
                    suggestedCommands: [
                        FlowRunSuggestedCommand(
                            commandID: "circuit-studio-flow-runner.review-round-trip",
                            readiness: .ready,
                            executable: "swift",
                            arguments: [
                                "run",
                                "--quiet",
                                "circuit-studio-flow-runner",
                                "--review-round-trip",
                                "--manifest",
                                manifestURL.path(percentEncoded: false),
                                "--json",
                            ],
                            reason: "Load the failed run review from its persisted manifest."
                        ),
                    ]
                ),
            ]
        )
        _ = try RoundTripActionLogService().recordSuggestedCommandSelection(
            from: failureEnvelope,
            commandID: "circuit-studio-flow-runner.review-round-trip",
            reviewer: "agent-1"
        )

        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .runSelectedSuggestedCommand,
            projectRootPath: root.path(percentEncoded: false),
            runID: "failure-run",
            suggestedCommandID: "circuit-studio-flow-runner.review-round-trip"
        ))

        #expect(result.kind == .reviewRoundTrip)
        #expect(result.roundTripReview?.runID == "failure-run")
        #expect(result.roundTripReview?.status == .failed)
        #expect(result.roundTripReview?.suggestedCommandSelections.count == 1)
        #expect(result.roundTripReview?.suggestedCommandSelections.first?.commandID == "circuit-studio-flow-runner.review-round-trip")
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRejectsUnsupportedSelectedFailureSuggestedExecutable() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("failure-command-dispatch-reject")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "failure-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
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
                    suggestedCommands: [
                        FlowRunSuggestedCommand(
                            commandID: "unsupported.shell",
                            readiness: .ready,
                            executable: "bash",
                            arguments: ["-lc", "echo unsafe"],
                            reason: "Unsupported shell command."
                        ),
                    ]
                ),
            ]
        )
        _ = try RoundTripActionLogService().recordSuggestedCommandSelection(
            from: failureEnvelope,
            commandID: "unsupported.shell",
            reviewer: "agent-1"
        )

        await #expect(throws: RoundTripSelectedSuggestedCommandResolutionError.self) {
            try await DesignFlowService().execute(DesignFlowCommand(
                kind: .runSelectedSuggestedCommand,
                projectRootPath: root.path(percentEncoded: false),
                runID: "failure-run",
                suggestedCommandID: "unsupported.shell"
            ))
        }
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRejectsEscapingGateApprovalArtifactPath() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("gate-approval-escape")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "approval-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let outsideURL = runDirectory
            .deletingLastPathComponent()
            .appending(path: "outside-comparison.json")
        try Data(#"{"status":"compared","gateStatus":"passed"}"#.utf8).write(to: outsideURL, options: .atomic)

        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try DesignFlowServiceTestSupport.writeHeadlessManifest(HeadlessRoundTripService.Manifest(
            runID: "approval-run",
            title: "Escaping approval run",
            createdAt: Date(timeIntervalSince1970: 1_700_000_150),
            isRoundTripComplete: true,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "post-layout-comparison", status: .passed),
            ],
            artifacts: [
                try DesignFlowServiceTestSupport.roundTripArtifact(
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

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRejectsAbsoluteManifestArtifactPath() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("gate-approval-absolute-artifact")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "approval-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try Data(#"{"status":"compared","gateStatus":"passed"}"#.utf8).write(to: comparisonURL, options: .atomic)
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try DesignFlowServiceTestSupport.writeHeadlessManifest(HeadlessRoundTripService.Manifest(
            runID: "approval-run",
            title: "Absolute artifact approval run",
            createdAt: Date(timeIntervalSince1970: 1_700_000_175),
            isRoundTripComplete: true,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "post-layout-comparison", status: .passed),
            ],
            artifacts: [
                try DesignFlowServiceTestSupport.roundTripArtifact(
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

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRejectsGateApprovalForInvalidManifestRunID() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("gate-approval-invalid-run")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "approval-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try Data(#"{"status":"compared","gateStatus":"passed"}"#.utf8).write(to: comparisonURL, options: .atomic)
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try DesignFlowServiceTestSupport.writeHeadlessManifest(HeadlessRoundTripService.Manifest(
            runID: "../escape",
            title: "Invalid approval run",
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            isRoundTripComplete: true,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "post-layout-comparison", status: .passed),
            ],
            artifacts: [
                try DesignFlowServiceTestSupport.roundTripArtifact(
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

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRejectsPrePEXApprovalWithoutVerificationArtifact() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("gate-approval-missing-pre-pex")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "approval-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let comparisonURL = runDirectory.appending(path: "post-layout-comparison.json")
        try Data(#"{"status":"compared","gateStatus":"passed"}"#.utf8).write(to: comparisonURL, options: .atomic)
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try DesignFlowServiceTestSupport.writeHeadlessManifest(HeadlessRoundTripService.Manifest(
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
                try DesignFlowServiceTestSupport.roundTripArtifact(
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

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIApprovesPhysicalVerificationReportGates() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("gate-approval-physical-verification")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let runDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "approval-run")
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let verificationURL = runDirectory.appending(path: "physical-verification.json")
        try Data(#"{"status":"passed","readyForPEX":true}"#.utf8).write(to: verificationURL, options: .atomic)
        let manifestURL = runDirectory.appending(path: "round-trip-manifest.json")
        try DesignFlowServiceTestSupport.writeHeadlessManifest(HeadlessRoundTripService.Manifest(
            runID: "approval-run",
            title: "Physical verification approval run",
            createdAt: Date(timeIntervalSince1970: 1_700_000_350),
            isRoundTripComplete: true,
            isReadyForPEX: true,
            stages: [
                HeadlessRoundTripService.Stage(name: "pre-pex-verification", status: .passed),
            ],
            artifacts: [
                try DesignFlowServiceTestSupport.roundTripArtifact(
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

    private func writeGateApprovalComparisonReport(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(gateApprovalComparisonReport())
        try data.write(to: url, options: .atomic)
    }

    private func gateApprovalComparisonReport() -> PostLayoutComparisonReport {
        PostLayoutComparisonReport(
            status: "compared",
            preLayoutPointCount: 1,
            postLayoutPointCount: 1,
            sweepVariable: nil,
            comparedPointCount: 1,
            maxAbsoluteDelta: 0.001,
            maxRelativeDelta: 0.01,
            comparedVariables: [
                PostLayoutVariableComparison(
                    variableName: "v(out)",
                    signalDomain: .voltage,
                    unit: "V",
                    maxAbsoluteDelta: 0.001,
                    maxRelativeDelta: 0.01,
                    firstPreLayoutValue: 1.0,
                    firstPostLayoutValue: 0.999,
                    lastPreLayoutValue: 1.0,
                    lastPostLayoutValue: 0.999
                ),
            ],
            oscillationMetrics: [],
            missingInPostLayout: [],
            addedInPostLayout: [],
            diagnostics: [],
            comparisonLimits: PostLayoutComparisonLimits(maxAbsoluteDelta: 0.01),
            gateStatus: "passed",
            gateViolations: []
        )
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
