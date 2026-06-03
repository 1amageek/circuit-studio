import Foundation
import Testing
@testable import CircuitStudioApp

/// F2: design-by-reference → materialized GDS → live signoff. Verifies that a
/// real PDK cell, referenced by name, is materialized to a GDS that passes real
/// DRC+LVS — no hand-supplied layout file. Gated on the toolchain.
@Suite("PDK cell materialization → signoff (gated)")
struct PDKCellLayoutServiceTests {

    static let layout = PDKCellLayoutService.locate()

    private func fixture(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "lvs"))
    }

    private func makeDir(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "PDKCellLayout-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test(
        "An inverter materialized by name passes real DRC+LVS",
        .enabled(if: PDKCellLayoutServiceTests.layout != nil),
        .timeLimit(.minutes(3))
    )
    func materializeAndSignoff() async throws {
        let layout = try #require(Self.layout)
        let work = try makeDir("materialize")
        defer { removeCoreTestTemporaryDirectory(work) }
        let cell = "sky130_fd_sc_hd__inv_1"

        let gds = try await layout.materialize(cell: cell, into: work.appending(path: "layout"))
        #expect(FileManager.default.fileExists(atPath: gds.path(percentEncoded: false)))

        let review = try await DesignFlowService().runLiveSignoff(
            layoutGDS: gds,
            topCell: cell,
            schematicNetlist: try fixture("inv_schematic", "spice"),
            artifactDirectory: work.appending(path: "signoff")
        )
        #expect(review.passed, "a materialized foundry cell must pass DRC+LVS")
    }

    @Test(
        "Materializing an unknown cell fails loud",
        .enabled(if: PDKCellLayoutServiceTests.layout != nil),
        .timeLimit(.minutes(2))
    )
    func unknownCellFailsLoud() async throws {
        let layout = try #require(Self.layout)
        let work = try makeDir("unknown")
        defer { removeCoreTestTemporaryDirectory(work) }
        await #expect(throws: PDKCellLayoutService.LayoutError.self) {
            _ = try await layout.materialize(cell: "no_such_cell_xyz", into: work)
        }
    }
}
