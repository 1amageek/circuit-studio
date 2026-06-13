import CoreGraphics
import Foundation
import CircuitPhysicalDesign
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore

@Suite("Circuit Layout Availability")
struct CircuitLayoutAvailabilityTests {

    @Test func componentWithoutWiresIsAvailable() {
        let document = SchematicDocument(components: [
            PlacedComponent(
                deviceKindID: "resistor",
                name: "R1",
                position: .zero,
                parameters: ["r": 1000]
            ),
        ])

        let availability = CircuitLayoutAvailability.evaluate(
            document: document,
            catalog: .standard(),
            activeCellName: "TOP"
        )

        #expect(availability.isAvailable)
        #expect(availability.reason == nil)
        #expect(availability.help.contains("No schematic wires"))
    }

    @Test func emptySchematicReportsReason() {
        let availability = CircuitLayoutAvailability.evaluate(
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

        let availability = CircuitLayoutAvailability.evaluate(
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

        let availability = CircuitLayoutAvailability.evaluate(
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
        defer { removeTemporaryDirectory(root) }
        let metadataDirectory = root.appending(path: ".xcircuite")
        let topCellDirectory = root.appending(path: "cells").appending(path: "Top")
        let leafCellDirectory = root.appending(path: "cells").appending(path: "Leaf")
        let projectService = ProjectService()
        try projectService.createProject(at: root)
        try FileManager.default.createDirectory(at: topCellDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: leafCellDirectory, withIntermediateDirectories: true)
        try projectService.saveStudioSessionManifest(
            StudioSessionManifest(topCell: "Top", activeCell: "Top"),
            forProjectAt: root
        )
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
            projectService: projectService,
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
        #expect(message.contains("xcircuiteManifest=\(metadataDirectory.appending(path: "project.json").path(percentEncoded: false))(exists=true)"))
        #expect(message.contains("studioSessionManifest=\(metadataDirectory.appending(path: "studio-session.json").path(percentEncoded: false))(exists=true)"))
        #expect(message.contains("cellsDirectory=\(root.appending(path: "cells").path(percentEncoded: false))(exists=true)"))
        #expect(message.contains("topCir=\(root.appending(path: "top.cir").path(percentEncoded: false))(exists=true)"))
        #expect(message.contains("topCell='Top'"))
        #expect(message.contains("activeCell='Top'"))
        #expect(message.contains("netlistMaterializationMessage=none"))
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

    @Test @MainActor func diagnosticMessageIncludesPathResolutionFailures() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "LayoutGenerationPathResolution-\(UUID().uuidString)")
        defer { removeTemporaryDirectory(root) }
        let projectService = ProjectService()
        try projectService.createProject(at: root)

        let invalidCell = CellWorkspace(name: "1Invalid")
        let source = LayoutGenerationSourceSnapshot.capture(
            projectRootURL: root,
            selectedFileURL: nil,
            activeCellName: invalidCell.name,
            projectService: projectService,
            netlistMaterialization: LayoutGenerationNetlistMaterializationSnapshot(
                status: .none,
                message: nil
            )
        )
        let snapshot = LayoutGenerationCellSnapshot.capture(
            cell: invalidCell,
            topCellName: invalidCell.name,
            activeCellName: invalidCell.name,
            source: source,
            projectRootURL: root,
            projectService: projectService,
            catalog: .standard()
        )
        let report = LayoutGenerationPreflightReport(
            context: "test",
            workspace: "layout",
            topCell: invalidCell.name,
            activeCell: invalidCell.name,
            source: source,
            activeCellSummary: snapshot,
            cells: [snapshot]
        )
        let message = report.diagnosticMessage()

        #expect(snapshot.pathResolutionFailures.count == 2)
        #expect(message.contains("activeCellPathResolutionFailures=["))
        #expect(message.contains("Cell name '1Invalid' is not a valid SPICE identifier"))
        #expect(report.jsonMessage().contains("\"pathResolutionFailures\""))
    }

    @Test @MainActor func topCirWithoutMaterializedSchematicReportsSpecificReason() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "LayoutGenerationTopCirOnly-\(UUID().uuidString)")
        defer { removeTemporaryDirectory(root) }
        let projectService = ProjectService()
        try projectService.createProject(at: root)
        try Data("R1 in out 1k\n.end\n".utf8).write(to: root.appending(path: "top.cir"))

        let project = StudioSession()
        let report = LayoutGenerationPreflightReport.make(
            context: "test",
            project: project,
            projectRootURL: root,
            selectedFileURL: root.appending(path: "top.cir"),
            projectService: projectService,
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

        let availability = CircuitLayoutAvailability.evaluate(
            document: project.schematicViewModel.document,
            catalog: .standard(),
            activeCellName: project.activeCellName
        )
        let nets = NetExtractor().extract(from: project.schematicViewModel.document)

        #expect(availability.isAvailable)
        #expect(project.schematicViewModel.document.components.map(\.name).sorted() == ["c1", "r1", "v1"])
        #expect(Set(nets.map(\.name)) == Set(["0", "in", "out"]))
    }

    @Test @MainActor func invalidStudioSessionManifestDoesNotBlockTopCirMaterialization() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "LayoutGenerationInvalidSessionManifest-\(UUID().uuidString)")
        defer { removeTemporaryDirectory(root) }

