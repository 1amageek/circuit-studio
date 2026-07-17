import Foundation
import LVSAdapters
import LVSCore
import Testing

@Suite("Netgen LVS adapter (real tool, gated)")
struct NetgenLVSAdapterIntegrationTests {
    static let toolchain = NetgenLVSAdapter.locate()
    private let topCell = "sky130_fd_sc_hd__inv_1"

    @Test(
        "Matching layout and schematic pass LVS",
        .enabled(if: NetgenLVSAdapterIntegrationTests.toolchain != nil),
        .timeLimit(.minutes(2))
    )
    func matchingNetlistsPass() async throws {
        let tool = try #require(Self.toolchain)
        let artifacts = try makeArtifactDirectory("match")
        defer { removeCoreTestTemporaryDirectory(artifacts) }

        let execution = try await tool.run(LVSRequest(
            layoutNetlistURL: try fixture("inv_layout"),
            schematicNetlistURL: try fixture("inv_schematic"),
            topCell: topCell,
            workingDirectory: artifacts
        ))

        #expect(execution.result.toolName == "netgen")
        #expect(execution.result.passed)
        #expect(!execution.result.diagnostics.contains { $0.severity == .error })
    }

    @Test(
        "A layout missing a device fails LVS",
        .enabled(if: NetgenLVSAdapterIntegrationTests.toolchain != nil),
        .timeLimit(.minutes(2))
    )
    func mismatchedNetlistsFail() async throws {
        let tool = try #require(Self.toolchain)
        let artifacts = try makeArtifactDirectory("mismatch")
        defer { removeCoreTestTemporaryDirectory(artifacts) }

        let execution = try await tool.run(LVSRequest(
            layoutNetlistURL: try fixture("inv_layout_broken"),
            schematicNetlistURL: try fixture("inv_schematic"),
            topCell: topCell,
            workingDirectory: artifacts
        ))

        #expect(execution.result.diagnostics.contains { $0.ruleID == "LVS_MISMATCH" })
        #expect(!execution.result.passed)
    }

    private func fixture(_ name: String) throws -> URL {
        try #require(
            Bundle.module.url(forResource: name, withExtension: "spice", subdirectory: "lvs")
        )
    }

    private func makeArtifactDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "NetgenLVSAdapterIntegrationTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
