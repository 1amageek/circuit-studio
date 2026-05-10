import Foundation
import Testing
@testable import CircuitStudioCore

@Suite("PEXBackendAdapter Tests")
struct PEXBackendAdapterTests {
    @Test func savedManifestAdapterLoadsIR() throws {
        let manifestURL = try fixtureURL(
            "manifest",
            extension: "json",
            subdirectory: "pex/golden-voltage-divider"
        )

        let result = try SavedPEXManifestBackendAdapter().extract(request: PEXBackendExtractionRequest(
            configURL: manifestURL,
            cornerID: "tt_25c_1v0"
        ))

        #expect(result.commandResult == nil)
        #expect(result.artifacts.backendID == "golden-fixture")
        #expect(result.ir.cornerID == "tt_25c_1v0")
        #expect(result.ir.elements.count == 3)
    }

    @Test func pexEngineCommandAdapterLoadsManifestFromJSONOutput() throws {
        let root = try makeTemporaryRoot("command")
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

        let result = try PEXEngineCommandBackendAdapter(
            executablePath: "/definitely/missing/pexengine"
        ).extract(request: PEXBackendExtractionRequest(
            configURL: configURL,
            cornerID: "tt_25c_1v0",
            executablePath: executable.path(percentEncoded: false),
            additionalArguments: ["--json"]
        ))

        #expect(result.commandResult?.commandLine == [
            executable.path(percentEncoded: false),
            "extract",
            "--config",
            configURL.path(percentEncoded: false),
            "--json",
        ])
        #expect(result.artifacts.manifestURL == runDirectory.appending(path: "manifest.json"))
        #expect(result.ir.elements == [
            PEXParasiticElement(
                id: "r_out",
                kind: .resistor,
                nodeA: "out",
                nodeB: "0",
                value: 12.0
            ),
        ])
    }

    @Test func pexEngineCommandAdapterRejectsMissingManifestURL() throws {
        let root = try makeTemporaryRoot("missing-manifest-url")
        defer { removeTemporaryRoot(root) }
        let configURL = root.appending(path: "pex-config.json")
        try "{}".write(to: configURL, atomically: true, encoding: .utf8)
        let executable = try writeExecutable(
            named: "mock-pexengine",
            in: root,
            contents: """
            #!/bin/sh
            printf '{}\\n'
            exit 0
            """
        )

        #expect(throws: PEXBackendAdapterError.missingManifestURLInCommandOutput) {
            _ = try PEXEngineCommandBackendAdapter(
                executablePath: executable.path(percentEncoded: false)
            ).extract(request: PEXBackendExtractionRequest(
                configURL: configURL,
                cornerID: "tt_25c_1v0"
            ))
        }
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
          "cornerID": "tt_25c_1v0",
          "units": { "resistance": "ohm", "capacitance": "F", "coordinate": "um" },
          "elements": [
            {
              "id": "r_out",
              "kind": "resistor",
              "nodeA": { "netName": "out", "nodeName": "out" },
              "nodeB": { "netName": "0", "nodeName": "0" },
              "value": 12.0
            }
          ]
        }
        """.write(to: irDirectory.appending(path: "tt_25c_1v0.json"), atomically: true, encoding: .utf8)
        try """
        {
          "version": 2,
          "runID": { "value": "00000000-0000-0000-0000-000000000200" },
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
            .appending(path: "CircuitStudioPEXBackendAdapterTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
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

    private func writeExecutable(named name: String, in root: URL, contents: String) throws -> URL {
        let url = root.appending(path: name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path(percentEncoded: false)
        )
        return url
    }
}
