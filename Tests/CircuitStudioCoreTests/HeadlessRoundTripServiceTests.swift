import Foundation
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore
@testable import SchematicEditor

@Suite("HeadlessRoundTripService Tests")
struct HeadlessRoundTripServiceTests {

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func cmosInverterCompletesHeadlessRoundTripWithArtifacts() async throws {
        let root = try makeTemporaryRoot("cmos-round-trip")
        defer { removeTemporaryRoot(root) }
        let drcExecutable = try writeExecutable(
            named: "mock-drc",
            in: root,
            contents: """
            #!/bin/sh
            printf '[INFO] rule=DRC_CLEAN message="clean drc"\\n'
            exit 0
            """
        )
        let lvsExecutable = try writeExecutable(
            named: "mock-lvs",
            in: root,
            contents: """
            #!/bin/sh
            printf '[INFO] rule=LVS_MATCH message="clean lvs"\\n'
            exit 0
            """
        )
        let testbench = Testbench(
            name: "Transient",
            analysisCommands: [
                .tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9)),
            ]
        )
        let pexIR = PEXParasiticIR(
            version: "1.0",
            cornerID: "tt_25c_1v0",
            elements: [
                PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 1.0),
                PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 2e-15),
            ]
        )
        let configuration = HeadlessRoundTripService.Configuration(
            projectRoot: root,
            runID: "cmos-inverter-round-trip",
            title: "CMOS inverter headless round trip",
            testbench: testbench,
            postLayoutCommand: .tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9)),
            pexIR: pexIR,
            externalSignoffCommands: [
                ExternalSignoffCommand(
                    kind: .drc,
                    toolName: "mock-drc",
                    executablePath: drcExecutable.path(percentEncoded: false)
                ),
                ExternalSignoffCommand(
                    kind: .lvs,
                    toolName: "mock-lvs",
                    executablePath: lvsExecutable.path(percentEncoded: false)
                ),
            ],
            approvedBy: "layout-reviewer",
            approvedAt: Date(timeIntervalSince1970: 2_000),
            createdAt: Date(timeIntervalSince1970: 1_000),
            continueAfterFailedPrePEXGate: true
        )

        let result = try await HeadlessRoundTripService().run(
            schematic: SchematicPreview.cmosInverterViewModel().document,
            configuration: configuration
        )

        #expect(result.manifest.isRoundTripComplete)
        #expect(!result.manifest.isReadyForPEX)
        #expect(!result.verification.isReadyForPEX)
        #expect(!result.verification.drc.passed)
        #expect(result.externalSignoff?.isReadyForPEX == true)
        #expect(result.preLayoutResult.status == .completed)
        #expect(result.postLayoutResult.status == .completed)
        #expect(Set(result.manifest.stages.map(\.name)).isSuperset(of: [
            "net-extraction",
            "netlist-generation",
            "pre-layout-simulation",
            "auto-layout",
            "pre-pex-verification",
            "pex-injection",
            "post-layout-simulation",
        ]))
        #expect(result.manifest.stages.filter { $0.status == .failed }.map(\.name) == ["pre-pex-verification"])
        #expect(result.manifest.stages.first { $0.name == "pre-pex-verification" }?.message?.contains("DRC violations") == true)
        #expect(FileManager.default.fileExists(atPath: result.manifestURL.path(percentEncoded: false)))

        let artifactPaths = result.manifest.artifacts.map(\.path)
        #expect(artifactPaths.contains { $0.hasSuffix("pre-layout.cir") })
        #expect(artifactPaths.contains { $0.hasSuffix("post-layout.cir") })
        #expect(artifactPaths.contains { $0.hasSuffix("drc-mock-drc.log") })
        #expect(artifactPaths.contains { $0.hasSuffix("lvs-mock-lvs.log") })
        #expect(artifactPaths.contains { $0.hasSuffix("external-signoff-review.json") })

        let manifestData = try Data(contentsOf: result.manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(HeadlessRoundTripService.Manifest.self, from: manifestData)
        #expect(manifest == result.manifest)

        let review = try ExternalSignoffReviewStore().load(projectRoot: root)
        #expect(review.approvedBy == "layout-reviewer")
        #expect(review.isReadyForPEX)
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioHeadlessRoundTripServiceTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }

    private func writeExecutable(named name: String, in root: URL, contents: String) throws -> URL {
        let url = root.appending(path: name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path(percentEncoded: false)
        )
        return url
    }
}
