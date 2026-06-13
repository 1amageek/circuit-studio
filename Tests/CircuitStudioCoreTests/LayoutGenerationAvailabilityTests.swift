import CoreGraphics
import Foundation
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore

@Suite("Layout Generation Availability")
struct LayoutGenerationAvailabilityTests {

    @Test func componentWithoutWiresIsAvailable() {
        let document = SchematicDocument(components: [
            PlacedComponent(
                deviceKindID: "resistor",
                name: "R1",
                position: .zero,
                parameters: ["r": 1000]
            ),
        ])

        let availability = LayoutGenerationAvailability.evaluate(
            document: document,
            catalog: .standard(),
            activeCellName: "TOP"
        )

        #expect(availability.isAvailable)
        #expect(availability.reason == nil)
        #expect(availability.help.contains("No schematic wires"))
    }

    @Test func emptySchematicReportsReason() {
        let availability = LayoutGenerationAvailability.evaluate(
            document: SchematicDocument(),
            catalog: .standard(),
            activeCellName: "TOP"
        )

        #expect(!availability.isAvailable)
        #expect(availability.reason == "Cell 'TOP' has no schematic components.")
    }

    @Test func sourceOnlySchematicReportsNoPhysicalGeometry() {
        let document = SchematicDocument(components: [
            PlacedComponent(
                deviceKindID: "vsource",
                name: "V1",
                position: .zero,
                parameters: ["dc": 1.0]
            ),
            PlacedComponent(
                deviceKindID: "ground",
                name: "GND1",
                position: CGPoint(x: 100, y: 0)
            ),
        ])

        let availability = LayoutGenerationAvailability.evaluate(
            document: document,
            catalog: .standard(),
            activeCellName: "TOP"
        )

        #expect(!availability.isAvailable)
        #expect(availability.reason?.contains("only contains ports, sources") == true)
    }

    @Test func unsupportedPhysicalDeviceReportsReason() {
        let document = SchematicDocument(components: [
            PlacedComponent(
                deviceKindID: "inductor",
                name: "L1",
                position: .zero,
                parameters: ["l": 1e-6]
            ),
        ])

        let availability = LayoutGenerationAvailability.evaluate(
            document: document,
            catalog: .standard(),
            activeCellName: "TOP"
        )

        #expect(!availability.isAvailable)
        #expect(availability.reason?.contains("L1") == true)
        #expect(availability.reason?.contains("inductor") == true)
    }

