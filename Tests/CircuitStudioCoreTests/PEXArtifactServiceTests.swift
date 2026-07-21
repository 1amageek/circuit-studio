import Foundation
import Testing
import CircuiteFoundation
@testable import CircuitStudioCore
import PEXEngine

@Suite("PEXArtifactService Tests")
struct PEXArtifactServiceTests {

    @Test func loadManifestUsesPEXEngineArtifactGraph() throws {
        let root = try makeTemporaryRoot("manifest")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root.appending(path: "run-1")
        try FileManager.default.createDirectory(
            at: runDirectory.appending(path: "ir"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: runDirectory.appending(path: "raw").appending(path: "tt"),
            withIntermediateDirectories: true
        )

        let manifestURL = runDirectory.appending(path: "manifest.json")
        try writeArtifact(Data(), relativePath: "ir/tt.json", in: runDirectory)
        try writeArtifact(Data(), relativePath: "raw/tt/tt.spef", in: runDirectory)
        try writeArtifact(Data(), relativePath: "raw/tt/extraction.log", in: runDirectory)
        try manifestJSON(runID: "run-1", cornerID: "tt")
            .write(to: manifestURL, atomically: true, encoding: .utf8)

        let manifest = try PEXArtifactService().loadManifest(manifestURL: manifestURL)
        let resolver = try PEXArtifactResolver(manifestURL: manifestURL)
        let cornerID = PEXCornerID("tt")

        #expect(manifest.runID.description == "00000000-0000-0000-0000-000000000001")
        #expect(manifest.backendID == "mock")
        #expect(manifest.status == .success)
        #expect(manifest.warnings.map(\.message) == ["low confidence"])
        #expect(manifest.corners.count == 1)
        #expect(manifest.corners[0].cornerID.value == "tt")
        #expect(resolver.completenessReport().status == .complete)
        #expect(resolver.records(kind: .parasiticIR, cornerID: cornerID, availability: .available).map { resolver.url(for: $0) } == [
            runDirectory.appending(path: "ir").appending(path: "tt.json"),
        ])
        #expect(resolver.records(kind: .rawOutput, cornerID: cornerID, availability: .available).map { resolver.url(for: $0) } == [
            runDirectory.appending(path: "raw").appending(path: "tt").appending(path: "tt.spef"),
        ])
        #expect(resolver.records(kind: .log, cornerID: cornerID, availability: .available).map { resolver.url(for: $0) } == [
            runDirectory.appending(path: "raw").appending(path: "tt").appending(path: "extraction.log"),
        ])
    }

    @Test func resolverResolvesRunRelativePEXEnginePaths() throws {
        let root = try makeTemporaryRoot("manifest-relative")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root.appending(path: "run-1")
        let manifestURL = runDirectory.appending(path: "manifest.json")
        try FileManager.default.createDirectory(
            at: runDirectory.appending(path: "raw").appending(path: "tt"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: runDirectory.appending(path: "ir"),
            withIntermediateDirectories: true
        )
        try writeArtifact(Data(), relativePath: "ir/tt.json", in: runDirectory)
        try writeArtifact(Data(), relativePath: "raw/tt/tt.spef", in: runDirectory)
        try writeArtifact(Data(), relativePath: "raw/tt/extraction.log", in: runDirectory)
        try manifestJSON(
            runID: "run-1",
            cornerID: "tt",
            rawFiles: ["raw/tt/tt.spef"],
            irFile: "ir/tt.json",
            logFile: "raw/tt/extraction.log"
        )
        .write(to: manifestURL, atomically: true, encoding: .utf8)

        _ = try PEXArtifactService().loadManifest(manifestURL: manifestURL)
        let resolver = try PEXArtifactResolver(manifestURL: manifestURL)
        let cornerID = PEXCornerID("tt")

        #expect(resolver.records(kind: .rawOutput, cornerID: cornerID, availability: .available).map { resolver.url(for: $0) } == [
            runDirectory.appending(path: "raw").appending(path: "tt").appending(path: "tt.spef"),
        ])
        #expect(resolver.records(kind: .parasiticIR, cornerID: cornerID, availability: .available).map { resolver.url(for: $0) } == [
            runDirectory.appending(path: "ir").appending(path: "tt.json"),
        ])
        #expect(resolver.records(kind: .log, cornerID: cornerID, availability: .available).map { resolver.url(for: $0) } == [
            runDirectory.appending(path: "raw").appending(path: "tt").appending(path: "extraction.log"),
        ])
    }

    @Test func loadIRForCornerUsesManifestArtifact() throws {
        let root = try makeTemporaryRoot("corner")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root.appending(path: "run-1")
        let irDirectory = runDirectory.appending(path: "ir")
        try FileManager.default.createDirectory(at: irDirectory, withIntermediateDirectories: true)
        let manifestURL = runDirectory.appending(path: "manifest.json")
        let irJSON = pexEngineIRJSON(cornerID: "tt")
        let irData = Data(irJSON.utf8)
        try irData.write(to: irDirectory.appending(path: "tt.json"), options: .atomic)
        try manifestJSON(
            runID: "run-1",
            cornerID: "tt",
            artifactDataByPath: ["ir/tt.json": irData]
        ).write(to: manifestURL, atomically: true, encoding: .utf8)

        let service = PEXArtifactService()
        let ir = try service.loadIR(for: "tt", manifestURL: manifestURL)

        #expect(ir.cornerID.value == "tt")
        #expect(ir.elements.count == 3)
    }

    @Test func loadIRRejectsArtifactWhoseDigestDoesNotMatchManifest() throws {
        let root = try makeTemporaryRoot("corner-integrity")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root.appending(path: "run-1")
        let irURL = runDirectory.appending(path: "ir/tt.json")
        try FileManager.default.createDirectory(
            at: irURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let irData = Data(pexEngineIRJSON(cornerID: "tt").utf8)
        try irData.write(to: irURL, options: .atomic)
        let manifestURL = runDirectory.appending(path: "manifest.json")
        try manifestJSON(
            runID: "run-1",
            cornerID: "tt",
            artifactDataByPath: ["ir/tt.json": Data("different artifact".utf8)]
        ).write(to: manifestURL, atomically: true, encoding: .utf8)

        do {
            _ = try PEXArtifactService().loadIR(for: "tt", manifestURL: manifestURL)
            Issue.record("Expected PEX artifact integrity validation to fail")
        } catch {
            #expect(error.localizedDescription.contains("IR artifact integrity check failed"))
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func loadPEXEngineArtifactsAndBuildPostLayoutNetlist() async throws {
        let root = try makeTemporaryRoot("pexengine")
        defer { removeTemporaryRoot(root) }

        let layoutURL = root.appending(path: "top.gds")
        let netlistURL = root.appending(path: "top.cir")
        try Data().write(to: layoutURL)
        try "V1 VDD_1 0 1.8\nR1 data_out_1 0 1k\n.end\n"
            .write(to: netlistURL, atomically: true, encoding: .utf8)

        let request = PEXRunRequest(
            layoutURL: layoutURL,
            layoutFormat: .gds,
            sourceNetlistURL: netlistURL,
            sourceNetlistFormat: .spice,
            topCell: "INV",
            corners: [PEXCorner(id: "tt")],
            technology: .inline(makeTechnologyIR()),
            backendSelection: PEXBackendSelection(backendID: "mock"),
            options: .default,
            workingDirectory: root
        )
        let result = try await DefaultPEXEngine(
            adapterRegistry: PEXAdapterRegistry(adapters: [FixturePEXExtractor()]),
            parserRegistry: PEXDefaultParsers.makeRegistry()
        ).run(request)

        #expect(result.status == .success)
        #expect(result.manifestURL.path(percentEncoded: false).hasPrefix(root.path(percentEncoded: false)))

        let artifactService = PEXArtifactService()
        let manifest = try artifactService.loadManifest(manifestURL: result.manifestURL)
        let resolver = try PEXArtifactResolver(manifestURL: result.manifestURL)
        let ir = try artifactService.loadIR(for: "tt", manifestURL: result.manifestURL)
        let postLayoutNetlist = PostLayoutSimulationService().buildPostLayoutNetlist(
            baseNetlist: try String(contentsOf: netlistURL, encoding: .utf8),
            parasitics: ir
        )

        #expect(manifest.status == .success)
        #expect(manifest.corners.count == 1)
        #expect(resolver.completenessReport().status == .complete)
        #expect(resolver.records(kind: .rawOutput, cornerID: PEXCornerID("tt"), availability: .available).map { resolver.url(for: $0) } == [
            root
                .appending(path: result.runID.description)
                .appending(path: "raw")
                .appending(path: "tt")
                .appending(path: "tt.spef"),
        ])
        #expect(ir.elements.count > 0)
        #expect(postLayoutNetlist.contains("* --- Extracted parasitics ---"))
        #expect(postLayoutNetlist.contains("RPEX_"))
        #expect(postLayoutNetlist.contains("CPEX_"))
    }

    @Test(.timeLimit(.minutes(1)))
    func loadGoldenPEXFixtureAndRunPostLayoutAnalysis() async throws {
        let manifestURL = try fixtureURL(
            "manifest",
            extension: "json",
            subdirectory: "pex/golden-voltage-divider"
        )
        let service = PEXArtifactService()
        let manifest = try service.loadManifest(manifestURL: manifestURL)
        let resolver = try PEXArtifactResolver(manifestURL: manifestURL)
        let ir = try service.loadIR(for: "tt_25c_1v0", manifestURL: manifestURL)

        let baseNetlist = """
        * Voltage divider fixture
        V1 vin 0 1
        R1 vin out 1000
        R2 out 0 1000
        .op
        .end
        """
        let postLayoutService = PostLayoutSimulationService()
        let postLayoutNetlist = postLayoutService.buildPostLayoutNetlist(
            baseNetlist: baseNetlist,
            parasitics: ir
        )
        let result = try await postLayoutService.runPostLayoutAnalysis(
            baseNetlist: baseNetlist,
            parasitics: ir,
            command: .op
        )

        #expect(!manifest.runID.description.isEmpty)
        #expect(manifest.backendID == "golden-fixture")
        #expect(manifest.status == .success)
        #expect(manifest.corners.count == 2)
        #expect(resolver.completenessReport().status == .complete)
        #expect(resolver.records(kind: .rawOutput, cornerID: PEXCornerID("tt_25c_1v0"), availability: .available).count == 1)
        #expect(resolver.records(kind: .log, cornerID: PEXCornerID("tt_25c_1v0"), availability: .available).first.map { resolver.url(for: $0).lastPathComponent } == "extraction.log")
        #expect(ir.units == ParasiticUnits(
            resistance: .kiloOhm,
            capacitance: .femtoFarad,
            coordinate: .micrometer
        ))
        #expect(ir.elements.count == 3)
        let resistor = try #require(ir.elements.first { $0.id == "r_out_segment" })
        #expect(resistor.kind == .resistor)
        #expect(resistor.nodeA.nodeName.value == "out")
        #expect(resistor.nodeB?.nodeName.value == "out_pex")
        #expect(resistor.value == 0.0015)
        let substrateCapacitor = try #require(ir.elements.first { $0.id == "c_out_to_substrate" })
        #expect(substrateCapacitor.kind == .capacitor)
        #expect(substrateCapacitor.nodeA.nodeName.value == "out_pex")
        #expect(substrateCapacitor.nodeB == nil)
        #expect(substrateCapacitor.value == 4.2)
        #expect(postLayoutNetlist.contains("RPEX_r_out_segment out out_pex 1.5"))
        #expect(postLayoutNetlist.contains("CPEX_c_out_to_substrate out_pex 0 4.2e-15"))
        #expect(result.status == .completed)
    }

    @Test(.timeLimit(.minutes(1)))
    func goldenPEXFixtureRunsMultiCornerPostLayoutGates() async throws {
        let manifestURL = try fixtureURL(
            "manifest",
            extension: "json",
            subdirectory: "pex/golden-voltage-divider"
        )
        let baseNetlist = """
        * Voltage divider fixture
        V1 vin 0 1
        R1 vin out 1000
        R2 out 0 1000
        .op
        .end
        """
        let preLayoutResult = try await SimulationService().runSPICE(source: baseNetlist, fileName: nil)
        let postLayoutService = PostLayoutSimulationService()
        let comparisonService = PostLayoutComparisonService()
        let limits = PostLayoutComparisonLimits(maxAbsoluteDelta: 1.0e-6, maxRelativeDelta: 1.0e-6)
        var observedCorners: [String] = []

        for cornerID in ["tt_25c_1v0", "ss_125c_0v9"] {
            let ir = try PEXArtifactService().loadIR(for: cornerID, manifestURL: manifestURL)
            let postLayoutResult = try await postLayoutService.runPostLayoutAnalysis(
                baseNetlist: baseNetlist,
                parasitics: ir,
                command: .op
            )
            let report = comparisonService.compare(
                preLayoutResult: preLayoutResult,
                postLayoutResult: postLayoutResult
            ).applyingLimits(limits)

            observedCorners.append(ir.cornerID.value)
            #expect(ir.elements.count == 3)
            #expect(postLayoutResult.status == .completed)
            #expect(report.status == "compared")
            #expect(report.gateStatus == "passed")
        }

        #expect(observedCorners == ["tt_25c_1v0", "ss_125c_0v9"])
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioPEXArtifactServiceTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
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

    private func manifestJSON(
        runID: String,
        cornerID: String,
        rawFiles: [String]? = nil,
        irFile: String? = nil,
        logFile: String? = nil,
        artifactDataByPath: [String: Data] = [:]
    ) throws -> String {
        _ = runID
        let resolvedRawFiles = rawFiles ?? ["raw/\(cornerID)/\(cornerID).spef"]
        let resolvedIRFile = irFile ?? "ir/\(cornerID).json"
        let resolvedLogFile = logFile ?? "raw/\(cornerID)/extraction.log"
        let createdAt = Date(timeIntervalSince1970: 1_777_920_000)
        let corner = PEXCornerID(cornerID)

        func record(
            id: String,
            kind: PEXArtifactKind,
            stage: PEXStage,
            path: String,
            format: ArtifactFormat
        ) throws -> PEXArtifactRecord {
            let data = artifactDataByPath[path] ?? Data()
            let reference = ArtifactReference(
                id: try ArtifactID(rawValue: id),
                locator: ArtifactLocator(
                    location: try ArtifactLocation(workspaceRelativePath: path),
                    role: .output,
                    kind: try ArtifactKind(rawValue: kind.foundationRawValue),
                    format: format
                ),
                digest: try ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: artifactDigest(data)
                ),
                byteCount: UInt64(data.count)
            )
            return PEXArtifactRecord(
                payload: .available(reference),
                stage: stage,
                cornerID: corner,
                createdAt: createdAt
            )
        }

        let rawRecords = try resolvedRawFiles.enumerated().map { index, path in
            try record(
                id: "raw-\(cornerID)-\(index)",
                kind: .rawOutput,
                stage: .backendExecution,
                path: path,
                format: .spef
            )
        }
        let records = try rawRecords + [
            record(
                id: "ir-\(cornerID)",
                kind: .parasiticIR,
                stage: .persistence,
                path: resolvedIRFile,
                format: .json
            ),
            record(
                id: "log-\(cornerID)",
                kind: .log,
                stage: .backendExecution,
                path: resolvedLogFile,
                format: .text
            ),
        ]
        guard let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001") else {
            throw StudioError.projectLoadFailed("Invalid PEX manifest fixture run identifier.")
        }
        let manifest = PEXArtifactManifest(
            runID: PEXRunID(identifier),
            requestHash: PEXRequestHash("abc"),
            backendID: "mock",
            status: .success,
            startedAt: createdAt,
            finishedAt: createdAt.addingTimeInterval(1),
            corners: [
                PEXArtifactCorner(
                    cornerID: corner,
                    status: .success,
                    artifactIDs: records.map(\.id)
                ),
            ],
            artifacts: records,
            warnings: [PEXWarning(stage: .reporting, message: "low confidence")]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(manifest), as: UTF8.self)
    }

    private func pexEngineIRJSON(cornerID: String) -> String {
        """
        {
          "version": "1.0",
          "cornerID": { "value": "\(cornerID)" },
          "units": {
            "resistance": "kohm",
            "capacitance": "fF",
            "coordinate": "um"
          },
          "nets": [],
          "elements": [
            {
              "id": "r_net_1",
              "kind": "resistor",
              "nodeA": { "netName": { "value": "in" }, "nodeName": { "value": "in_1" } },
              "nodeB": { "netName": { "value": "out" }, "nodeName": { "value": "out_1" } },
              "value": 0.0125,
              "source": "extracted"
            },
            {
              "id": "c_out_gnd",
              "kind": "capacitor",
              "nodeA": { "netName": { "value": "out" }, "nodeName": { "value": "out_1" } },
              "nodeB": null,
              "value": 1,
              "source": "extracted"
            },
            {
              "id": "cc_in_out",
              "kind": "coupling",
              "nodeA": { "netName": { "value": "in" }, "nodeName": { "value": "in_1" } },
              "nodeB": { "netName": { "value": "out" }, "nodeName": { "value": "out_1" } },
              "value": 2,
              "source": "extracted"
            }
          ],
          "metadata": {}
        }
        """
    }

    private func artifactDigest(_ data: Data) -> String {
        PEXRequestHash.compute(from: data).value
    }

    private func writeArtifact(_ data: Data, relativePath: String, in runDirectory: URL) throws {
        let url = runDirectory.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private func makeTechnologyIR() -> TechnologyIR {
        TechnologyIR(
            processName: "test_process",
            stack: [
                TechnologyLayer(
                    name: "M1",
                    order: 0,
                    thickness: 0.1,
                    material: "copper",
                    resistivity: 1.7e-8
                ),
            ],
            logicalToPhysicalLayerMap: [:],
            vias: [],
            defaultExtractionRules: .default,
            backendHints: [:]
        )
    }
}

