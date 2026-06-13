import Foundation
import CircuitStudioCore

struct LayoutGenerationPreflightReport: Sendable, Codable, Equatable {
    let context: String
    let workspace: String
    let topCell: String
    let activeCell: String
    let source: LayoutGenerationSourceSnapshot
    let activeCellSummary: LayoutGenerationCellSnapshot
    let cells: [LayoutGenerationCellSnapshot]

    var availability: LayoutGenerationAvailability {
        activeCellSummary.availability
    }

    var signature: String {
        [
            workspace,
            topCell,
            activeCell,
            availability.code.rawValue,
            availability.reason ?? "none",
            "\(activeCellSummary.components)",
            "\(activeCellSummary.wires)",
            "\(activeCellSummary.labels)",
            source.projectRoot.path ?? "none",
            "\(source.xcircuiteProjectManifest.exists)",
            "\(source.studioSessionManifest.exists)",
            "\(source.cellsDirectory.exists)",
            "\(source.topNetlist.exists)",
            "\(source.activeCellSchematic.exists)",
            source.netlistMaterialization?.status.rawValue ?? "none",
            source.netlistMaterialization?.message ?? "none",
            cells.map { "\($0.name):\($0.components):\($0.wires):\($0.labels):\($0.layoutHasContent)" }
                .joined(separator: "|"),
        ].joined(separator: "|")
    }

    @MainActor
    static func make(
        context: String,
        project: StudioSession,
        projectRootURL: URL?,
        selectedFileURL: URL?,
        projectService: ProjectService,
        catalog: DeviceCatalog,
        workspace: String,
        netlistMaterialization: LayoutGenerationNetlistMaterializationSnapshot?
    ) -> LayoutGenerationPreflightReport {
        let source = LayoutGenerationSourceSnapshot.capture(
            projectRootURL: projectRootURL,
            selectedFileURL: selectedFileURL,
            activeCellName: project.activeCellName,
            projectService: projectService,
            netlistMaterialization: netlistMaterialization
        )
        let cells = project.cells.map { cell in
            LayoutGenerationCellSnapshot.capture(
                cell: cell,
                topCellName: project.topCellName,
                activeCellName: project.activeCellName,
                source: source,
                projectRootURL: projectRootURL,
                projectService: projectService,
                catalog: catalog
            )
        }
        let active = cells.first { $0.isActive }
            ?? LayoutGenerationCellSnapshot.capture(
                cell: project.activeCell,
                topCellName: project.topCellName,
                activeCellName: project.activeCellName,
                source: source,
                projectRootURL: projectRootURL,
                projectService: projectService,
                catalog: catalog
            )
        return LayoutGenerationPreflightReport(
            context: context,
            workspace: workspace,
            topCell: project.topCellName,
            activeCell: project.activeCellName,
            source: source,
            activeCellSummary: active,
            cells: cells
        )
    }

    func diagnosticMessage() -> String {
        [
            "Layout generation preflight [\(context)]",
            "workspace=\(workspace)",
            "enabled=\(availability.isAvailable)",
            "code=\(availability.code.rawValue)",
            "reason=\(availability.reason ?? "none")",
            "projectRoot=\(source.projectRoot.displayPath)(exists=\(source.projectRoot.exists))",
            "selectedFile=\(source.selectedFile.displayPath)(exists=\(source.selectedFile.exists))",
            "xcircuiteManifest=\(source.xcircuiteProjectManifest.displayPath)(exists=\(source.xcircuiteProjectManifest.exists))",
            "studioSessionManifest=\(source.studioSessionManifest.displayPath)(exists=\(source.studioSessionManifest.exists))",
            "cellsDirectory=\(source.cellsDirectory.displayPath)(exists=\(source.cellsDirectory.exists))",
            "topCir=\(source.topNetlist.displayPath)(exists=\(source.topNetlist.exists))",
            "activeSchematic=\(source.activeCellSchematic.displayPath)(exists=\(source.activeCellSchematic.exists))",
            "netlistMaterialization=\(source.netlistMaterialization?.status.rawValue ?? "none")",
            "netlistMaterializationMessage=\(source.netlistMaterialization?.message ?? "none")",
            "topCell='\(topCell)'",
            "activeCell='\(activeCell)'",
            "components=\(activeCellSummary.components)",
            "wires=\(activeCellSummary.wires)",
            "labels=\(activeCellSummary.labels)",
            "placeable=\(activeCellSummary.placeable)",
            "unsupportedPhysical=\(activeCellSummary.unsupportedPhysical)",
            "hierarchical=\(activeCellSummary.hierarchical)",
            "unknown=\(activeCellSummary.unknown)",
            "duplicateNames=\(activeCellSummary.duplicateNames)",
        ].joined(separator: "; ")
    }

    func jsonMessage() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return diagnosticMessage()
        }
        return string
    }
}
