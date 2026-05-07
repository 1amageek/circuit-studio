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

        let roundTrip = try await runRoundTrip(
            rootName: "cmos-round-trip",
            runID: "cmos-inverter-round-trip",
            title: "CMOS inverter headless round trip",
            schematic: SchematicPreview.cmosInverterViewModel().document,
            testbench: testbench,
            postLayoutCommand: .tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9)),
            pexIR: pexIR
        )

        try assertCompletedRoundTrip(roundTrip)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func voltageDividerCompletesHeadlessRoundTripWithArtifacts() async throws {
        let testbench = Testbench(
            name: "Operating Point",
            analysisCommands: [.op]
        )
        let pexIR = PEXParasiticIR(
            version: "1.0",
            cornerID: "tt_25c_1v0",
            elements: [
                PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 0.5),
                PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 1e-15),
            ]
        )
        let schematic = SchematicPreview.voltageDividerViewModel().document

        let roundTrip = try await runRoundTrip(
            rootName: "voltage-divider-round-trip",
            runID: "voltage-divider-round-trip",
            title: "Voltage divider headless round trip",
            schematic: schematic,
            testbench: testbench,
            postLayoutCommand: .op,
            pexIR: pexIR
        )

        try assertCompletedRoundTrip(roundTrip)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func voltageDividerCompletesRoundTripWithImportedSignoffReview() async throws {
        let root = try makeTemporaryRoot("voltage-divider-imported-signoff")
        defer { removeTemporaryRoot(root) }

        let drcLogURL = root.appending(path: "golden-drc.log")
        let lvsLogURL = root.appending(path: "golden-lvs.log")
        let pexManifestURL = root.appending(path: "pex-manifest.json")
        try """
        [INFO] rule=DRC_CLEAN message="clean drc"
        """.write(to: drcLogURL, atomically: true, encoding: .utf8)
        try """
        [INFO] rule=LVS_MATCH message="clean lvs"
        """.write(to: lvsLogURL, atomically: true, encoding: .utf8)
        try """
        {"status":"success"}
        """.write(to: pexManifestURL, atomically: true, encoding: .utf8)

        let review = try ExternalSignoffArtifactService().load(logs: [
            ExternalSignoffLogArtifact(kind: .drc, toolName: "imported-drc", logURL: drcLogURL, success: true),
            ExternalSignoffLogArtifact(kind: .lvs, toolName: "imported-lvs", logURL: lvsLogURL, success: true),
        ])
        let configuration = makeConfiguration(
            projectRoot: root,
            runID: "voltage-divider-imported-signoff",
            title: "Voltage divider imported signoff round trip",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: smallPEXIR(),
            pexArtifactPaths: [pexManifestURL.path(percentEncoded: false)],
            externalSignoffReview: review
        )

        let result = try await HeadlessRoundTripService().run(
            schematic: SchematicPreview.voltageDividerViewModel().document,
            configuration: configuration
        )

        #expect(result.manifest.isRoundTripComplete)
        #expect(result.manifest.isReadyForPEX)
        #expect(result.externalSignoff?.isReadyForPEX == true)
        #expect(result.externalSignoff?.reports.map(\.toolName) == ["imported-drc", "imported-lvs"])
        #expect(result.manifest.artifacts.map(\.path).contains(drcLogURL.path(percentEncoded: false)))
        #expect(result.manifest.artifacts.map(\.path).contains(lvsLogURL.path(percentEncoded: false)))
        #expect(result.manifest.artifacts.contains {
            $0.kind == "pex-artifact" && $0.path == pexManifestURL.path(percentEncoded: false)
        })
        #expect(!result.manifest.artifacts.map(\.path).contains { $0.hasSuffix("mock-drc.log") })

        let storedReview = try ExternalSignoffReviewStore().load(projectRoot: root)
        #expect(storedReview.approvedBy == "layout-reviewer")
        #expect(storedReview.isReadyForPEX)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func prePEXGateFailureWritesManifest() async throws {
        let root = try makeTemporaryRoot("pre-pex-failure")
        defer { removeTemporaryRoot(root) }

        let commands = try makeSignoffCommands(
            in: root,
            drcContents: """
            #!/bin/sh
            printf '[ERROR] rule=DRC_FAIL message="drc failed"\\n'
            exit 2
            """,
            lvsContents: """
            #!/bin/sh
            printf '[INFO] rule=LVS_MATCH message="clean lvs"\\n'
            exit 0
            """
        )
        let configuration = makeConfiguration(
            projectRoot: root,
            runID: "pre-pex-failure",
            title: "Pre-PEX failure manifest",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: smallPEXIR(),
            externalSignoffCommands: commands
        )

        try await expectInvalidDesign(
            "Pre-PEX verification gate failed.",
            operation: {
                _ = try await HeadlessRoundTripService().run(
                    schematic: SchematicPreview.voltageDividerViewModel().document,
                    configuration: configuration
                )
            }
        )

        let manifest = try loadManifest(projectRoot: root, runID: "pre-pex-failure")
        assertFailureManifest(
            manifest,
            failedStage: "pre-pex-verification",
            skippedStages: ["pex-injection", "post-layout-simulation"],
            isReadyForPEX: false
        )
        #expect(manifest.stages.first { $0.name == "external-signoff" }?.status == .failed)
        #expect(manifest.artifacts.map(\.path).contains { $0.hasSuffix("drc-mock-drc.log") })
        #expect(manifest.artifacts.map(\.path).contains { $0.hasSuffix("external-signoff-review.json") })
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func emptyPEXIRFailureWritesManifest() async throws {
        let root = try makeTemporaryRoot("empty-pex-failure")
        defer { removeTemporaryRoot(root) }

        let configuration = makeConfiguration(
            projectRoot: root,
            runID: "empty-pex-failure",
            title: "Empty PEX failure manifest",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .op,
            pexIR: PEXParasiticIR(version: "1.0", cornerID: "tt_25c_1v0", elements: []),
            externalSignoffCommands: try makeSignoffCommands(in: root)
        )

        try await expectInvalidDesign(
            "Headless round trip requires non-empty PEX IR.",
            operation: {
                _ = try await HeadlessRoundTripService().run(
                    schematic: SchematicPreview.voltageDividerViewModel().document,
                    configuration: configuration
                )
            }
        )

        let manifest = try loadManifest(projectRoot: root, runID: "empty-pex-failure")
        assertFailureManifest(
            manifest,
            failedStage: "pex-injection",
            skippedStages: ["post-layout-simulation"],
            isReadyForPEX: true
        )
        #expect(manifest.artifacts.map(\.path).contains { $0.hasSuffix("post-layout.cir") })
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func postLayoutSimulationFailureWritesManifest() async throws {
        let root = try makeTemporaryRoot("post-layout-failure")
        defer { removeTemporaryRoot(root) }

        let configuration = makeConfiguration(
            projectRoot: root,
            runID: "post-layout-failure",
            title: "Post-layout failure manifest",
            testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
            postLayoutCommand: .dcSweep(DCSweepSpec(source: "V1", startValue: 0, stopValue: 1, stepValue: 0)),
            pexIR: smallPEXIR(),
            externalSignoffCommands: try makeSignoffCommands(in: root)
        )

        do {
            _ = try await HeadlessRoundTripService().run(
                schematic: SchematicPreview.voltageDividerViewModel().document,
                configuration: configuration
            )
            Issue.record("Expected post-layout simulation failure")
        } catch {
            #expect(error.localizedDescription.contains("DC sweep step cannot be zero"))
        }

        let manifest = try loadManifest(projectRoot: root, runID: "post-layout-failure")
        assertFailureManifest(
            manifest,
            failedStage: "post-layout-simulation",
            skippedStages: [],
            isReadyForPEX: true
        )
        #expect(manifest.stages.first { $0.name == "pex-injection" }?.status == .passed)
    }

    private struct RoundTripOutput {
        var result: HeadlessRoundTripService.Result
        var projectRoot: URL
    }

    @MainActor
    private func runRoundTrip(
        rootName: String,
        runID: String,
        title: String,
        schematic: SchematicDocument,
        testbench: Testbench,
        postLayoutCommand: AnalysisCommand,
        pexIR: PEXParasiticIR
    ) async throws -> RoundTripOutput {
        let root = try makeTemporaryRoot(rootName)
        let configuration = makeConfiguration(
            projectRoot: root,
            runID: runID,
            title: title,
            testbench: testbench,
            postLayoutCommand: postLayoutCommand,
            pexIR: pexIR,
            externalSignoffCommands: try makeSignoffCommands(in: root)
        )

        do {
            let result = try await HeadlessRoundTripService().run(
                schematic: schematic,
                configuration: configuration
            )
            return RoundTripOutput(result: result, projectRoot: root)
        } catch {
            removeTemporaryRoot(root)
            throw error
        }
    }

    private func assertCompletedRoundTrip(_ roundTrip: RoundTripOutput) throws {
        defer { removeTemporaryRoot(roundTrip.projectRoot) }

        let result = roundTrip.result

        if !result.verification.isReadyForPEX {
            Issue.record("DRC: \(String(describing: result.verification.drc))")
            Issue.record("LVS: \(String(describing: result.verification.lvs))")
        }

        #expect(result.manifest.isRoundTripComplete)
        #expect(result.manifest.isReadyForPEX)
        #expect(result.verification.isReadyForPEX)
        #expect(result.verification.drc.passed)
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
        #expect(result.manifest.stages.allSatisfy { $0.status == .passed })
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

        let review = try ExternalSignoffReviewStore().load(projectRoot: roundTrip.projectRoot)
        #expect(review.approvedBy == "layout-reviewer")
        #expect(review.isReadyForPEX)
    }

    private func assertFailureManifest(
        _ manifest: HeadlessRoundTripService.Manifest,
        failedStage: String,
        skippedStages: [String],
        isReadyForPEX: Bool
    ) {
        #expect(!manifest.isRoundTripComplete)
        #expect(manifest.isReadyForPEX == isReadyForPEX)
        #expect(manifest.stages.first { $0.name == failedStage }?.status == .failed)
        for skippedStage in skippedStages {
            #expect(manifest.stages.first { $0.name == skippedStage }?.status == .skipped)
        }
        #expect(FileManager.default.fileExists(atPath: manifest.artifacts.first?.path ?? ""))
    }

    @MainActor
    private func expectInvalidDesign(
        _ message: String,
        operation: @MainActor () async throws -> Void
    ) async throws {
        do {
            try await operation()
            Issue.record("Expected invalid design error")
        } catch StudioError.invalidDesign(let actualMessage) {
            #expect(actualMessage == message)
        } catch {
            Issue.record("Expected invalid design error, got \(error)")
        }
    }

    private func makeConfiguration(
        projectRoot: URL,
        runID: String,
        title: String,
        testbench: Testbench,
        postLayoutCommand: AnalysisCommand,
        pexIR: PEXParasiticIR,
        pexArtifactPaths: [String] = [],
        externalSignoffCommands: [ExternalSignoffCommand] = [],
        externalSignoffReview: ExternalSignoffReview? = nil
    ) -> HeadlessRoundTripService.Configuration {
        HeadlessRoundTripService.Configuration(
            projectRoot: projectRoot,
            runID: runID,
            title: title,
            testbench: testbench,
            postLayoutCommand: postLayoutCommand,
            pexIR: pexIR,
            pexArtifactPaths: pexArtifactPaths,
            externalSignoffCommands: externalSignoffCommands,
            externalSignoffReview: externalSignoffReview,
            approvedBy: "layout-reviewer",
            approvedAt: Date(timeIntervalSince1970: 2_000),
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func smallPEXIR() -> PEXParasiticIR {
        PEXParasiticIR(
            version: "1.0",
            cornerID: "tt_25c_1v0",
            elements: [
                PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 0.5),
                PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 1e-15),
            ]
        )
    }

    private func makeSignoffCommands(
        in root: URL,
        drcContents: String = """
        #!/bin/sh
        printf '[INFO] rule=DRC_CLEAN message="clean drc"\\n'
        exit 0
        """,
        lvsContents: String = """
        #!/bin/sh
        printf '[INFO] rule=LVS_MATCH message="clean lvs"\\n'
        exit 0
        """
    ) throws -> [ExternalSignoffCommand] {
        let drcExecutable = try writeExecutable(named: "mock-drc", in: root, contents: drcContents)
        let lvsExecutable = try writeExecutable(named: "mock-lvs", in: root, contents: lvsContents)
        return [
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
        ]
    }

    private func loadManifest(
        projectRoot: URL,
        runID: String
    ) throws -> HeadlessRoundTripService.Manifest {
        let manifestURL = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: runID)
            .appending(path: "round-trip-manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HeadlessRoundTripService.Manifest.self, from: data)
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
