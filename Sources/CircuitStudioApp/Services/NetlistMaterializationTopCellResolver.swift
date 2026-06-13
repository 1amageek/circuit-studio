import Foundation

struct NetlistMaterializationTopCellResolver: Sendable {
    let projectService: ProjectService

    init(projectService: ProjectService) {
        self.projectService = projectService
    }

    func resolveTopCellName(
        forProjectAt projectRoot: URL,
        fallbackTopCellName: String
    ) -> NetlistMaterializationTopCellResolution {
        do {
            guard let manifest = try projectService.loadStudioSessionManifestIfPresent(
                forProjectAt: projectRoot
            ) else {
                return NetlistMaterializationTopCellResolution(
                    topCellName: fallbackTopCellName,
                    warning: nil
                )
            }
            let topCell = manifest.topCell.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !topCell.isEmpty else {
                return NetlistMaterializationTopCellResolution(
                    topCellName: fallbackTopCellName,
                    warning: "Studio session manifest has an empty top cell; using '\(fallbackTopCellName)'."
                )
            }
            return NetlistMaterializationTopCellResolution(topCellName: topCell, warning: nil)
        } catch {
            return NetlistMaterializationTopCellResolution(
                topCellName: fallbackTopCellName,
                warning: "Could not read studio session manifest for SPICE top-cell selection: \(error.localizedDescription). Using '\(fallbackTopCellName)'."
            )
        }
    }
}
