import Foundation
import Testing
import PEXEngine
import PEXNative
import PEXCLICore
@testable import CircuitStudioApp
@testable import CircuitStudioCore

@Suite("Studio native PEX configuration", .timeLimit(.minutes(2)))
struct StudioNativePEXConfigurationTests {
    @Test
    func preservesNativePathAcrossProjectSavesAndPublicCLI() async throws {
        let root = try makeRoot("persistence")
        defer { cleanup(root) }
        let service = ProjectService()
        try await service.createProject(at: root)
        let fixture = try StudioNativePEXFixture(root: root)
        let cliWorkspace = root.appending(path: "cli-runs")
        let config = fixture.projectConfig(workspace: cliWorkspace.path)
        try service.savePEXProjectConfig(config, forProjectAt: root)
        #expect(try service.loadPEXProjectConfig(forProjectAt: root) == config)
        try service.updatePEXTopCell("RENAMED", forProjectAt: root)
        #expect(try service.loadPEXProjectConfig(forProjectAt: root).inputs.nativeInput == fixture.referencePath)
        try service.updatePEXTopCell("TOP", forProjectAt: root)
        try service.ensurePEXProjectFiles(forProjectAt: root)
        #expect(try service.loadPEXProjectConfig(forProjectAt: root) == config)
        let configURL = try service.pexConfigURL(inProjectAt: root)
        let persisted = try JSONDecoder().decode(PEXProjectConfig.self, from: Data(contentsOf: configURL))
        #expect(persisted.version == 1 && persisted.inputs.nativeInput == "native reference \"sheet\".json")
        #expect(persisted.inputs.layout == "../sheet.gds" && persisted.inputs.netlist == "../source.spice"
            && persisted.inputs.technology == "../technology.json")
        #expect(config.inputs.nativeInput.map { root.appending(path: $0).standardizedFileURL }
            == persisted.inputs.nativeInput.map { configURL.deletingLastPathComponent().appending(path: $0).standardizedFileURL })

        // Execute the actual canonical JSON through the public CLI parser.
        try await ExtractCommand(arguments: ["--config", configURL.path]).run()
        let runs = try FileManager.default.contentsOfDirectory(at: cliWorkspace, includingPropertiesForKeys: nil)
        #expect(runs.count == 1)
        let runDirectory = try #require(runs.first)
        let resolver = try PEXArtifactResolver(manifestURL: runDirectory.appending(path: "manifest.json"))
        try assertNativeSuccess(resolver, fixture: fixture)
        try fixture.assertOriginalInputsUnchanged()
    }

    @Test
    @MainActor
    func actualNativeCommandRetainsCanonicalArtifacts() async throws {
        let root = try makeRoot("command")
        defer { cleanup(root) }
        let project = ProjectService()
        try await project.createProject(at: root)
        let fixture = try StudioNativePEXFixture(root: root)
        try project.savePEXProjectConfig(fixture.projectConfig(workspace: root.appending(path: "studio-runs").path),
            forProjectAt: root)
        let configURL = try project.pexConfigURL(inProjectAt: root)
        let commandResult = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .runPEXExtraction, pexCornerID: "tt", pexConfigPath: configURL.path))
        #expect(commandResult.kind == .runPEXExtraction && commandResult.message == "native")
        #expect(commandResult.pexCornerID == "tt")
        let resolver = try PEXArtifactResolver(manifestURL: URL(filePath: #require(commandResult.pexManifestPath)))
        try assertNativeSuccess(resolver, fixture: fixture)
        #expect(commandResult.pexElementCount == (try resolver.loadIR(cornerID: "tt")).elements.count)
        try fixture.assertOriginalInputsUnchanged()
    }

    @Test(arguments: ["missing", "blank", "wrong-backend"])
    func missingNativeInputIsRejectedBeforeExecution(reason: String) async throws {
        let root = try makeRoot(reason)
        defer { cleanup(root) }
        let project = ProjectService()
        try await project.createProject(at: root)
        let fixture = try StudioNativePEXFixture(root: root)
        let workspace = root.appending(path: "rejected-runs")
        var config = fixture.projectConfig(workspace: workspace.path)
        if reason == "missing" { config.inputs.nativeInput = nil }
        if reason == "blank" { config.inputs.nativeInput = " \n " }
        if reason == "wrong-backend" { config.backendID = "magic" }
        try project.savePEXProjectConfig(config, forProjectAt: root)
        do {
            _ = try await PEXExtractionService().extract(.init(configURL: project.pexConfigURL(inProjectAt: root), cornerID: "tt"))
            Issue.record("Native input admission unexpectedly succeeded: \(reason)")
        } catch let error as PEXError {
            #expect(error.kind == .invalidInput)
        }
        #expect(!FileManager.default.fileExists(atPath: workspace.path))
        try fixture.assertOriginalInputsUnchanged()
    }

    @Test
    @MainActor
    func actualBackendFailureRetainsRunResult() async throws {
        let root = try makeRoot("backend-failure")
        defer { cleanup(root) }
        let project = ProjectService()
        try await project.createProject(at: root)
        let fixture = try StudioNativePEXFixture(root: root, maximumMeshCells: 0)
        let workspace = root.appending(path: "failed-runs")
        try project.savePEXProjectConfig(fixture.projectConfig(workspace: workspace.path), forProjectAt: root)
        do {
            _ = try await DesignFlowService().execute(DesignFlowCommand(kind: .runPEXExtraction,
                pexCornerID: "tt", pexConfigPath: project.pexConfigURL(inProjectAt: root).path))
            Issue.record("Zero mesh budget unexpectedly produced successful native extraction")
        } catch let error as PEXExtractionError {
            guard case .executionFailed(let actual) = error else {
                Issue.record("Backend failure lost its actual run result: \(error)")
                return
            }
            #expect(actual.status == .failed && actual.cornerResults.first?.ir == nil)
            let resolver = try PEXArtifactResolver(manifestURL: actual.manifestURL)
            #expect(resolver.manifest.runID == actual.runID && resolver.manifest.requestHash == actual.requestHash)
            #expect(resolver.manifest.backendExecutions == actual.artifactManifest.backendExecutions)
            #expect(resolver.manifest.corners.first?.failure?.message.contains("meshCells") == true)
            #expect(!actual.diagnostics.isEmpty)
            #expect(resolver.records(kind: .parasiticIR).isEmpty)
            #expect(resolver.records(kind: .processEvidence, availability: .available).count == 1)
            let identity = try #require(actual.artifactManifest.backendExecutions.first)
            #expect(identity.invocation.mode == .inProcess && identity.producer.identifier == "pex-native")
            let stored = try PEXArtifactStore(workspace: .init(baseURL: workspace, runID: actual.runID)).loadResult()
            // Persistence reconstructs corner telemetry; compare the retained failure contract.
            #expect(stored.runID == actual.runID && stored.requestHash == actual.requestHash)
            #expect(stored.status == actual.status && stored.cornerResults.count == actual.cornerResults.count)
            let liveCorner = try #require(actual.cornerResults.first)
            let storedCorner = try #require(stored.cornerResults.first)
            #expect(liveCorner.status == .failed && !liveCorner.warnings.isEmpty)
            #expect(liveCorner.metrics.durationSeconds > 0 && liveCorner.metrics.durationSeconds.isFinite)
            #expect(storedCorner.cornerID == liveCorner.cornerID && storedCorner.status == liveCorner.status)
            #expect(storedCorner.ir == nil && storedCorner.rawOutputURLs == liveCorner.rawOutputURLs)
            #expect(storedCorner.logURL == liveCorner.logURL)
            #expect(stored.warnings == actual.warnings && stored.diagnostics == actual.diagnostics)
            #expect(stored.artifactManifest.corners == actual.artifactManifest.corners)
            #expect(stored.artifactManifest.backendExecutions == actual.artifactManifest.backendExecutions)
            try assertCapturedInputs(resolver, fixture: fixture)
        }
        try fixture.assertOriginalInputsUnchanged()
    }

    private func assertNativeSuccess(_ resolver: PEXArtifactResolver, fixture: StudioNativePEXFixture) throws {
        #expect(resolver.manifest.status == .success && resolver.manifest.backendID == "native")
        #expect(resolver.completenessReport().issues.isEmpty)
        let identity = try #require(resolver.manifest.backendExecutions.first)
        #expect(identity.invocation.mode == .inProcess && identity.producer.identifier == "pex-native")
        let image = try NativePEXCodeImage.measure()
        #expect(identity.binaryDigest == image.digest && identity.producer.build == image.digest.hexadecimalValue)
        let ir = try resolver.loadIR(cornerID: "tt")
        #expect(!ir.elements.isEmpty && ir.elements.allSatisfy { $0.value.isFinite && $0.value > 0 })
        #expect(abs(ir.elements.filter { $0.kind == .resistor }.reduce(0) { $0 + $1.value } - 0.02) < 1e-14)
        #expect(abs(ir.nets.reduce(0) { $0 + $1.totalGroundCapF } - 5e-16) < 1e-28)
        for kind in [PEXArtifactKind.parasiticIR, .spiceBackannotation, .spefRoundTrip] {
            let record = try #require(resolver.records(kind: kind, cornerID: "tt", availability: .available).first)
            #expect(record.producer == identity.producer)
            #expect(!(try Data(contentsOf: resolver.validatedURL(for: record))).isEmpty)
        }
        let topologyRecord = try #require(resolver.records(kind: .processEvidence, availability: .available).first {
            $0.relativePath.stringValue.hasSuffix(NativePEXTopologyEvidence.artifactFileName)
        })
        let topology = try JSONDecoder().decode(NativePEXTopologyEvidence.self,
            from: Data(contentsOf: resolver.validatedURL(for: topologyRecord)))
        #expect(topology.coordinateUnits == fixture.configuration.expectedCoordinateUnits)
        #expect(topology.components.count == 1 && topology.pins.count == 2 && topology.electrodeContacts.count == 2)
        #expect(topology.opens.isEmpty && topology.shortComponentIndices.isEmpty)
        #expect(topology.executionIdentity == identity && topology.model.calibrationArtifacts == [fixture.calibrationID])
        try assertCapturedInputs(resolver, fixture: fixture)
    }

    private func assertCapturedInputs(_ resolver: PEXArtifactResolver, fixture: StudioNativePEXFixture) throws {
        let calibration = try #require(resolver.records(kind: .calibrationInput, availability: .available).first)
        #expect(calibration.reference?.id == fixture.calibrationID)
        #expect(try Data(contentsOf: resolver.validatedURL(for: calibration)) == Data(contentsOf: #require(fixture.reference.calibrations.first).url))
        let configuration = try #require(resolver.records(kind: .nativeConfigurationInput, availability: .available).first)
        let configurationBytes = try Data(contentsOf: resolver.validatedURL(for: configuration))
        #expect(configurationBytes == (try Data(contentsOf: fixture.reference.configurationURL)))
        let retainedConfiguration = try JSONDecoder().decode(NativePEXConfiguration.self, from: configurationBytes)
        #expect(retainedConfiguration.version == 3)
        #expect(retainedConfiguration.netBindings == fixture.configuration.netBindings)
        let captured = try PEXArtifactStore(workspace: .init(baseURL: resolver.runDirectory.deletingLastPathComponent(),
            runID: resolver.manifest.runID)).loadRequest()
        #expect(captured.backendSelection.backendID == "native")
        for kind in [PEXArtifactKind.layoutInput, .netlistInput, .technologyInput] {
            let record = try #require(resolver.records(kind: kind, availability: .available).first)
            let retainedBytes = try Data(contentsOf: resolver.validatedURL(for: record))
            let name: String
            switch kind {
            case .layoutInput: name = "sheet.gds"
            case .netlistInput: name = "source.spice"
            case .technologyInput: name = "technology.json"
            default: throw PEXError.invalidInput("Unexpected fixture input kind")
            }
            #expect(retainedBytes == fixture.originalInputs[fixture.root.appending(path: name)])
        }
        #expect(captured.nativeInput?.calibrations.map(\.artifactID) == [fixture.calibrationID])
        #expect(captured.nativeInput?.configurationURL.path.hasPrefix(resolver.runDirectory.path) == true)
    }

    private func makeRoot(_ name: String) throws -> URL {
        let parent = ProcessInfo.processInfo.environment["LSI_STUDIO_NATIVE_PEX_OUTPUT_ROOT"].map { URL(filePath: $0) }
            ?? FileManager.default.temporaryDirectory
        let root = parent.appending(path: "StudioNativePEX-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func cleanup(_ root: URL) {
        guard ProcessInfo.processInfo.environment["LSI_STUDIO_NATIVE_PEX_OUTPUT_ROOT"] == nil else { return }
        do { try FileManager.default.removeItem(at: root) }
        catch { Issue.record("Native PEX fixture cleanup failed: \(error)") }
    }
}
