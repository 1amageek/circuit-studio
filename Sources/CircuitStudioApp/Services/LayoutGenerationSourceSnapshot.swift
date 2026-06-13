import Foundation

struct LayoutGenerationSourceSnapshot: Sendable, Codable, Equatable {
    let projectRoot: LayoutGenerationFileSnapshot
    let selectedFile: LayoutGenerationFileSnapshot
    let xcircuiteProjectManifest: LayoutGenerationFileSnapshot
    let studioSessionManifest: LayoutGenerationFileSnapshot
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
        let xcircuiteProjectManifestURL = projectRootURL.map {
            projectService.xcircuiteProjectManifestURL(inProjectAt: $0)
        }
        let studioSessionManifestURL = projectRootURL.flatMap { projectRoot in
            resolvedURL { try projectService.studioSessionManifestURL(inProjectAt: projectRoot) }
        }
        let cellsDirectoryURL = projectRootURL.map { projectService.cellsDirectoryURL(inProjectAt: $0) }
        let topNetlistURL = projectRootURL.map { projectService.topNetlistURL(inProjectAt: $0) }
        let schematicURL = projectRootURL.flatMap { projectRoot in
            resolvedURL { try projectService.cellSchematicURL(cellName: activeCellName, inProjectAt: projectRoot) }
        }
        let layoutURL = projectRootURL.flatMap { projectRoot in
            resolvedURL { try projectService.cellLayoutDocumentURL(cellName: activeCellName, inProjectAt: projectRoot) }
        }

        return LayoutGenerationSourceSnapshot(
            projectRoot: .capture(projectRootURL),
            selectedFile: .capture(selectedFileURL),
            xcircuiteProjectManifest: .capture(xcircuiteProjectManifestURL),
            studioSessionManifest: .capture(studioSessionManifestURL),
            cellsDirectory: .capture(cellsDirectoryURL),
            topNetlist: .capture(topNetlistURL),
            activeCellSchematic: .capture(schematicURL),
            activeCellLayout: .capture(layoutURL),
            netlistMaterialization: netlistMaterialization
        )
    }

    private static func resolvedURL(_ makeURL: () throws -> URL) -> URL? {
        do {
            return try makeURL()
        } catch {
            return nil
        }
    }
}
