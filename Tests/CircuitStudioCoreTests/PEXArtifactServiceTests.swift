import Foundation
import Testing
@testable import CircuitStudioCore
import PEXEngine

@Suite("PEXArtifactService Tests")
struct PEXArtifactServiceTests {

    @Test func loadArtifactsResolvesManifestPaths() throws {
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
        try manifestJSON(runID: "run-1", cornerID: "tt")
            .write(to: manifestURL, atomically: true, encoding: .utf8)

        let artifacts = try PEXArtifactService().loadArtifacts(manifestURL: manifestURL)

        #expect(artifacts.runID == "run-1")
        #expect(artifacts.backendID == "mock")
        #expect(artifacts.status == "success")
        #expect(artifacts.warnings == ["low confidence"])
        #expect(artifacts.corners.count == 1)
        #expect(artifacts.corners[0].cornerID == "tt")
        #expect(artifacts.corners[0].irURL == runDirectory.appending(path: "ir").appending(path: "tt.json"))
        #expect(artifacts.corners[0].rawFileURLs == [
            runDirectory.appending(path: "raw").appending(path: "tt").appending(path: "tt.spef"),
        ])
        #expect(artifacts.corners[0].logURL == runDirectory.appending(path: "raw").appending(path: "tt").appending(path: "extraction.log"))
    }

    @Test func loadIRDecodesParasiticElements() throws {
        let root = try makeTemporaryRoot("ir")
        defer { removeTemporaryRoot(root) }

        let irURL = root.appending(path: "tt.json")
        try irJSON(cornerID: "tt").write(to: irURL, atomically: true, encoding: .utf8)

        let ir = try PEXArtifactService().loadIR(from: irURL)

        #expect(ir.version == "1.0")
        #expect(ir.cornerID == "tt")
        #expect(ir.units == .canonical)
        #expect(ir.elements.count == 3)
        #expect(ir.elements[0] == PEXParasiticElement(
            id: "r_net_1",
            kind: .resistor,
            nodeA: "in_1",
            nodeB: "out_1",
            value: 12.5
        ))
        #expect(ir.elements[1].kind == .capacitor)
        #expect(ir.elements[1].nodeB == nil)
        #expect(ir.elements[1].value == 1e-15)
        #expect(ir.elements[2].kind == .coupling)
        #expect(ir.elements[2].nodeB == "out_1")
        #expect(ir.elements[2].value == 2e-15)
        #expect(ir.diagnostics.count == 2)
        #expect(ir.diagnostics.contains { $0.elementID == "zero" })
        #expect(ir.diagnostics.contains { $0.elementID == "unsupported" })
    }

    @Test func loadIRForCornerUsesManifestArtifact() throws {
        let root = try makeTemporaryRoot("corner")
        defer { removeTemporaryRoot(root) }

        let runDirectory = root.appending(path: "run-1")
        let irDirectory = runDirectory.appending(path: "ir")
        try FileManager.default.createDirectory(at: irDirectory, withIntermediateDirectories: true)
        let manifestURL = runDirectory.appending(path: "manifest.json")
        try manifestJSON(runID: "run-1", cornerID: "tt")
            .write(to: manifestURL, atomically: true, encoding: .utf8)
        try irJSON(cornerID: "tt")
            .write(to: irDirectory.appending(path: "tt.json"), atomically: true, encoding: .utf8)

        let service = PEXArtifactService()
        let artifacts = try service.loadArtifacts(manifestURL: manifestURL)
        let ir = try service.loadIR(for: "tt", artifacts: artifacts)

        #expect(ir.cornerID == "tt")
        #expect(ir.elements.count == 3)
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
            backendSelection: .mock(),
            options: .default,
            workingDirectory: root
        )
        let result = try await DefaultPEXEngine.withDefaults().run(request)

        #expect(result.status == .success)
        #expect(result.artifacts.manifestURL.path(percentEncoded: false).hasPrefix(root.path(percentEncoded: false)))

        let artifactService = PEXArtifactService()
        let artifacts = try artifactService.loadArtifacts(manifestURL: result.artifacts.manifestURL)
        let ir = try artifactService.loadIR(for: "tt", artifacts: artifacts)
        let postLayoutNetlist = PostLayoutSimulationService().buildPostLayoutNetlist(
            baseNetlist: try String(contentsOf: netlistURL, encoding: .utf8),
            parasitics: ir
        )

        #expect(artifacts.status == "success")
        #expect(artifacts.corners.count == 1)
        #expect(ir.elements.count > 0)
        #expect(ir.diagnostics.isEmpty)
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
        let artifacts = try service.loadArtifacts(manifestURL: manifestURL)
        let ir = try service.loadIR(for: "tt_25c_1v0", artifacts: artifacts)

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

        #expect(artifacts.runID == "golden-voltage-divider")
        #expect(artifacts.backendID == "golden-fixture")
        #expect(artifacts.status == "success")
        #expect(artifacts.corners.count == 1)
        #expect(artifacts.corners[0].rawFileURLs.count == 1)
        #expect(artifacts.corners[0].logURL?.lastPathComponent == "extraction.log")
        #expect(ir.units == .canonical)
        #expect(ir.elements.count == 3)
        #expect(ir.elements.contains(PEXParasiticElement(
            id: "r_out_segment",
            kind: .resistor,
            nodeA: "out",
            nodeB: "out_pex",
            value: 1.5
        )))
        let substrateCapacitor = try #require(ir.elements.first { $0.id == "c_out_to_substrate" })
        #expect(substrateCapacitor.kind == .capacitor)
        #expect(substrateCapacitor.nodeA == "out_pex")
        #expect(substrateCapacitor.nodeB == nil)
        #expect(abs(substrateCapacitor.value - 4.2e-15) < 1.0e-27)
        #expect(postLayoutNetlist.contains("RPEX_r_out_segment out out_pex 1.5"))
        #expect(postLayoutNetlist.contains("CPEX_c_out_to_substrate out_pex 0 4.2e-15"))
        #expect(result.status == .completed)
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

    private func manifestJSON(runID: String, cornerID: String) -> String {
        """
        {
          "version": 1,
          "runID": { "value": "\(runID)" },
          "requestHash": { "value": "abc" },
          "backendID": "mock",
          "status": "success",
          "startedAt": "2026-05-07T00:00:00Z",
          "finishedAt": "2026-05-07T00:00:01Z",
          "corners": [
            {
              "cornerID": { "value": "\(cornerID)" },
              "status": "success",
              "rawFiles": ["\(cornerID).spef"],
              "irFile": "\(cornerID).json",
              "logFile": "extraction.log"
            }
          ],
          "warnings": ["low confidence"]
        }
        """
    }

    private func irJSON(cornerID: String) -> String {
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
            },
            {
              "id": "zero",
              "kind": "capacitor",
              "nodeA": { "netName": { "value": "out" }, "nodeName": { "value": "out_1" } },
              "nodeB": null,
              "value": 0,
              "source": "extracted"
            },
            {
              "id": "unsupported",
              "kind": "inductor",
              "nodeA": { "netName": { "value": "out" }, "nodeName": { "value": "out_1" } },
              "nodeB": null,
              "value": 1,
              "source": "extracted"
            }
          ]
        }
        """
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
