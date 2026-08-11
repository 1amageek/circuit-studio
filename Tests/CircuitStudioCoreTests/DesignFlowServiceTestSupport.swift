import CircuitSignoff
import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation
import Foundation
import DesignFlowKernel
import Testing
import LayoutCore
import PEXEngine
import Xcircuite
@testable import CircuitStudioApp
@testable import CircuitStudioCore
@testable import SchematicEditor

enum DesignFlowServiceTestSupport {
    static func createCanonicalRunLedger(
        projectRoot: URL,
        runID: String
    ) async throws {
        let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        try await store.createWorkspace()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let manifest = try FlowRunManifest(
            runID: runID,
            status: .failed,
            actor: FlowRunActor(kind: .agent, identifier: "circuit-studio-tests"),
            intent: "Failure action selection test",
            createdAt: timestamp,
            updatedAt: timestamp,
            startedAt: timestamp,
            finishedAt: timestamp
        )
        let stageID = "failure-stage"
        let stage = FlowStageResult(
            stageID: stageID,
            status: .failed,
            gates: [FlowGateResult(gateID: "execution", status: .failed)]
        )
        let toolchain = FlowToolchainManifest(
            runID: runID,
            stages: [
                FlowToolchainStageRecord(
                    stageID: stageID,
                    executorToolID: "circuit-studio-tests"
                ),
            ]
        )
        let evidence = try EvidenceManifest.contentAddressed(
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(
                    kind: .library,
                    identifier: "circuit-studio-tests",
                    version: "development"
                ),
                startedAt: timestamp,
                completedAt: timestamp
            ),
            artifacts: [],
            digester: SHA256ContentDigester()
        )
        _ = try await store.saveRunLedger(FlowRunLedger(
            runID: runID,
            runManifest: manifest,
            stages: [stage],
            toolchain: toolchain,
            evidence: evidence
        ))
    }

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
        let inputDirectory = runDirectory.appending(path: "inputs")
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: irDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        let spefData = Data("mock spef".utf8)
        let logData = Data("mock log".utf8)
        let inputData = Data("{}".utf8)
        let irData = Data("""
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
        """.utf8)
        try spefData.write(to: rawDirectory.appending(path: "top.spef"), options: .atomic)
        try logData.write(to: rawDirectory.appending(path: "extraction.log"), options: .atomic)
        try irData.write(to: irDirectory.appending(path: "tt_25c_1v0.json"), options: .atomic)
        try inputData.write(to: inputDirectory.appending(path: "layout.json"), options: .atomic)
        let cornerID = PEXCornerID("tt_25c_1v0")
        let createdAt = Date(timeIntervalSince1970: 1_778_112_000)
        let producer = try ProducerIdentity(
            kind: .engine,
            identifier: "mock-pexengine",
            version: "1.0.0",
            build: String(repeating: "a", count: 64)
        )
        func artifactRecord(
            id: String,
            kind: PEXArtifactKind,
            stage: PEXStage,
            relativePath: String,
            format: ArtifactFormat,
            data: Data
        ) throws -> PEXArtifactRecord {
            let descriptor = ArtifactDescriptor(
                role: .output,
                kind: try ArtifactKind(rawValue: kind.foundationRawValue),
                format: format
            )
            let path = try ArtifactRelativePath(
                segments: relativePath.split(separator: "/").map(String.init)
            )
            let reference = try ArtifactReference(
                digest: try ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: PEXRequestHash.compute(from: data).value
                ),
                byteCount: UInt64(data.count),
                descriptor: descriptor
            )
            let available = try PEXAvailableArtifact(
                reference: reference,
                availability: .local(
                    artifactID: reference.id,
                    rootID: ArtifactRootID(rawValue: "pex-test-run"),
                    relativePath: path
                ),
                producer: producer
            )
            return try PEXArtifactRecord(
                declaration: PEXArtifactDeclaration(
                    id: try PEXArtifactRecordID(rawValue: id),
                    descriptor: descriptor,
                    relativePath: path
                ),
                payload: .available(available),
                stage: stage,
                cornerID: cornerID,
                createdAt: createdAt
            )
        }

        let artifacts = try [
            artifactRecord(
                id: "raw-tt",
                kind: .rawOutput,
                stage: .backendExecution,
                relativePath: "raw/tt_25c_1v0/top.spef",
                format: .spef,
                data: spefData
            ),
            artifactRecord(
                id: "ir-tt",
                kind: .parasiticIR,
                stage: .persistence,
                relativePath: "ir/tt_25c_1v0.json",
                format: .json,
                data: irData
            ),
            artifactRecord(
                id: "log-tt",
                kind: .log,
                stage: .backendExecution,
                relativePath: "raw/tt_25c_1v0/extraction.log",
                format: .text,
                data: logData
            ),
        ]
        guard let runUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000300") else {
            throw StudioError.projectLoadFailed("Invalid PEX fixture run ID")
        }
        let inputArtifact = try ArtifactReference(
            digest: try SHA256ContentDigester().digest(data: inputData),
            byteCount: UInt64(inputData.count),
            descriptor: ArtifactDescriptor(
                role: .input,
                kind: .layout,
                format: .json
            )
        )
        let finishedAt = createdAt.addingTimeInterval(1)
        let provenance = try ExecutionProvenance(
            producer: producer,
            inputs: [inputArtifact],
            invocation: try .inProcess(
                entryPoint: "CircuitStudioTests.DesignFlowServiceTestSupport.writePEXArtifacts"
            ),
            environment: try ExecutionEnvironmentFingerprint(
                platform: "macos",
                architecture: "arm64",
                toolchain: "mock-pexengine"
            ),
            startedAt: createdAt,
            completedAt: finishedAt
        )
        let evidence = try EvidenceManifest.contentAddressed(
            provenance: provenance,
            artifacts: artifacts.compactMap(\.reference),
            digester: SHA256ContentDigester()
        )
        let manifest = try PEXArtifactManifest(
            runID: PEXRunID(runUUID),
            requestHash: PEXRequestHash("fixture"),
            backendID: "mock-pexengine",
            status: .success,
            startedAt: createdAt,
            finishedAt: finishedAt,
            corners: [
                PEXArtifactCorner(
                    cornerID: cornerID,
                    status: .success,
                    artifactIDs: artifacts.map(\.id)
                )
            ],
            artifacts: artifacts,
            warnings: [],
            provenance: provenance,
            evidence: evidence
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: runDirectory.appending(path: "manifest.json"),
            options: .atomic
        )
    }

    static func makePEXRunResult(runDirectory: URL) throws -> PEXRunResult {
        let manifestURL = runDirectory.appending(path: "manifest.json")
        let resolver = try PEXArtifactResolver(manifestURL: manifestURL)
        let manifest = resolver.manifest
        let ir = try resolver.loadIR(cornerID: "tt_25c_1v0")
        return try PEXRunResult(
            runID: manifest.runID,
            requestHash: manifest.requestHash,
            status: .success,
            startedAt: manifest.startedAt,
            finishedAt: manifest.finishedAt,
            cornerResults: [
                PEXCornerResult(
                    cornerID: "tt_25c_1v0",
                    status: .success,
                    ir: ir,
                    metrics: PEXCornerMetrics(
                        durationSeconds: 0.1,
                        netCount: ir.nets.count,
                        elementCount: ir.elements.count
                    )
                ),
            ],
            warnings: [],
            artifactManifest: manifest,
            manifestURL: manifestURL,
            metrics: PEXRunMetrics(
                totalDurationSeconds: 0.1,
                cornerCount: 1,
                successCount: 1,
                failureCount: 0
            )
        )
    }

    static func writePEXConfig(to url: URL) throws {
        let config = PEXProjectConfig(
            topCell: "TOP",
            backendID: "mock-pexengine",
            corners: ["tt_25c_1v0"],
            inputs: PEXProjectConfig.InputPaths(
                layout: "top.gds",
                netlist: "top.spice",
                technology: "technology.json"
            ),
            output: PEXProjectConfig.OutputPaths(workspace: "pex-runs")
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
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
        let relativePath = path ?? url.lastPathComponent
        let binding = try FlowArtifactBinding.circuitStudioBinding(
            logicalID: "\(kind)-\(relativePath)",
            kind: kind,
            relativePath: relativePath,
            fileURL: url
        )
        return HeadlessRoundTripService.Artifact(
            binding: binding
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
            pexIR: ParasiticIR(
                version: "1.0",
                cornerID: "tt_25c_1v0",
                elements: [
                    ParasiticElement(
                        id: "r_out",
                        kind: .resistor,
                        nodeA: "out",
                        nodeB: "out_pex",
                        value: 0.5
                    ),
                    ParasiticElement(
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
        let resolvedUnits = pexUnits.isEmpty ? """
            "units": {
              "resistance": "ohm",
              "capacitance": "F",
              "coordinate": "um"
            },
            """ : pexUnits
        return """
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
            "cornerID": { "value": "tt_25c_1v0" },
            \(resolvedUnits)
            "nets": [
              {
                "name": { "value": "out" },
                "nodes": [
                  { "name": { "value": "out" }, "kind": "internal" }
                ],
                "totalGroundCapF": 0,
                "totalCouplingCapF": 0,
                "totalResistanceOhm": 0
              },
              {
                "name": { "value": "out_pex" },
                "nodes": [
                  { "name": { "value": "out_pex" }, "kind": "internal" }
                ],
                "totalGroundCapF": 0,
                "totalCouplingCapF": 0,
                "totalResistanceOhm": 0
              }
            ],
            "elements": [
              \(pexElements)
            ],
            "metadata": {}
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
