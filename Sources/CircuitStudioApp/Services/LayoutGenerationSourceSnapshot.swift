import Foundation

struct LayoutGenerationSourceSnapshot: Sendable, Codable, Equatable {
    let projectRoot: LayoutGenerationFileSnapshot
    let selectedFile: LayoutGenerationFileSnapshot
    let manifest: LayoutGenerationFileSnapshot
    let cellsDirectory: LayoutGenerationFileSnapshot
    let topNetlist: LayoutGenerationFileSnapshot
    let activeCellSchematic: LayoutGenerationFileSnapshot
    let activeCellLayout: LayoutGenerationFileSnapshot
    let netlistMaterialization: LayoutGenerationNetlistMaterializationSnapshot?

    static func capture(
        projectRootURL: URL?,
        selectedFileURL: URL?,
        activeCellName: String,
        projectService: ProjectService,
        netlistMaterialization: LayoutGenerationNetlistMaterializationSnapshot?
    ) -> LayoutGenerationSourceSnapshot {
        let manifestURL = projectRootURL.flatMap { try? projectService.projectManifestURL(inProjectAt: $0) }
        let cellsDirectoryURL = projectRootURL.map { projectService.cellsDirectoryURL(inProjectAt: $0) }
        let topNetlistURL = projectRootURL.map { projectService.topNetlistURL(inProjectAt: $0) }
        let schematicURL = projectRootURL.flatMap {
            try? projectService.cellSchematicURL(cellName: activeCellName, inProjectAt: $0)
        }
        let layoutURL = projectRootURL.flatMap {
            try? projectService.cellLayoutDocumentURL(cellName: activeCellName, inProjectAt: $0)
        }

        return LayoutGenerationSourceSnapshot(
            projectRoot: .capture(projectRootURL),
            selectedFile: .capture(selectedFileURL),
            manifest: .capture(manifestURL),
            cellsDirectory: .capture(cellsDirectoryURL),
            topNetlist: .capture(topNetlistURL),
            activeCellSchematic: .capture(schematicURL),
            activeCellLayout: .capture(layoutURL),
            netlistMaterialization: netlistMaterialization
        )
    }
}
