import Foundation
import Testing
import PEXEngine
@testable import CircuitStudioApp
@testable import CircuitStudioCore
import DesignFlowKernel
import Xcircuite

@Suite("ProjectService Tests")
struct ProjectServiceTests {

    @Test func createProjectBootstrapsWorkspaceAndPEXFiles() async throws {
        let root = try makeTemporaryProjectRoot("bootstrap")
        defer { removeTemporaryProjectRoot(root) }

        let service = ProjectService()
        try await service.createProject(at: root)

        #expect(service.isProject(root))
        #expect(fileExists(".xcircuite/project.json", in: root))
        #expect(fileExists(".xcircuite/workspace.json", in: root))
        #expect(!fileExists(".xcircuite/studio-session.json", in: root))
        #expect(fileExists(".xcircuite/pex.json", in: root))
        #expect(fileExists(".xcircuite/pex/runs", in: root, isDirectory: true))
        #expect(fileExists("pex.toml", in: root))
        #expect(fileExists("tech.json", in: root))

        let packageManifest = try String(
            contentsOf: root.appending(path: ".xcircuite/project.json"),
            encoding: .utf8
        )
        #expect(packageManifest.contains("\"schemaVersion\""))
        #expect(packageManifest.contains("\"identity\""))

        let workspace = try service.loadWorkspaceConfig(forProjectAt: root)
        #expect(workspace.version == 2)
        #expect(workspace.editorDestination == "schematic.netlist")

        let pex = try service.loadPEXProjectConfig(forProjectAt: root)
        #expect(pex.topCell == "TOP")
        #expect(pex.backendID == "")
        #expect(pex.normalizedBackendID == nil)
        #expect(!pex.usesMockBackend)
        #expect(pex.normalizedCorners == ["tt_25c_1v0"])
        #expect(pex.options.strictValidation)

        let pexTOML = try String(contentsOf: service.pexTOMLURL(inProjectAt: root), encoding: .utf8)
        #expect(pexTOML.contains("backend = \"\""))
    }

    @Test func saveAndLoadWorkspaceCellsAndSimulationConfigs() async throws {
        let root = try makeTemporaryProjectRoot("configs")
        defer { removeTemporaryProjectRoot(root) }

        let service = ProjectService()
        try await service.createProject(at: root)

        let workspace = WorkspaceConfig(
            editorDestination: "layout",
            panels: .init(inspector: true, console: true, simulationResults: false)
        )
        try service.saveWorkspaceConfig(workspace, forProjectAt: root)

        // Two cells plus a studio session manifest designating the hierarchy root.
        let topDoc = SchematicDocument(labels: [NetLabel(name: "OUT", position: .zero)])
        let leafDoc = SchematicDocument(labels: [NetLabel(name: "Y", position: .zero)])
        try service.saveCellSchematic(topDoc, cellName: "Amp", forProjectAt: root)
        try service.saveCellSchematic(leafDoc, cellName: "Buffer", forProjectAt: root)
        try await service.saveStudioSessionManifest(
            StudioSessionManifest(topCell: "Amp", activeCell: "Buffer"),
            forProjectAt: root
        )

        let simulation = SimulationConfig(
            selectedAnalysis: .tran(TranSpec(stopTime: 1e-6, stepTime: 1e-9))
        )
        try service.saveSimulationConfig(simulation, forProjectAt: root)

        let loadedWorkspace = try service.loadWorkspaceConfig(forProjectAt: root)
        #expect(loadedWorkspace.editorDestination == "layout")
        #expect(loadedWorkspace.panels.inspector)
        #expect(loadedWorkspace.panels.console)
        #expect(!loadedWorkspace.panels.simulationResults)

        let cellNames = try service.listCellNames(forProjectAt: root)
        #expect(cellNames == ["Amp", "Buffer"])

        let loadedTop = try service.loadCellSchematic(cellName: "Amp", forProjectAt: root)
        #expect(loadedTop.labels.map(\.name) == ["OUT"])

        let manifest = try #require(try service.loadStudioSessionManifestIfPresent(forProjectAt: root))
        #expect(manifest.version == 1)
        #expect(manifest.topCell == "Amp")
        #expect(manifest.activeCell == "Buffer")

        let packageManifest = try JSONDecoder().decode(
            XcircuiteProjectManifest.self,
            from: Data(contentsOf: root.appending(path: ".xcircuite/project.json"))
        )
        #expect(packageManifest.identity.topDesignName == "Amp")
        #expect(packageManifest.schemaVersion == XcircuiteProjectManifest.currentSchemaVersion)

        let loadedSimulation = try service.loadSimulationConfig(forProjectAt: root)
        #expect(loadedSimulation.version == 1)
        #expect(loadedSimulation.selectedAnalysis == .tran(TranSpec(stopTime: 1e-6, stepTime: 1e-9)))
    }

