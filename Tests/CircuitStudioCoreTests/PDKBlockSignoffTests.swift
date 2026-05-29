import Foundation
import Testing
import PEXEngine
@testable import CircuitStudioApp

/// B (PDK-scale summit): the full real flow on a nontrivial Sky130 standard cell
/// — a 24-transistor D flip-flop (sky130_fd_sc_hd__dfxtp_1), 12x the inverter —
/// run through real DRC + real LVS + real PEX. Gated on the toolchain.
@Suite("PDK-scale signoff: D flip-flop (gated)")
struct PDKBlockSignoffTests {

    static let available = LiveSignoffService.locate() != nil && MagicToolchain.locate() != nil
    private let topCell = "sky130_fd_sc_hd__dfxtp_1"

    private func fixture(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "lvs"))
    }

    @Test(
        "A 24-transistor flip-flop passes real DRC+LVS and extracts real parasitics",
        .enabled(if: PDKBlockSignoffTests.available),
        .timeLimit(.minutes(5))
    )
    func flipFlopFullFlow() async throws {
        let work = FileManager.default.temporaryDirectory.appending(path: "PDKBlock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let gds = try fixture("dff", "gds")

        // Real DRC + LVS on the flip-flop layout vs its schematic.
        let review = try DesignFlowService().runLiveSignoff(
            layoutGDS: gds,
            topCell: topCell,
            schematicNetlist: try fixture("dff_schematic", "spice"),
            artifactDirectory: work.appending(path: "signoff")
        )
        #expect(review.passed, "DFF must pass DRC and LVS")
        let lvs = try #require(review.reports.first { $0.kind == .lvs })
        #expect(lvs.passed, "DFF layout must match its 24-device schematic")

        // Real PEX on the same layout.
        let netlist = work.appending(path: "top.cir")
        try Data("* placeholder\n.end\n".utf8).write(to: netlist)
        let tech = TechnologyIR(
            processName: "sky130A", stack: [], logicalToPhysicalLayerMap: [:],
            vias: [], defaultExtractionRules: .default, backendHints: [:]
        )
        let request = PEXRunRequest(
            layoutURL: gds, layoutFormat: .gds,
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
        let pexResult = try await DefaultPEXEngine.withDefaults().run(request)
        #expect(pexResult.status == .success)
        let ir = try #require(pexResult.cornerResults.first?.ir)
        // A 24-FET cell has many more parasitics than the inverter.
        #expect(ir.elements.count > 20, "expected a rich parasitic network, got \(ir.elements.count)")
        #expect(ParasiticIRValidator().validate(ir).isValid)
    }
}