        let projectService = ProjectService()
        try projectService.createProject(at: root)
        try Data("{}".utf8).write(to: try projectService.studioSessionManifestURL(inProjectAt: root))
        try Data("R1 in out 1k\n.end\n".utf8).write(to: root.appending(path: "top.cir"))

        let resolution = NetlistMaterializationTopCellResolver(
            projectService: projectService
        ).resolveTopCellName(
            forProjectAt: root,
            fallbackTopCellName: "Top"
        )

        #expect(resolution.topCellName == "Top")
        #expect(resolution.warning?.contains("Could not read studio session manifest") == true)

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
            topCellName: resolution.topCellName,
            catalog: .standard()
        )
        let project = StudioSession()
        try project.replaceCells(
            result.cells.map { ($0.name, $0.schematic) },
            topCell: result.topCellName,
            activeCell: result.activeCellName
        )

        let report = LayoutGenerationPreflightReport.make(
            context: "test",
            project: project,
            projectRootURL: root,
            selectedFileURL: root.appending(path: "top.cir"),
            projectService: projectService,
            catalog: .standard(),
            workspace: "layout",
            netlistMaterialization: LayoutGenerationNetlistMaterializationSnapshot(
                status: .succeeded,
                message: resolution.warning
            )
        )

        #expect(report.availability.isAvailable)
        #expect(report.source.studioSessionManifest.exists)
        #expect(report.source.xcircuiteProjectManifest.exists)
        #expect(report.diagnosticMessage().contains("Could not read studio session manifest"))
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

        #expect(throws: CircuitLayoutSynthesisError.duplicateComponentNames(["R1"])) {
            try CircuitLayoutSynthesizer().generate(from: document, catalog: .standard())
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

        let output = try CircuitLayoutSynthesizer().generate(from: document, catalog: .standard())

        #expect(output.layoutContainsPlacedInstances)
        #expect(output.unroutedNets.isEmpty)
        #expect(output.designUnit.componentToInstance.count == 1)
        #expect(output.designUnit.netNameToLayoutNet.isEmpty)
    }

    @Test @MainActor func sourceOnlyCircuitLayoutThrowsNoPlaceableComponents() throws {
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

        #expect(throws: CircuitLayoutSynthesisError.noPlaceableComponents) {
            try CircuitLayoutSynthesizer().generate(from: document, catalog: .standard())
        }
    }
}

private extension CircuitLayoutSynthesisOutput {
    var layoutContainsPlacedInstances: Bool {
        document.cells.contains { !$0.instances.isEmpty }
    }
}

private func removeTemporaryDirectory(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove temporary directory: \(error)")
    }
}
