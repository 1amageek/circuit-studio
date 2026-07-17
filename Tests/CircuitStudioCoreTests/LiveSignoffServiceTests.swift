import CircuitSignoff
import Foundation
import LVSCore
import LVSExtractionAdapters
import Testing
@testable import CircuitStudioApp

/// Integration tests for live signoff: real Magic DRC + Magic LVS-extraction +
/// Netgen LVS producing an ExternalSignoffReview. Gated on the toolchain
/// (LiveSignoffService.locate()), skipped where Magic/Netgen/PDK are absent.
/// Edge cases: clean pass, LVS mismatch, DRC violation, extractor failing loud.
@Suite("Live signoff (real DRC+LVS, gated)")
struct LiveSignoffServiceTests {

    static let service = LiveSignoffService.locate()
    private let topCell = "sky130_fd_sc_hd__inv_1"

    private func fixture(_ name: String, _ ext: String) throws -> URL {
        try #require(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "lvs"),
            "missing fixture lvs/\(name).\(ext)"
        )
    }

    private func makeArtifactDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "LiveSignoffServiceTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test(
        "A clean layout passes both DRC and LVS",
        .enabled(if: LiveSignoffServiceTests.service != nil),
        .timeLimit(.minutes(3))
    )
    func cleanLayoutPasses() async throws {
        let service = try #require(Self.service)
        let artifacts = try makeArtifactDirectory("clean")
        defer { removeCoreTestTemporaryDirectory(artifacts) }

        let review = try await service.run(
            layoutGDS: try fixture("inv1", "gds"),
            topCell: topCell,
            schematicNetlist: try fixture("inv_schematic", "spice"),
            artifactDirectory: artifacts
        )

        #expect(review.passed)
        #expect(review.reports.count == 2)
        #expect(review.reports.contains { $0.kind == .drc && $0.passed })
        #expect(review.reports.contains { $0.kind == .lvs && $0.passed })
    }

    @Test(
        "A wrong schematic fails LVS while DRC still passes",
        .enabled(if: LiveSignoffServiceTests.service != nil),
        .timeLimit(.minutes(3))
    )
    func wrongSchematicFailsLVS() async throws {
        let service = try #require(Self.service)
        let artifacts = try makeArtifactDirectory("lvs-mismatch")
        defer { removeCoreTestTemporaryDirectory(artifacts) }

        let review = try await service.run(
            layoutGDS: try fixture("inv1", "gds"),
            topCell: topCell,
            schematicNetlist: try fixture("inv_schematic_wrong", "spice"),
            artifactDirectory: artifacts
        )

        #expect(!review.passed)
        let drc = try #require(review.reports.first { $0.kind == .drc })
        let lvs = try #require(review.reports.first { $0.kind == .lvs })
        #expect(drc.passed, "DRC should still pass on the clean inv1 layout")
        #expect(!lvs.passed)
        #expect(lvs.diagnostics.contains { $0.ruleID == "LVS_MISMATCH" })
    }

    @Test(
        "A DRC-violating layout fails the DRC report",
        .enabled(if: LiveSignoffServiceTests.service != nil),
        .timeLimit(.minutes(3))
    )
    func drcViolationFailsDRC() async throws {
        let service = try #require(Self.service)
        let artifacts = try makeArtifactDirectory("drc-violation")
        defer { removeCoreTestTemporaryDirectory(artifacts) }

        // The met1-spacing-violation plate (cell "drc_broken").
        let brokenGDS = try #require(
            Bundle.module.url(forResource: "met1_spacing_violation", withExtension: "gds", subdirectory: "magic")
        )
        let review = try await service.run(
            layoutGDS: brokenGDS,
            topCell: "drc_broken",
            schematicNetlist: try fixture("inv_schematic", "spice"),
            artifactDirectory: artifacts
        )

        #expect(!review.passed)
        let drc = try #require(review.reports.first { $0.kind == .drc })
        #expect(!drc.passed)
        #expect(drc.diagnostics.contains { $0.ruleID == "met1.2" })
    }

    @Test(
        "The layout extractor fails loud on a missing cell",
        .enabled(if: LiveSignoffServiceTests.service != nil),
        .timeLimit(.minutes(2))
    )
    func extractorFailsLoudOnMissingCell() async throws {
        let extractor = try #require(MagicLayoutNetlistExtractor.locate())
        let artifacts = try makeArtifactDirectory("extract-fail")
        defer { removeCoreTestTemporaryDirectory(artifacts) }

        await #expect(throws: LVSError.self) {
            _ = try await extractor.extractLayoutNetlist(
                gds: try fixture("inv1", "gds"),
                topCell: "no_such_cell_xyz",
                into: artifacts,
                timeoutSeconds: 300
            )
        }
    }
}
