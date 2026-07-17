import Foundation
import Testing
@testable import CircuitStudioCore
import PEXEngine

@Suite("PEX extraction service")
struct PEXExtractionServiceTests {
    @Test func savedManifestLoaderLoadsIR() throws {
        let manifestURL = try fixtureURL(
            "manifest",
            extension: "json",
            subdirectory: "pex/golden-voltage-divider"
        )

        let result = try SavedPEXManifestLoader().load(
            manifestURL: manifestURL,
            cornerID: "tt_25c_1v0"
        )

        #expect(result.runResult == nil)
        #expect(result.manifest.backendID == "golden-fixture")
        #expect(result.ir.cornerID.value == "tt_25c_1v0")
        #expect(result.ir.elements.count == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func extractionUsesInjectedPEXRunner() async throws {
        let root = try makeTemporaryRoot("direct-engine")
        defer { removeTemporaryRoot(root) }
        let manifestURL = try fixtureURL(
            "manifest",
            extension: "json",
            subdirectory: "pex/golden-voltage-divider"
        )
        let resolver = try PEXArtifactResolver(manifestURL: manifestURL)
        let manifest = resolver.manifest
        let canonicalIR = try resolver.loadIR(cornerID: "tt_25c_1v0")
        let runResult = try PEXRunResult(
            runID: manifest.runID,
            requestHash: manifest.requestHash,
            status: .success,
            startedAt: manifest.startedAt,
            finishedAt: manifest.finishedAt,
            cornerResults: [
                PEXCornerResult(
                    cornerID: "tt_25c_1v0",
                    status: .success,
                    ir: canonicalIR,
                    metrics: PEXCornerMetrics(
                        durationSeconds: 0.1,
                        netCount: canonicalIR.nets.count,
                        elementCount: canonicalIR.elements.count
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
        let configURL = root.appending(path: "pex-config.json")
        try writeConfig(to: configURL, enabled: true)

        let result = try await PEXExtractionService(
            engine: StubPEXRunner(result: runResult)
        ).extract(PEXExtractionRequest(
            configURL: configURL,
            workspaceDirectory: root.appending(path: "workspace"),
            cornerID: "tt_25c_1v0",
            executablePath: "/opt/pex/mock"
        ))

        #expect(result.runResult == runResult)
        #expect(result.manifestURL == manifestURL)
        #expect(result.ir.elements.count == canonicalIR.elements.count)
    }

    @Test func disabledConfigurationIsRejectedBeforeExecution() async throws {
        let root = try makeTemporaryRoot("disabled")
        defer { removeTemporaryRoot(root) }
        let configURL = root.appending(path: "pex-config.json")
        try writeConfig(to: configURL, enabled: false)

        await #expect(throws: PEXExtractionError.disabledConfiguration) {
            _ = try await PEXExtractionService(
                engine: RejectingPEXRunner()
            ).extract(PEXExtractionRequest(configURL: configURL))
        }
    }

    private func writeConfig(to url: URL, enabled: Bool) throws {
        let config = PEXProjectConfig(
            enabled: enabled,
            topCell: "TOP",
            backendID: "mock",
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
            .appending(path: "CircuitStudioPEXExtractionServiceTests-\(name)-\(UUID().uuidString)")
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
}
