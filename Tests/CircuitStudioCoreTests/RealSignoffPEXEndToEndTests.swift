import Foundation
import Testing
import PEXEngine
@testable import CircuitStudioApp

/// A5: end-to-end proof that all three real backends run on ONE real layout
/// through circuit-studio's own dependencies — real DRC + real LVS (via
/// DesignFlowService.runLiveSignoff) and real PEX (via the same DefaultPEXEngine
/// the pexengine CLI wraps, backendID=magic). Gated on the toolchain.
@Suite("Real DRC+LVS+PEX end-to-end (gated)")
struct RealSignoffPEXEndToEndTests {

    static let available = LiveSignoffService.locate() != nil && MagicToolchain.locate() != nil
    private let topCell = "sky130_fd_sc_hd__inv_1"

    private func lvsFixture(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "lvs"))
    }

    @Test(
        "A real layout passes live DRC+LVS and yields real PEX parasitics",
        .enabled(if: RealSignoffPEXEndToEndTests.available),
        .timeLimit(.minutes(4))
    )
    func fullRealFlow() async throws {
        let work = FileManager.default.temporaryDirectory
            .appending(path: "RealE2E-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let gds = try lvsFixture("inv1", "gds")

        // 1) Real DRC + LVS through the flow's live-signoff entry point.
        let review = try await DesignFlowService().runLiveSignoff(
            layoutGDS: gds,
            topCell: topCell,
            schematicNetlist: try lvsFixture("inv_schematic", "spice"),
            artifactDirectory: work.appending(path: "signoff")
        )
        #expect(review.passed, "live DRC+LVS should pass on the clean inv1 layout")

        // 2) Real PEX on the same layout via the default engine (backendID=magic).
        let netlist = work.appending(path: "top.cir")
        try Data("* placeholder\n.end\n".utf8).write(to: netlist)
        let tech = TechnologyIR(
            processName: "sky130A", stack: [], logicalToPhysicalLayerMap: [:],
            vias: [], defaultExtractionRules: .default, backendHints: [:]
        )
        let request = PEXRunRequest(
            layoutURL: gds,
            layoutFormat: .gds,
            sourceNetlistURL: netlist,
            sourceNetlistFormat: .spice,
            topCell: topCell,
            corners: [PEXCorner(id: "tt")],
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
        #expect(ir.metadata["sourceFormat"] == "magic-spice", "PEX must use the real Magic backend")
        #expect(!ir.elements.isEmpty, "an inverter layout should yield real parasitic elements")
    }
}