    @Test @MainActor func diagnosticMessageContainsProjectAndCellContext() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "LayoutGenerationDiagnostics-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let metadataDirectory = root.appending(path: ".xcircuite")
        let topCellDirectory = root.appending(path: "cells").appending(path: "Top")
        let leafCellDirectory = root.appending(path: "cells").appending(path: "Leaf")
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: topCellDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: leafCellDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: metadataDirectory.appending(path: "project.json"))
        try Data("* test\n".utf8).write(to: root.appending(path: "top.cir"))
        try Data("{}".utf8).write(to: topCellDirectory.appending(path: "schematic.json"))
        try Data("{}".utf8).write(to: leafCellDirectory.appending(path: "schematic.json"))

        let project = StudioSession()
        try project.addCell(named: "Leaf")
        project.schematicViewModel.document.components = [
            PlacedComponent(
                deviceKindID: "inductor",
                name: "L1",
                position: .zero,
                parameters: ["l": 1e-6]
            ),
        ]
        try project.activateCell(named: "Top")

        let report = LayoutGenerationPreflightReport.make(
            context: "test",
            project: project,
            projectRootURL: root,
            selectedFileURL: root.appending(path: "top.cir"),
            projectService: ProjectService(),
            catalog: .standard(),
            workspace: "layout",
            netlistMaterialization: LayoutGenerationNetlistMaterializationSnapshot(
                status: .none,
                message: nil
            )
        )
        let message = report.diagnosticMessage()

        #expect(message.contains("Layout generation preflight [test]"))
        #expect(message.contains("workspace=layout"))
        #expect(message.contains("code=emptySchematic"))
        #expect(message.contains("projectRoot=\(root.path(percentEncoded: false))(exists=true)"))
        #expect(message.contains("selectedFile=\(root.appending(path: "top.cir").path(percentEncoded: false))(exists=true)"))
        #expect(message.contains("manifest=\(metadataDirectory.appending(path: "project.json").path(percentEncoded: false))(exists=true)"))
        #expect(message.contains("cellsDirectory=\(root.appending(path: "cells").path(percentEncoded: false))(exists=true)"))
        #expect(message.contains("topCir=\(root.appending(path: "top.cir").path(percentEncoded: false))(exists=true)"))
        #expect(message.contains("topCell='Top'"))
        #expect(message.contains("activeCell='Top'"))
        #expect(message.contains("enabled=false"))
        #expect(message.contains("components=0"))
        #expect(message.contains("wires=0"))
        #expect(message.contains("unsupportedPhysical=0"))
        #expect(report.cells.map(\.name).sorted() == ["Leaf", "Top"])
        #expect(report.cells.first { $0.name == "Leaf" }?.componentNames == ["L1"])
        #expect(report.cells.first { $0.name == "Leaf" }?.schematic.path == leafCellDirectory.appending(path: "schematic.json").path(percentEncoded: false))
        #expect(report.cells.first { $0.name == "Leaf" }?.schematic.exists == true)
        #expect(report.jsonMessage().contains("\"activeCell\":\"Top\""))
    }

    @Test @MainActor func topCirWithoutMaterializedSchematicReportsSpecificReason() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "LayoutGenerationTopCirOnly-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appending(path: ".xcircuite"),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: root.appending(path: ".xcircuite/project.json"))
        try Data("R1 in out 1k\n.end\n".utf8).write(to: root.appending(path: "top.cir"))

        let project = StudioSession()
        let report = LayoutGenerationPreflightReport.make(
            context: "test",
            project: project,
            projectRootURL: root,
            selectedFileURL: root.appending(path: "top.cir"),
            projectService: ProjectService(),
            catalog: .standard(),
            workspace: "layout",
            netlistMaterialization: LayoutGenerationNetlistMaterializationSnapshot(
                status: .none,
                message: nil
            )
        )

        #expect(!report.availability.isAvailable)
        #expect(report.availability.code == .missingMaterializedSchematic)
        #expect(report.availability.reason?.contains("top.cir") == true)
        #expect(report.availability.reason?.contains("schematic.json is missing") == true)
    }

    @Test @MainActor func topCirImportMaterializesSchematicAndEnablesLayoutGeneration() async throws {
        let source = """
        * resistor divider
        V1 in 0 5
        R1 in out 1k
        C1 out 0 2p
        .end
        """

        let result = try await SPICESchematicImporter().importTopLevel(
            source: source,
            fileName: "top.cir",
            topCellName: "Top",
            catalog: .standard()
        )
        let project = StudioSession()
        try project.replaceCells(
            result.cells.map { ($0.name, $0.schematic) },
            topCell: result.topCellName,
            activeCell: result.activeCellName
        )

        let availability = LayoutGenerationAvailability.evaluate(
            document: project.schematicViewModel.document,
            catalog: .standard(),
            activeCellName: project.activeCellName
        )
        let nets = NetExtractor().extract(from: project.schematicViewModel.document)

        #expect(availability.isAvailable)
        #expect(project.schematicViewModel.document.components.map(\.name).sorted() == ["c1", "r1", "v1"])
        #expect(Set(nets.map(\.name)) == Set(["0", "in", "out"]))
    }

    @Test @MainActor func duplicateComponentNamesThrowBeforeLayoutGeneration() throws {
        let document = SchematicDocument(components: [
            PlacedComponent(
                deviceKindID: "resistor",
                name: "R1",
                position: .zero,
                parameters: ["r": 1000]
            ),
            PlacedComponent(
                deviceKindID: "resistor",
                name: "R1",
                position: CGPoint(x: 100, y: 0),
                parameters: ["r": 2000]
            ),
        ])

        #expect(throws: AutoLayoutError.duplicateComponentNames(["R1"])) {
            try AutoLayoutService().generate(from: document, catalog: .standard())
        }
    }

    @Test @MainActor func componentWithoutWiresGeneratesPlacementOnlyLayout() throws {
        let document = SchematicDocument(components: [
            PlacedComponent(
                deviceKindID: "resistor",
                name: "R1",
                position: .zero,
                parameters: ["r": 1000]
            ),
        ])

        let output = try AutoLayoutService().generate(from: document, catalog: .standard())

        #expect(output.layoutContainsPlacedInstances)
        #expect(output.unroutedNets.isEmpty)
        #expect(output.designUnit.componentToInstance.count == 1)
        #expect(output.designUnit.netNameToLayoutNet.isEmpty)
    }

    @Test @MainActor func sourceOnlyAutoLayoutThrowsNoPlaceableComponents() throws {
        let document = SchematicDocument(components: [
            PlacedComponent(
                deviceKindID: "vsource",
                name: "V1",
                position: .zero,
                parameters: ["dc": 1.0]
            ),
            PlacedComponent(
                deviceKindID: "ground",
                name: "GND1",
                position: CGPoint(x: 100, y: 0)
            ),
        ])

        #expect(throws: AutoLayoutError.noPlaceableComponents) {
            try AutoLayoutService().generate(from: document, catalog: .standard())
        }
    }
}

private extension AutoLayoutOutput {
    var layoutContainsPlacedInstances: Bool {
        document.cells.contains { !$0.instances.isEmpty }
    }
}
