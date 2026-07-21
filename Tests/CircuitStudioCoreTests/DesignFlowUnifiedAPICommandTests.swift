import PEXEngine
import Foundation
import DesignFlowKernel
import Testing
import LayoutCore
@testable import CircuitStudioApp
@testable import CircuitStudioCore
@testable import SchematicEditor

@Suite("DesignFlowService unified API commands", .serialized)
struct DesignFlowUnifiedAPICommandTests {
    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func unifiedAPIRunsHeadlessRoundTrip() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("round-trip")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }

        let service = DesignFlowService()
        let configuration = HeadlessRoundTripService.Configuration(
            projectRoot: root,
            runID: "api-round-trip",
            title: "API round trip",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: ParasiticIR(
                version: "1.0",
                cornerID: "tt_25c_1v0",
                elements: [
                    ParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 0.5),
                    ParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 1e-15),
                ]
            ),
            externalSignoffCommands: try DesignFlowServiceTestSupport.makeSignoffCommands(in: root),
            approvedBy: "api-reviewer",
            approvedAt: Date(timeIntervalSince1970: 2_000),
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        let result = try await service.runRoundTrip(DesignFlowRoundTripRequest(
            schematic: SchematicPreview.voltageDividerViewModel().document,
            configuration: configuration
        ))
        let bottlenecks = try service.summarizeBottlenecks(projectRoot: root)

        #expect(result.manifest.isRoundTripComplete)
        #expect(result.manifest.isReadyForPEX)
        #expect(result.manifest.stages.allSatisfy { $0.status == .passed })
        #expect(bottlenecks.runCount == 1)
        #expect(bottlenecks.mostExpensiveStageName != nil)
    }

    @Test(.timeLimit(.minutes(2)))
    func unifiedAPIRunsSchematicSimulation() async throws {
        let service = DesignFlowService()
        let result = try await service.runSchematicSimulation(DesignFlowSchematicSimulationRequest(
            schematic: SchematicPreview.voltageDividerViewModel().document,
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op])
        ))

        #expect(result.netlist.contains(".op"))
        #expect(result.simulationResult.status == .completed)
        #expect(result.simulationResult.waveform != nil)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func unifiedAPIGeneratesLayoutAndRunsPrePEXVerification() throws {
        let service = DesignFlowService()
        let schematic = SchematicPreview.voltageDividerViewModel().document

        let layout = try service.generateLayout(DesignFlowLayoutGenerationRequest(
            schematic: schematic,
            catalog: .standard()
        ))
        let verification = service.runPrePEXVerification(DesignFlowPrePEXVerificationRequest(
            schematic: schematic,
            layout: layout.document,
            tech: layout.tech,
            designUnit: layout.designUnit,
            catalog: .standard()
        ))

        if !verification.drc.passed {
            Issue.record("Auto-layout DRC violations: \(layout.drcResult.violations.map(\.message).joined(separator: " | "))")
            Issue.record("Auto-layout DRC details: \(layout.drcResult.violations.map { "\($0.kind.rawValue) layer=\($0.layer?.name ?? "-") region=\($0.region) nets=\($0.netIDs)" }.joined(separator: " | "))")
        }
        #expect(layout.unroutedNets.isEmpty)
        #expect(verification.drc.passed)
        #expect(verification.lvs.passed)
        #expect(verification.isLocalPreflightPassing)
        #expect(verification.externalSignoff == nil)
        #expect(!verification.isReadyForPEX)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func unifiedAPIGeneratesRCLowPassLayoutAndRunsPrePEXVerification() throws {
        let service = DesignFlowService()
        let schematic = SchematicPreview.rcLowPassViewModel().document

        let layout = try service.generateLayout(DesignFlowLayoutGenerationRequest(
            schematic: schematic,
            catalog: .standard()
        ))
        let verification = service.runPrePEXVerification(DesignFlowPrePEXVerificationRequest(
            schematic: schematic,
            layout: layout.document,
            tech: layout.tech,
            designUnit: layout.designUnit,
            catalog: .standard()
        ))

        if !verification.isLocalPreflightPassing {
            Issue.record("Auto-layout DRC violations: \(layout.drcResult.violations.map(\.message).joined(separator: " | "))")
            Issue.record("Auto-layout DRC details: \(layout.drcResult.violations.map { "\($0.kind.rawValue) layer=\($0.layer?.name ?? "-") region=\($0.region) nets=\($0.netIDs)" }.joined(separator: " | "))")
            Issue.record("Auto-layout via neighborhood: \(viaNeighborhoodSummary(layout.document, around: layout.drcResult.violations.first?.region))")
            Issue.record("DRC: \(verification.drc)")
            Issue.record("LVS: \(verification.lvs)")
        }

        #expect(layout.unroutedNets.isEmpty)
        #expect(verification.drc.passed)
        #expect(verification.lvs.passed)
        #expect(verification.isLocalPreflightPassing)
        #expect(verification.externalSignoff == nil)
        #expect(!verification.isReadyForPEX)
    }

    private func viaNeighborhoodSummary(_ document: LayoutDocument, around region: LayoutRect?) -> String {
        guard let topCellID = document.topCellID,
              let topCell = document.cell(withID: topCellID),
              let region else {
            return "unavailable"
        }
        let expanded = region.expanded(by: 0.5, 0.5)
        let nearbyShapes = topCell.shapes.filter {
            let box = LayoutGeometryAnalysis.boundingBox(for: $0.geometry)
            return box.intersects(expanded)
        }.map {
            "\($0.layer.name) net=\($0.netID?.uuidString ?? "-") box=\(LayoutGeometryAnalysis.boundingBox(for: $0.geometry))"
        }
        let nearbyVias = topCell.vias.filter {
            expanded.contains($0.position)
        }.map {
            "\($0.viaDefinitionID) net=\($0.netID?.uuidString ?? "-") at=\($0.position)"
        }
        return "vias=[\(nearbyVias.joined(separator: "; "))] shapes=[\(nearbyShapes.joined(separator: "; "))]"
    }

    @Test(.timeLimit(.minutes(2)))
    func unifiedAPIRunsPostLayoutSimulationAndComparison() async throws {
        let service = DesignFlowService()
        let baseNetlist = """
        * Voltage divider fixture
        V1 vin 0 1
        R1 vin out 1000
        R2 out 0 1000
        .op
        .end
        """
        let parasitics = ParasiticIR(
            version: "1.0",
            cornerID: "tt_25c_1v0",
            elements: [
                ParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 0.5),
                ParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 1e-15),
            ]
        )

        let preLayoutResult = try await service.runSPICESimulation(DesignFlowSPICESimulationRequest(
            source: baseNetlist,
            fileName: nil
        ))
        let postLayoutNetlist = service.buildPostLayoutNetlist(
            baseNetlist: baseNetlist,
            parasitics: parasitics
        )
        let postLayoutResult = try await service.runPostLayoutSimulation(DesignFlowPostLayoutSimulationRequest(
            baseNetlist: baseNetlist,
            parasitics: parasitics,
            command: .op
        ))
        let comparison = service.comparePostLayout(
            preLayoutResult: preLayoutResult,
            postLayoutResult: postLayoutResult,
            limits: PostLayoutComparisonLimits(maxAbsoluteDelta: 1.0e-3)
        )

        #expect(postLayoutNetlist.contains("* --- Extracted parasitics ---"))
        #expect(postLayoutResult.status == .completed)
        #expect(comparison.status == "compared")
        #expect(comparison.gateStatus == "passed")
    }

    @Test func unifiedAPILoadsPEXInputWithArtifactPaths() throws {
        let manifestURL = try DesignFlowServiceTestSupport.fixtureURL(
            "manifest",
            extension: "json",
            subdirectory: "pex/golden-voltage-divider"
        )

        let input = try DesignFlowService().loadPEXInput(
            manifestURL: manifestURL,
            cornerID: "ss_125c_0v9"
        )

        #expect(input.ir.cornerID.value == "ss_125c_0v9")
        #expect(input.ir.elements.count == 3)
        #expect(input.artifactPaths.contains { $0.hasSuffix("manifest.json") })
        #expect(input.artifactPaths.contains { $0.hasSuffix("ss_125c_0v9.json") })
        #expect(input.artifactPaths.contains { $0.hasSuffix("voltage-divider.spef") })
        #expect(input.artifactPaths.contains { $0.hasSuffix("extraction.log") })
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func commandAPIRunsPEXExtractionThroughEngineProtocol() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("pex-extraction-command")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let runDirectory = root.appending(path: "pex-runs").appending(path: "mock-run")
        try DesignFlowServiceTestSupport.writePEXArtifacts(runDirectory: runDirectory)
        let configURL = root.appending(path: "pex-config.json")
        try DesignFlowServiceTestSupport.writePEXConfig(to: configURL)
        let runResult = try DesignFlowServiceTestSupport.makePEXRunResult(runDirectory: runDirectory)

        let result = try await DesignFlowService(
            pexRunner: StubPEXRunner(result: runResult)
        ).execute(DesignFlowCommand(
            kind: .runPEXExtraction,
            pexCornerID: "tt_25c_1v0",
            pexConfigPath: configURL.path(percentEncoded: false)
        ))

        #expect(result.kind == .runPEXExtraction)
        #expect(result.pexManifestPath == runDirectory.appending(path: "manifest.json").path(percentEncoded: false))
        #expect(result.pexCornerID == "tt_25c_1v0")
        #expect(result.pexElementCount == 1)
        #expect(result.message == "mock-pexengine")
    }

    @Test(.timeLimit(.minutes(2)))
    func sharedPEXExtractionAPIProducesInjectablePostLayoutNetlist() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("pex-extraction-shared-api")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let runDirectory = root.appending(path: "pex-runs").appending(path: "mock-run")
        try DesignFlowServiceTestSupport.writePEXArtifacts(runDirectory: runDirectory)
        let configURL = root.appending(path: "pex-config.json")
        try DesignFlowServiceTestSupport.writePEXConfig(to: configURL)
        let runResult = try DesignFlowServiceTestSupport.makePEXRunResult(runDirectory: runDirectory)

        let service = DesignFlowService(pexRunner: StubPEXRunner(result: runResult))
        let extraction = try await service.runPEXExtraction(DesignFlowPEXExtractionRequest(
            configURL: configURL,
            workspaceDirectory: root,
            cornerID: "tt_25c_1v0"
        ))
        let postLayoutNetlist = service.buildPostLayoutNetlist(
            baseNetlist: """
            * Base
            V1 out 0 1
            .op
            .end
            """,
            parasitics: extraction.ir
        )

        #expect(extraction.runResult == runResult)
        #expect(extraction.manifestURL == runDirectory.appending(path: "manifest.json"))
        #expect(extraction.ir.elements.count == 1)
        #expect(postLayoutNetlist.contains("* --- Extracted parasitics ---"))
        #expect(postLayoutNetlist.contains("RPEX_r_out out 0 12"))
        #expect(!postLayoutNetlist.contains("top.spef"))
    }
}
