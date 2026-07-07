import Foundation
import DesignFlowKernel
import Testing
import LayoutCore
@testable import CircuitStudioApp
@testable import CircuitStudioCore
@testable import SchematicEditor

enum DesignFlowServiceTestSupport {
    static func makeSignoffCommands(in root: URL) throws -> [ExternalSignoffCommand] {
        let drc = try Self.writeExecutable(
            named: "mock-drc",
            in: root,
            contents: """
            #!/bin/sh
            printf '[INFO] rule=DRC_CLEAN message="clean drc"\\n'
            printf 'SIGNOFF_RESULT status=pass\\n'
            exit 0
            """
        )
        let lvs = try Self.writeExecutable(
            named: "mock-lvs",
            in: root,
            contents: """
            #!/bin/sh
            printf '[INFO] rule=LVS_MATCH message="clean lvs"\\n'
            printf 'SIGNOFF_RESULT status=pass\\n'
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
    
    static func writePEXArtifacts(runDirectory: URL) throws {
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
    
    static func writeExecutable(named name: String, in root: URL, contents: String) throws -> URL {
        let url = root.appending(path: name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path(percentEncoded: false)
        )
        return url
    }
    
    static func fixtureURL(_ name: String, extension ext: String, subdirectory: String) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: ext,
            subdirectory: subdirectory
        ) else {
            throw StudioError.projectLoadFailed("Missing fixture: Fixtures/\(subdirectory)/\(name).\(ext)")
        }
        return url
    }
    
    static func rootFixtureURL(_ name: String, extension ext: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw StudioError.projectLoadFailed("Missing fixture: Fixtures/\(name).\(ext)")
        }
        return url
    }
    
    static func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioDesignFlowServiceTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    
    static func writeDesignSpec(_ spec: DesignFlowDesignSpec, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(spec)
        try data.write(to: url, options: .atomic)
    }
    
    static func writeDesignEditScript(_ script: DesignFlowDesignEditScript, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(script)
        try data.write(to: url, options: .atomic)
    }
    
    static func writeLayoutDocument(_ layout: LayoutDocument, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(layout)
        try data.write(to: url, options: .atomic)
    }
    
    static func writeDesignUnit(_ designUnit: DesignUnit, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(designUnit)
        try data.write(to: url, options: .atomic)
    }
    
    static func writeHeadlessManifest(_ manifest: HeadlessRoundTripService.Manifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }
    
    static func roundTripArtifact(
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
    
    static func writeLayoutEditScript(_ script: DesignFlowLayoutEditScript, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(script)
        try data.write(to: url, options: .atomic)
    }
    
    static func loadLayoutDiff(_ url: URL) throws -> DesignFlowLayoutDiff {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DesignFlowLayoutDiff.self, from: data)
    }
    
    static func writeDesignSpecJSON(_ json: String, to url: URL) throws {
        try Data(json.utf8).write(to: url, options: .atomic)
    }
    
    static func agentResistorDividerSpec(
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
    
    static func agentResistorDividerSpecJSON(
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
    
    static func removeTemporaryRoot(_ root: URL) {
        guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
    
    static func prewarmTimingLibraryBuildCache(
        model: Level1DeviceModel,
        technologyContext: TimingTechnologyContext
    ) async throws {
        let inputSlews = [40e-12, 200e-12]
        let outputLoads = [1e-15, 4e-15, 12e-15]
        let cellLibrary = try CMOSGateLibrary.loadBundledDefault()
        let cells = [
            cellLibrary.inverter(name: "inv"),
            cellLibrary.nand(name: "nand2", inputs: ["A", "B"]),
            cellLibrary.nor(name: "nor2", inputs: ["A", "B"]),
        ]
        for (index, cell) in cells.enumerated() {
            _ = try await TimingCharacterizationCache.shared.cellTiming(
                cell: cell,
                model: model,
                inputSlews: inputSlews,
                outputLoads: outputLoads
            ) {
                try Self.cellTimingFixture(
                    cell: cell,
                    inputSlews: inputSlews,
                    outputLoads: outputLoads,
                    value: Double(index + 1) * 10e-12
                )
            }
        }
    
        let dffNetlist = DFFGenerator(cellLibrary: cellLibrary).netlist(name: "dff")
        _ = try await TimingCharacterizationCache.shared.sequentialReport(
            netlist: dffNetlist,
            cellName: "dff",
            model: model,
            technologyContext: technologyContext,
            clockSlew: 80e-12,
            dataSlew: 80e-12,
            outputLoads: outputLoads,
            setupHoldSearchWindow: 300e-12,
            setupHoldSearchResolution: 20e-12,
            maxSearchIterations: 4
        ) {
            try Self.sequentialReportFixture(
                netlist: dffNetlist,
                technologyContext: technologyContext,
                outputLoads: outputLoads
            )
        }
    }
    
    static func cellTimingFixture(
        cell: CMOSGateNetlist,
        inputSlews: [Double],
        outputLoads: [Double],
        value: Double
    ) throws -> CellTiming {
        let inputPins = Set(cell.devices.map(\.gate)).sorted()
        let lut = try Self.constantTimingLUT(inputSlews: inputSlews, outputLoads: outputLoads, value: value)
        return CellTiming(
            cellName: cell.name,
            inputCapacitance: Dictionary(uniqueKeysWithValues: inputPins.map { ($0, 1e-15) }),
            arcs: inputPins.map {
                TimingArc(
                    inputPin: $0,
                    sense: .negativeUnate,
                    delayRise: lut,
                    delayFall: lut,
                    transitionRise: lut,
                    transitionFall: lut
                )
            }
        )
    }
    
    static func sequentialReportFixture(
        netlist: GateLevelNetlist,
        technologyContext: TimingTechnologyContext,
        outputLoads: [Double]
    ) throws -> SequentialTimingCharacterizationReport {
        let clockSlews = [80e-12]
        let timing = SequentialTiming(
            clkToQRise: try Self.constantTimingLUT(inputSlews: clockSlews, outputLoads: outputLoads, value: 100e-12),
            clkToQFall: try Self.constantTimingLUT(inputSlews: clockSlews, outputLoads: outputLoads, value: 110e-12),
            qTransitionRise: try Self.constantTimingLUT(inputSlews: clockSlews, outputLoads: outputLoads, value: 30e-12),
            qTransitionFall: try Self.constantTimingLUT(inputSlews: clockSlews, outputLoads: outputLoads, value: 35e-12),
            setupTime: 20e-12,
            holdTime: 10e-12,
            dataCapacitance: 1e-15,
            clockCapacitance: 2e-15
        )
        return SequentialTimingCharacterizationReport(
            cellName: "dff",
            topologyHash: try TimingTopologyHasher.hash(netlist),
            activeClockEdge: .rising,
            technology: technologyContext,
            characterizationGrid: SequentialTimingCharacterizationGrid(
                clockSlews: clockSlews,
                dataSlews: [80e-12],
                outputLoads: outputLoads,
                setupHoldSearchResolution: 20e-12,
                setupHoldSearchWindow: 300e-12
            ),
            timing: timing,
            clkToQMeasurements: [],
            qTransitionMeasurements: [],
            setupMeasurements: [],
            holdMeasurements: [],
            status: .passed
        )
    }
    
    static func constantTimingLUT(
        inputSlews: [Double],
        outputLoads: [Double],
        value: Double
    ) throws -> TimingLUT {
        try TimingLUT(
            inputSlews: inputSlews,
            outputLoads: outputLoads,
            values: inputSlews.map { _ in outputLoads.map { _ in value } }
        )
    }
}

extension String {
    func loadManifest() throws -> HeadlessRoundTripService.Manifest {
        let data = try Data(contentsOf: URL(filePath: self))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HeadlessRoundTripService.Manifest.self, from: data)
    }
}

func artifactURL(path: String, manifestPath: String) -> URL {
    if path.hasPrefix("/") {
        return URL(filePath: path)
    }
    return URL(filePath: manifestPath).deletingLastPathComponent().appending(path: path)
}
