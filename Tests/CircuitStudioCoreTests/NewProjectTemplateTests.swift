import Foundation
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore

@Suite("New Project Template Tests")
struct NewProjectTemplateTests {

    @Test
    @MainActor
    func templateContentIsConsistent() throws {
        let content = NewProjectTemplate.cmosInverter()

        #expect(content.netlistFileName == "top.cir")
        #expect(content.netlist == content.schematicPlacement.sourceNetlist)
        #expect(content.netlist.hasPrefix("* Welcome to Circuit Studio!"))
        #expect(content.netlist.contains("MP1"))
        #expect(content.netlist.contains("MN1"))
        #expect(content.netlist.contains(".tran"))
        #expect(content.netlist.contains(".end"))
        #expect(!content.schematicPlacement.document.components.isEmpty)
        #expect(
            content.simulationConfig.selectedAnalysis
                == .tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9))
        )
    }

    @Test
    @MainActor
    func installTemplateSeedsProjectFiles() throws {
        let root = try makeTemporaryProjectRoot("install")
        defer { removeTemporaryProjectRoot(root) }

        let service = ProjectService()
        try service.createProject(at: root)

        let content = NewProjectTemplate.cmosInverter()
        try service.installTemplate(content, forProjectAt: root)

        let netlistURL = root.appending(path: content.netlistFileName)
        let savedNetlist = try String(contentsOf: netlistURL, encoding: .utf8)
        #expect(savedNetlist == content.netlist)

        let placement = try service.loadSchematicPlacement(forProjectAt: root)
        #expect(placement.sourceNetlist == content.netlist)
        #expect(
            placement.document.components.count
                == content.schematicPlacement.document.components.count
        )

        let simulation = try service.loadSimulationConfig(forProjectAt: root)
        #expect(simulation.selectedAnalysis == content.simulationConfig.selectedAnalysis)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func templateNetlistSimulatesToCompletion() async throws {
        let content = NewProjectTemplate.cmosInverter()

        let result = try await SimulationService().runSPICE(
            source: content.netlist,
            fileName: content.netlistFileName
        )

        #expect(result.status == .completed)
        let waveform = try #require(result.waveform)
        #expect(waveform.pointCount > 50)
        #expect(waveform.variables.contains { $0.name.lowercased().contains("out") })
    }

    private func makeTemporaryProjectRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "NewProjectTemplateTests-\(name)-\(UUID().uuidString)")
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
}
