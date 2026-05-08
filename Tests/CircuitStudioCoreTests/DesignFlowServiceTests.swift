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
        try writeDesignSpec(agentResistorDividerSpec(), to: specURL)

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
            maxAbsoluteDelta: 1.0e-3,
            maxRelativeDelta: 2.0
        ))
        #expect(roundTrip.designName == "agent-resistor-divider")
        #expect(roundTrip.runID == "agent-resistor-divider-run")
        #expect(roundTrip.readyForPEX == true)
        #expect(roundTrip.manifestPath?.hasSuffix("round-trip-manifest.json") == true)
        let manifest = try #require(roundTrip.manifestPath).loadManifest()
        #expect(manifest.artifacts.contains {
            $0.kind == "design-spec"
                && $0.path.contains("/input-artifacts/design/")
                && $0.sourcePath == specURL.path(percentEncoded: false)
        })

        let encoded = try JSONEncoder().encode(roundTrip)
        let decoded = try JSONDecoder().decode(DesignFlowCommandResult.self, from: encoded)
        #expect(decoded.designName == roundTrip.designName)
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
            maxRelativeDelta: 1.0e-3
        ))

        #expect(roundTrip.fixtureName == "resistor-divider")
        #expect(roundTrip.runID == "command-api-round-trip")
        #expect(roundTrip.readyForPEX == true)
        #expect(roundTrip.manifestPath?.hasSuffix("round-trip-manifest.json") == true)
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

    private func writeDesignSpecJSON(_ json: String, to url: URL) throws {
        try Data(json.utf8).write(to: url, options: .atomic)
    }

    private func agentResistorDividerSpec() -> DesignFlowDesignSpec {
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
