import CircuitSignoff
import DRCAdapters
import DRCCore
import Foundation
import Testing

@Suite("Magic DRC adapter (real tool, gated)")
struct MagicDRCAdapterIntegrationTests {
    static let toolchain = MagicDRCAdapter.locate()

    @Test(
        "Foundry standard cell passes DRC with no violations",
        .enabled(if: MagicDRCAdapterIntegrationTests.toolchain != nil),
        .timeLimit(.minutes(2))
    )
    func cleanCellPasses() async throws {
        let tool = try #require(Self.toolchain)
        let artifacts = try makeArtifactDirectory("clean")
        defer { removeCoreTestTemporaryDirectory(artifacts) }
        let layoutService = try #require(PDKCellLayoutService.locate())
        let layout = try await layoutService.materialize(
            cell: "sky130_fd_sc_hd__inv_1",
            into: artifacts.appending(path: "layout")
        )

        let execution = try await tool.run(DRCRequest(
            layoutURL: layout,
            topCell: "sky130_fd_sc_hd__inv_1",
            layoutFormat: .gds,
            workingDirectory: artifacts
        ))

        #expect(execution.result.toolName == "magic")
        #expect(execution.result.passed)
        #expect(!execution.result.diagnostics.contains { $0.severity == .error })
        let log = try String(contentsOf: URL(filePath: execution.result.logPath), encoding: .utf8)
        #expect(log.contains("DRC_SUMMARY total=0"))
    }

    @Test(
        "met1 spacing violation is attributed to met1.2",
        .enabled(if: MagicDRCAdapterIntegrationTests.toolchain != nil),
        .timeLimit(.minutes(2))
    )
    func violationDetected() async throws {
        let tool = try #require(Self.toolchain)
        let gds = try #require(
            Bundle.module.url(
                forResource: "met1_spacing_violation",
                withExtension: "gds",
                subdirectory: "magic"
            )
        )
        let artifacts = try makeArtifactDirectory("violation")
        defer { removeCoreTestTemporaryDirectory(artifacts) }

        let execution = try await tool.run(DRCRequest(
            layoutURL: gds,
            topCell: "drc_broken",
            layoutFormat: .gds,
            workingDirectory: artifacts
        ))

        let errors = execution.result.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.ruleID == "met1.2" })
        #expect(!execution.result.passed)
    }

    @Test(
        "Missing cell never produces a clean result",
        .enabled(if: MagicDRCAdapterIntegrationTests.toolchain != nil),
        .timeLimit(.minutes(2))
    )
    func missingCellFailsLoud() async throws {
        _ = try #require(Self.toolchain)
        let layoutService = try #require(PDKCellLayoutService.locate())
        let artifacts = try makeArtifactDirectory("missing")
        defer { removeCoreTestTemporaryDirectory(artifacts) }

        await #expect(throws: PDKCellLayoutService.LayoutError.self) {
            _ = try await layoutService.materialize(cell: "no_such_cell_xyz", into: artifacts)
        }
    }

    private func makeArtifactDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "MagicDRCAdapterIntegrationTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