    @Test func listCellNamesRejectsInvalidPersistedCellDirectoryName() async throws {
        let root = try makeTemporaryProjectRoot("invalid-cell-directory")
        defer { removeTemporaryProjectRoot(root) }

        let service = ProjectService()
        try await service.createProject(at: root)

        let invalidCellDirectory = root.appending(path: "cells/1bad")
        try FileManager.default.createDirectory(at: invalidCellDirectory, withIntermediateDirectories: true)
        let schematic = SchematicDocument()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(schematic)
        try data.write(to: invalidCellDirectory.appending(path: "schematic.json"), options: [.atomic])

        #expect(throws: CellLibraryError.invalidCellName("1bad")) {
            _ = try service.listCellNames(forProjectAt: root)
        }
    }

    @Test func obsoleteStudioSessionManifestIsRejectedWithoutRewritingProjectLedger() async throws {
        let root = try makeTemporaryProjectRoot("obsolete-manifest-rejected")
        defer { removeTemporaryProjectRoot(root) }

        let metadataDirectory = root.appending(path: ".xcircuite")
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        try Data(
            """
            {
              "activeCell" : "Leaf",
              "topCell" : "ObsoleteTop",
              "version" : 1
            }
            """.utf8
        ).write(to: metadataDirectory.appending(path: "project.json"))

        let service = ProjectService()
        #expect(try service.loadStudioSessionManifestIfPresent(forProjectAt: root) == nil)
        await #expect(throws: XcircuiteWorkspaceStoreError.self) {
            try await service.saveStudioSessionManifest(
                StudioSessionManifest(topCell: "ObsoleteTop", activeCell: "Leaf"),
                forProjectAt: root
            )
        }

        let preserved = try String(
            contentsOf: metadataDirectory.appending(path: "project.json"),
            encoding: .utf8
        )
        #expect(preserved.contains("\"topCell\" : \"ObsoleteTop\""))
        #expect(!preserved.contains("\"schemaVersion\""))
        #expect(!fileExists(".xcircuite/studio-session.json", in: root))
    }

    @Test func savePEXProjectConfigWritesJSONAndTOML() async throws {
        let root = try makeTemporaryProjectRoot("pex")
        defer { removeTemporaryProjectRoot(root) }

        let service = ProjectService()
        try await service.createProject(at: root)

        let config = PEXProjectConfig(
            enabled: true,
            topCell: "AMP_TOP",
            backendID: "magic",
            corners: ["tt", "ss"],
            processProfile: PEXProcessProfileReference(
                profileID: "sky130",
                cornerDeckPaths: [
                    "tt": "pdk/sky130A.magicrc",
                    "ss": "pdk/sky130B.magicrc",
                ]
            ),
            inputs: .init(
                layout: "layout/amp.oas",
                netlist: "netlists/amp.cir",
                technology: "pdk/tech.json"
            ),
            output: .init(workspace: ".xcircuite/pex/runs"),
            options: .init(
                includeCouplingCaps: false,
                minCapacitanceF: 1e-15,
                minResistanceOhm: 0.25,
                maxParallelJobs: 0,
                strictValidation: true
            )
        )

        try service.savePEXProjectConfig(config, forProjectAt: root)

        let loaded = try service.loadPEXProjectConfig(forProjectAt: root)
        #expect(loaded == config)

        let toml = try String(contentsOf: service.pexTOMLURL(inProjectAt: root), encoding: .utf8)
        #expect(toml.contains("layout = \"layout/amp.oas\""))
        #expect(toml.contains("netlist = \"netlists/amp.cir\""))
        #expect(toml.contains("top_cell = \"AMP_TOP\""))
        #expect(toml.contains("backend = \"magic\""))
        #expect(toml.contains("max_jobs = 1"))
        #expect(toml.contains("include_coupling = false"))
        #expect(toml.contains("min_cap_f = 1e-15"))
        #expect(toml.contains("min_res_ohm = 0.25"))
        #expect(toml.contains("strict = true"))
        #expect(toml.contains("id = \"tt\""))
        #expect(toml.contains("id = \"ss\""))
    }

    @Test func saveNetlistCreatesIntermediateDirectories() async throws {
        let root = try makeTemporaryProjectRoot("netlist")
        defer { removeTemporaryProjectRoot(root) }

        let service = ProjectService()
        try await service.createProject(at: root)

        let source = """
        * RC test
        V1 in 0 1
        R1 in out 1k
        C1 out 0 1p
        .op
        .end
        """

        try service.saveNetlist(source, toProjectRelativePath: "netlists/generated/top.cir", inProjectAt: root)

        let url = root.appending(path: "netlists/generated/top.cir")
        let loaded = try String(contentsOf: url, encoding: .utf8)
        #expect(loaded == source)
    }

    @Test func projectRootFileOperationsRejectUnsafeFileNames() async throws {
        let root = try makeTemporaryProjectRoot("unsafe-root-file")
        defer { removeTemporaryProjectRoot(root) }

        let service = ProjectService()
        try await service.createProject(at: root)

        let unsafeFileNames = [
            "",
            ".",
            "..",
            "../escape.cir",
            "nested/top.cir",
            "/tmp/top.cir",
            "~/top.cir",
            "\\tmp\\top.cir",
            ".xcircuite",
            "cells"
        ]

        for fileName in unsafeFileNames {
            do {
                try service.saveNetlist("* rejected\n.end\n", named: fileName, inProjectAt: root)
                Issue.record("Expected unsafe project root file name to be rejected for save: \(fileName)")
            } catch StudioError.projectSaveFailed(let message) {
                #expect(message.contains("Unsafe project root file name"))
            } catch {
                Issue.record("Unexpected save error for unsafe project root file name \(fileName): \(error)")
            }

            do {
                try service.removeProjectRootFile(named: fileName, forProjectAt: root)
                Issue.record("Expected unsafe project root file name to be rejected for removal: \(fileName)")
            } catch StudioError.projectSaveFailed(let message) {
                #expect(message.contains("Unsafe project root file name"))
            } catch {
                Issue.record("Unexpected removal error for unsafe project root file name \(fileName): \(error)")
            }
        }
    }

    @Test func saveMaterializedSchematicWritesCanonicalCellArtifacts() async throws {
        let root = try makeTemporaryProjectRoot("materialized-schematic")
        defer { removeTemporaryProjectRoot(root) }

        let service = ProjectService()
        try await service.createProject(at: root)

        let source = """
        * imported top-level deck
        V1 in 0 5
        R1 in out 1k
        C1 out 0 1p
        .end
        """
        let result = try await SPICESchematicImporter().importTopLevel(
            source: source,
            fileName: "top.cir",
            topCellName: "Top",
            catalog: .standard()
        )

        try await service.saveMaterializedSchematic(result, forProjectAt: root)

        #expect(fileExists("cells/Top/schematic.json", in: root))
        #expect(fileExists(".xcircuite/studio-session.json", in: root))

        let cellNames = try service.listCellNames(forProjectAt: root)
        #expect(cellNames == ["Top"])

        let document = try service.loadCellSchematic(cellName: "Top", forProjectAt: root)
        #expect(document.components.map(\.name).sorted() == ["c1", "r1", "v1"])

        let manifest = try #require(try service.loadStudioSessionManifestIfPresent(forProjectAt: root))
        #expect(manifest.topCell == "Top")
        #expect(manifest.activeCell == "Top")

        let packageManifest = try JSONDecoder().decode(
            XcircuiteProjectManifest.self,
            from: Data(contentsOf: root.appending(path: ".xcircuite/project.json"))
        )
        #expect(packageManifest.identity.topDesignName == "Top")
    }

    private func makeTemporaryProjectRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioProjectServiceTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryProjectRoot(_ root: URL) {
        let path = root.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary project root: \(error)")
        }
    }

    private func fileExists(_ relativePath: String, in root: URL, isDirectory expectedDirectory: Bool? = nil) -> Bool {
        var isDirectory: ObjCBool = false
        let path = root.appending(path: relativePath).path(percentEncoded: false)
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        if let expectedDirectory {
            return exists && isDirectory.boolValue == expectedDirectory
        }
        return exists
    }
}
