import Foundation
import DesignFlowKernel
import Testing
import LayoutCore
@testable import CircuitStudioApp
@testable import CircuitStudioCore
@testable import SchematicEditor

@Suite("DesignFlowService spec validation commands", .serialized)
struct DesignFlowSpecValidationCommandTests {
    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRejectsUnsafeDesignSpecNamesAndDuplicateTerminals() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("invalid-design-spec")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let base = DesignFlowServiceTestSupport.agentResistorDividerSpec()
        let service = DesignFlowService()

        let unsafeNameURL = root.appending(path: "unsafe-name.json")
        try DesignFlowServiceTestSupport.writeDesignSpec(DesignFlowDesignSpec(
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
        try DesignFlowServiceTestSupport.writeDesignSpec(DesignFlowDesignSpec(
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

        let missingSchemaData = Data("""
        {
          "name": "missing-schema",
          "components": [],
          "nets": [],
          "analyses": []
        }
        """.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DesignFlowDesignSpec.self, from: missingSchemaData)
        }

        let unsupportedSchemaURL = root.appending(path: "unsupported-schema.json")
        let unsupportedSchemaData = Data("""
        {
          "schemaVersion": 2,
          "name": "unsupported-schema",
          "components": [],
          "nets": [],
          "analyses": []
        }
        """.utf8)
        try unsupportedSchemaData.write(to: unsupportedSchemaURL)

        await #expect(throws: DesignFlowDesignSpecError.unsupportedSchemaVersion(2)) {
            try await service.execute(DesignFlowCommand(
                kind: .generateDesignNetlist,
                designSpecPath: unsupportedSchemaURL.path(percentEncoded: false)
            ))
        }

        let wrongPrefixURL = root.appending(path: "wrong-prefix.json")
        try DesignFlowServiceTestSupport.writeDesignSpec(DesignFlowDesignSpec(
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
        try DesignFlowServiceTestSupport.writeDesignSpec(DesignFlowDesignSpec(
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
        try DesignFlowServiceTestSupport.writeDesignSpec(DesignFlowDesignSpec(
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
        try DesignFlowServiceTestSupport.writeDesignSpec(DesignFlowDesignSpec(
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
        try DesignFlowServiceTestSupport.writeDesignSpec(DesignFlowDesignSpec(
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
        try DesignFlowServiceTestSupport.writeDesignSpec(DesignFlowDesignSpec(
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
        try DesignFlowServiceTestSupport.writeDesignSpec(DesignFlowDesignSpec(
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
        try DesignFlowServiceTestSupport.writeDesignSpec(DesignFlowDesignSpec(
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

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func designSpecNormalizesInlinePEXUnitsAndRejectsInvalidPEX() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("inline-pex-spec")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let service = DesignFlowService()

        let scaledPEXURL = root.appending(path: "scaled-pex.json")
        try DesignFlowServiceTestSupport.writeDesignSpecJSON(
            DesignFlowServiceTestSupport.agentResistorDividerSpecJSON(
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

        let unsupportedElementKindURL = root.appending(path: "unsupported-pex-element-kind.json")
        try DesignFlowServiceTestSupport.writeDesignSpecJSON(
            DesignFlowServiceTestSupport.agentResistorDividerSpecJSON(
                pexUnits: "",
                pexElements: """
                {
                  "id": "l_out",
                  "kind": "inductor",
                  "nodeA": "out",
                  "nodeB": "out_pex",
                  "value": 0.5
                }
                """
            ),
            to: unsupportedElementKindURL
        )
        #expect(throws: DesignFlowDesignSpecError.unsupportedPEXElementKind("inductor")) {
            _ = try service.loadDesignSpec(unsupportedElementKindURL)
        }

        let unsupportedDiagnosticSeverityURL = root.appending(path: "unsupported-pex-diagnostic-severity.json")
        let unsupportedDiagnosticSeverityJSON = DesignFlowServiceTestSupport.agentResistorDividerSpecJSON(
            pexUnits: "",
            pexElements: """
            {
              "id": "r_out",
              "kind": "resistor",
              "nodeA": "out",
              "nodeB": "out_pex",
              "value": 0.5
            }
            """
        ).replacingOccurrences(
            of: "\"diagnostics\": []",
            with: "\"diagnostics\": [{\"severity\":\"fatal\",\"message\":\"unsupported severity\"}]"
        )
        try DesignFlowServiceTestSupport.writeDesignSpecJSON(
            unsupportedDiagnosticSeverityJSON,
            to: unsupportedDiagnosticSeverityURL
        )
        #expect(throws: DesignFlowDesignSpecError.unsupportedPEXDiagnosticSeverity("fatal")) {
            _ = try service.loadDesignSpec(unsupportedDiagnosticSeverityURL)
        }

        let missingNodeURL = root.appending(path: "missing-node.json")
        try DesignFlowServiceTestSupport.writeDesignSpecJSON(
            DesignFlowServiceTestSupport.agentResistorDividerSpecJSON(
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
        try DesignFlowServiceTestSupport.writeDesignSpecJSON(
            DesignFlowServiceTestSupport.agentResistorDividerSpecJSON(
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

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRunsFixtureRoundTripAndSummarizesBottlenecks() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("command-round-trip")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }

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

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRejectsIncompleteSignoffPairAndInvalidLimits() async throws {
        let service = DesignFlowService()
        let invalidRoot = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioDesignFlowServiceTests-invalid-command-\(UUID().uuidString)")
        let invalidRunIDRoot = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioDesignFlowServiceTests-invalid-run-id-\(UUID().uuidString)")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(invalidRoot) }
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(invalidRunIDRoot) }

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
}
