import Foundation
import Testing
@testable import CircuitStudioApp

/// Integration tests for the real Magic-driven DRC signoff. These exercise an
/// actual `magic` process against the installed Sky130 PDK, so they are gated on
/// the toolchain being present (`MagicDRCSignoff.locate()`); they are skipped
/// rather than failing on machines without Magic + the PDK. The mock/golden-log
/// path remains covered by the other signoff tests.
@Suite("Magic DRC signoff (real tool, gated)")
struct MagicDRCSignoffTests {

    static let toolchain = MagicDRCSignoff.locate()

    @Test(
        "Foundry standard cell passes DRC with no violations",
        .enabled(if: MagicDRCSignoffTests.toolchain != nil),
        .timeLimit(.minutes(2))
    )
    func cleanCellPasses() throws {
        let tool = try #require(Self.toolchain)
        let artifacts = try makeArtifactDirectory("clean")
        defer { try? FileManager.default.removeItem(at: artifacts) }

        // The inverter ships in the PDK; no GDS is supplied, so the driver loads
        // it through the magicrc search path.
        let command = tool.command(
            cell: "sky130_fd_sc_hd__inv_1",
            artifactDirectory: artifacts
        )
        let result = try ExternalSignoffCommandService(parser: MagicDRCSignoff.reportParser).run(
            command: command,
            artifactDirectory: artifacts
        )

        #expect(result.exitCode == 0)
        #expect(result.report.kind == .drc)
        #expect(result.report.toolName == "magic")
        #expect(!result.report.diagnostics.contains { $0.severity == .error })
        #expect(result.report.passed)
        #expect(result.standardOutput.contains("DRC_SUMMARY total=0"))
    }

    @Test(
        "met1 spacing violation in a GDS is detected and attributed to met1.2",
        .enabled(if: MagicDRCSignoffTests.toolchain != nil),
        .timeLimit(.minutes(2))
    )
    func violationDetected() throws {
        let tool = try #require(Self.toolchain)
        let gds = try #require(
            Bundle.module.url(
                forResource: "met1_spacing_violation",
                withExtension: "gds",
                subdirectory: "magic"
            ),
            "missing fixture magic/met1_spacing_violation.gds"
        )
        let artifacts = try makeArtifactDirectory("violation")
        defer { try? FileManager.default.removeItem(at: artifacts) }

        let command = tool.command(
            cell: "drc_broken",
            gdsPath: gds.path(percentEncoded: false),
            artifactDirectory: artifacts
        )
        let result = try ExternalSignoffCommandService(parser: MagicDRCSignoff.reportParser).run(
            command: command,
            artifactDirectory: artifacts
        )

        #expect(result.exitCode == 0)
        let errors = result.report.diagnostics.filter { $0.severity == .error }
        #expect(!errors.isEmpty, "expected at least one DRC violation")
        #expect(errors.contains { $0.ruleID == "met1.2" },
                "expected the metal1 spacing rule (met1.2); got \(errors.map(\.ruleID))")
        // A run that finds a violation ran successfully but must not pass.
        #expect(!result.report.passed)
    }

    private func makeArtifactDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "MagicDRCSignoffTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
