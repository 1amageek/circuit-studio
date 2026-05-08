import Foundation
import Testing
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
            pexIR: base.pexIR?.core
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
            pexIR: base.pexIR?.core
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
