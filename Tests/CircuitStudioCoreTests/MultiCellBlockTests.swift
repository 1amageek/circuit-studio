import Foundation
import Testing
import PEXEngine
@testable import CircuitStudioApp

/// F3: a real multi-cell block (two abuttable Sky130 inverter instances composed
/// into a parent cell) through real DRC + real PEX. Both scale to a hierarchical,
/// multi-instance layout. Gated on the toolchain.
///
/// Block-level LVS is intentionally out of scope here: an independent block
/// schematic must come from a design netlist produced by place-and-route (the
/// layout's exact hierarchical/substrate topology can't be hand-authored
/// reliably). Single-cell LVS is covered by LiveSignoffServiceTests /
/// PDKBlockSignoffTests; block DRC + PEX are the verifiable multi-cell pieces.
@Suite("Multi-cell block: DRC + PEX (gated)")
struct MultiCellBlockTests {

    static let available = MagicDRCSignoff.locate() != nil && MagicToolchain.locate() != nil
    private let topCell = "inv_pair"

    private func blockGDS() throws -> URL {
        try #require(Bundle.module.url(forResource: "inv_pair", withExtension: "gds", subdirectory: "lvs"))
    }

    private func makeDir(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "MultiCellBlock-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test(
        "A two-cell block is DRC-clean",
        .enabled(if: MultiCellBlockTests.available),
        .timeLimit(.minutes(3))
    )
    func blockDRCClean() throws {
        let drc = try #require(MagicDRCSignoff.locate())
        let work = try makeDir("drc")
        defer { try? FileManager.default.removeItem(at: work) }

        let result = try ExternalSignoffCommandService(parser: MagicDRCSignoff.reportParser).run(
            command: drc.command(cell: topCell, gds: try blockGDS(), artifactDirectory: work),
            artifactDirectory: work
        )
        #expect(result.report.passed, "the composed block must be DRC-clean")
        #expect(!result.report.diagnostics.contains { $0.severity == .error })
    }

    @Test(
        "PEX extracts the whole block's parasitics across both cells",
        .enabled(if: MultiCellBlockTests.available),
        .timeLimit(.minutes(3))
    )
    func blockPEX() async throws {
        let work = try makeDir("pex")
        defer { try? FileManager.default.removeItem(at: work) }
        let netlist = work.appending(path: "top.cir")
        try Data("* placeholder\n.end\n".utf8).write(to: netlist)
        let tech = TechnologyIR(
            processName: "sky130A", stack: [], logicalToPhysicalLayerMap: [:],
            vias: [], defaultExtractionRules: .default, backendHints: [:]
        )
        let request = PEXRunRequest(
            layoutURL: try blockGDS(), layoutFormat: .gds,
            sourceNetlistURL: netlist, sourceNetlistFormat: .spice,
            topCell: topCell, corners: [PEXCorner(id: "tt")],
            technology: .inline(tech),
            backendSelection: PEXBackendSelection(backendID: "magic"),
            options: PEXRunOptions(
                extractMode: .cOnly, includeCouplingCaps: true,
                minCapacitanceF: nil, minResistanceOhm: nil, maxParallelJobs: 1,
                emitRawArtifacts: true, emitIRJSON: true, strictValidation: false
            ),
            workingDirectory: work.appending(path: "pex")
        )
        let result = try await DefaultPEXEngine.withDefaults().run(request)
        #expect(result.status == .success)
        let ir = try #require(result.cornerResults.first?.ir)
        // Two inverters' worth of parasitics — more than a single inverter (15).
        #expect(ir.elements.count > 25, "expected the block's parasitics, got \(ir.elements.count)")
        #expect(ParasiticIRValidator().validate(ir).isValid)
    }
}
