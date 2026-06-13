import Foundation
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore

@Suite("New Project Template Tests")
struct NewProjectTemplateTests {

    @Test
    @MainActor
    func templateContentIsConsistent() throws {
        let content = try NewProjectTemplate.cmosInverter()

        #expect(content.netlistFileName == "top.cir")
        #expect(content.netlist.hasPrefix("* Welcome to Circuit Studio!"))
        #expect(content.netlist.contains("MP1"))
        #expect(content.netlist.contains("MN1"))
        #expect(content.netlist.contains(".tran"))
        #expect(content.netlist.contains(".end"))

        // The template seeds exactly the top cell, which carries the drawn
        // schematic.
        #expect(content.topCellName == content.activeCellName)
        let topCell = try #require(content.cells.first { $0.name == content.topCellName })
        #expect(!topCell.schematic.components.isEmpty)
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

        let content = try NewProjectTemplate.cmosInverter()
        try service.installTemplate(content, forProjectAt: root)

        let netlistURL = root.appending(path: content.netlistFileName)
        let savedNetlist = try String(contentsOf: netlistURL, encoding: .utf8)
        #expect(savedNetlist == content.netlist)

        // Every template cell lands under cells/<name>/schematic.json, and the
        // studio session manifest records the top/active designation.
        let cellNames = try service.listCellNames(forProjectAt: root)
        #expect(cellNames == content.cells.map(\.name).sorted())

        let topCell = try #require(content.cells.first { $0.name == content.topCellName })
        let savedTop = try service.loadCellSchematic(
            cellName: content.topCellName,
            forProjectAt: root
        )
        #expect(savedTop.components.count == topCell.schematic.components.count)

        let manifest = try #require(try service.loadStudioSessionManifestIfPresent(forProjectAt: root))
        #expect(manifest.topCell == content.topCellName)
        #expect(manifest.activeCell == content.activeCellName)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: ".xcircuite/studio-session.json").path))

        let simulation = try service.loadSimulationConfig(forProjectAt: root)
        #expect(simulation.selectedAnalysis == content.simulationConfig.selectedAnalysis)
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func templateNetlistSimulatesToCompletion() async throws {
        let content = try NewProjectTemplate.cmosInverter()

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
