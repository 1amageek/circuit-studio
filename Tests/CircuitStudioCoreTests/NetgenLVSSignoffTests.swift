import Foundation
import Testing
@testable import CircuitStudioApp

/// Integration tests for the real Netgen-driven LVS signoff. They run an actual
/// `netgen` process against the installed Sky130 setup, so they are gated on the
/// toolchain (`NetgenLVSSignoff.locate()`) and skipped where Netgen + the PDK are
/// absent. The normalization contract is covered without Netgen by
/// `ExternalSignoffReportParserTests`.
@Suite("Netgen LVS signoff (real tool, gated)")
struct NetgenLVSSignoffTests {

    static let toolchain = NetgenLVSSignoff.locate()
    private let topCell = "sky130_fd_sc_hd__inv_1"

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "spice", subdirectory: "lvs"),
            "missing fixture lvs/\(name).spice"
        )
        return url.path(percentEncoded: false)
    }

    private func makeArtifactDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "NetgenLVSSignoffTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test(
        "Matching layout and schematic pass LVS",
        .enabled(if: NetgenLVSSignoffTests.toolchain != nil),
        .timeLimit(.minutes(2))
    )
    func matchingNetlistsPass() throws {
        let tool = try #require(Self.toolchain)
        let artifacts = try makeArtifactDirectory("match")
        defer { try? FileManager.default.removeItem(at: artifacts) }

        let command = tool.command(
            layoutNetlistPath: try fixture("inv_layout"),
            schematicNetlistPath: try fixture("inv_schematic"),
            topCell: topCell,
            artifactDirectory: artifacts
        )
        let result = try ExternalSignoffCommandService(parser: NetgenLVSSignoff.reportParser).run(
            command: command,
            artifactDirectory: artifacts
        )

        #expect(result.exitCode == 0)
        #expect(result.report.kind == .lvs)
        #expect(!result.report.diagnostics.contains { $0.severity == .error })
        #expect(result.report.passed)
        #expect(result.standardOutput.contains("LVS_RESULT status=match"))
    }

    @Test(
        "A layout missing a device fails LVS with an LVS_MISMATCH diagnostic",
        .enabled(if: NetgenLVSSignoffTests.toolchain != nil),
        .timeLimit(.minutes(2))
    )
    func mismatchedNetlistsFail() throws {
        let tool = try #require(Self.toolchain)
        let artifacts = try makeArtifactDirectory("mismatch")
        defer { try? FileManager.default.removeItem(at: artifacts) }

        let command = tool.command(
            layoutNetlistPath: try fixture("inv_layout_broken"),
            schematicNetlistPath: try fixture("inv_schematic"),
            topCell: topCell,
            artifactDirectory: artifacts
        )
        let result = try ExternalSignoffCommandService(parser: NetgenLVSSignoff.reportParser).run(
            command: command,
            artifactDirectory: artifacts
        )

        #expect(result.exitCode == 0)
        let errors = result.report.diagnostics.filter { $0.severity == .error }
        #expect(!errors.isEmpty, "expected an LVS mismatch diagnostic")
        #expect(errors.contains { $0.ruleID == "LVS_MISMATCH" })
        #expect(!result.report.passed)
    }
}