private struct FixturePEXExtractor: PEXExtracting {
    let backendID = "mock"
    let capabilities = PEXBackendCapabilities(
        supportsCouplingCaps: true,
        supportsCornerSweep: false,
        supportsIncremental: false,
        supportsRCReduction: false,
        nativeOutputFormats: [.spef]
    )

    func prepare(_ context: PEXExecutionContext) async throws {
        try FileManager.default.createDirectory(
            at: context.rawOutputDirectory,
            withIntermediateDirectories: true
        )
    }

    func execute(_ context: PEXExecutionContext) async throws -> PEXAdapterExecutionResult {
        let outputURL = context.rawOutputDirectory.appending(path: "\(context.corner.id.value).spef")
        let binaryDigest = try SHA256ContentDigester().digest(
            data: Data("fixture-pex-extractor:1.0".utf8),
            using: .sha256
        )
        let executionIdentity = try PEXBackendExecutionIdentity(
            producer: ProducerIdentity(
                kind: .tool,
                identifier: "pex-mock",
                version: "1.0",
                build: binaryDigest.hexadecimalValue
            ),
            binaryDigest: binaryDigest,
            invocation: .inProcess(entryPoint: "FixturePEXExtractor.execute"),
            environment: ExecutionEnvironmentFingerprint(
                platform: "test",
                architecture: "test",
                toolchain: "fixture"
            )
        )
        let spef = """
        *SPEF "IEEE 1481-1998"
        *DESIGN "\(context.topCell)"
        *DATE "2026-07-17"
        *VENDOR "CircuitStudioTests"
        *PROGRAM "FixturePEXExtractor"
        *VERSION "1.0"
        *DESIGN_FLOW "EXTERNAL"
        *DIVIDER /
        *DELIMITER :
        *BUS_DELIMITER [ ]
        *T_UNIT 1 NS
        *C_UNIT 1 PF
        *R_UNIT 1 OHM
        *L_UNIT 1 HENRY
        *PORTS
        data_out_1 O
        *D_NET data_out_1 0.05
        *CONN
        *P data_out_1 O
        *CAP
        1 data_out_1:1 0.05
        *RES
        1 data_out_1:1 data_out_1:2 10.0
        *END
        """
        try Data(spef.utf8).write(to: outputURL, options: .atomic)
        return PEXAdapterExecutionResult(
            rawOutput: PEXRawOutput(
                format: .spef,
                fileURLs: [outputURL],
                logURL: nil,
                metadata: ["source": "fixture"]
            ),
            generatedArtifacts: [
                PEXGeneratedArtifact(
                    kind: .rawOutput,
                    stage: .backendExecution,
                    cornerID: context.corner.id,
                    url: outputURL
                )
            ],
            executionIdentity: executionIdentity
        )
    }

    func cleanup(_ context: PEXExecutionContext) async {}
}
