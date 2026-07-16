import Foundation
import CircuitStudioCore
import LayoutCore
import LayoutTech
import LayoutIO
import DesignFlowKernel
import Xcircuite

/// Manages `.xcircuite/` project directory for persistent workspace state.
public struct ProjectService: Sendable {

    private static let pexConfigFileName = "pex.json"
    private static let pexDirectoryName = "pex"
    private static let pexRunsDirectoryName = "runs"
    private static let pexTOMLFileName = "pex.toml"
    private static let studioSessionManifestFileName = "studio-session.json"
    private static let layoutTechFileName = "layout-tech.json"
    private static let cellsDirectoryName = "cells"
    private static let cellSchematicFileName = "schematic.json"
    private static let cellLayoutFileName = "layout.json"
    private static let cellDesignUnitFileName = "design-unit.json"

    public init() {}

    // MARK: - Project Lifecycle

    /// Creates a new project at the given directory, initializing `.xcircuite/`.
    func createProject(at directory: URL) async throws {
        try await ensureXcircuiteProjectManifest(forProjectAt: directory, topDesignName: nil)

        // Write default workspace config
        let defaultConfig = WorkspaceConfig()
        try saveWorkspaceConfig(defaultConfig, forProjectAt: directory)

        // Bootstrap PEX files so the project is immediately runnable by `pexengine`.
        try ensurePEXProjectFiles(forProjectAt: directory)
    }

    /// Seeds a project with template content (sample netlist, design cells,
    /// and simulation config) so it opens as a working example.
    func installTemplate(_ content: ProjectTemplateContent, forProjectAt projectRoot: URL) async throws {
        try saveNetlist(content.netlist, named: content.netlistFileName, inProjectAt: projectRoot)
        for cell in content.cells {
            try saveCellSchematic(cell.schematic, cellName: cell.name, forProjectAt: projectRoot)
        }
        try await saveStudioSessionManifest(
            StudioSessionManifest(topCell: content.topCellName, activeCell: content.activeCellName),
            forProjectAt: projectRoot
        )
        try saveSimulationConfig(content.simulationConfig, forProjectAt: projectRoot)
    }

    /// Returns `true` if the directory contains a `.xcircuite/` folder.
    func isProject(_ directory: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(
            atPath: XcircuiteWorkspaceLayout(projectRoot: directory).workspaceURL.path(percentEncoded: false),
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    // MARK: - Workspace Config

    func saveWorkspaceConfig(_ config: WorkspaceConfig, forProjectAt projectRoot: URL) throws {
        let url = try configurationFileURL(named: "workspace.json", inProjectAt: projectRoot)
        try writeJSON(config, to: url, forProjectAt: projectRoot)
    }

    func loadWorkspaceConfig(forProjectAt projectRoot: URL) throws -> WorkspaceConfig {
        let url = try configurationFileURL(named: "workspace.json", inProjectAt: projectRoot)
        return try readJSON(WorkspaceConfig.self, from: url)
    }

    // MARK: - Manifests

    func xcircuiteProjectManifestURL(inProjectAt projectRoot: URL) -> URL {
        XcircuiteWorkspaceLayout(projectRoot: projectRoot).manifestURL
    }

    func studioSessionManifestURL(inProjectAt projectRoot: URL) throws -> URL {
        try configurationFileURL(named: Self.studioSessionManifestFileName, inProjectAt: projectRoot)
    }

    func saveStudioSessionManifest(
        _ manifest: StudioSessionManifest,
        forProjectAt projectRoot: URL
    ) async throws {
        try await ensureXcircuiteProjectManifest(forProjectAt: projectRoot, topDesignName: manifest.topCell)
        let url = try studioSessionManifestURL(inProjectAt: projectRoot)
        try writeJSON(manifest, to: url, forProjectAt: projectRoot)
    }

    /// Returns nil when no Circuit Studio session manifest has been saved.
    /// A present but unreadable `studio-session.json` throws so corruption
    /// surfaces. `.xcircuite/project.json` is always the package manifest.
    func loadStudioSessionManifestIfPresent(forProjectAt projectRoot: URL) throws -> StudioSessionManifest? {
        let url = try studioSessionManifestURL(inProjectAt: projectRoot)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        return try readJSON(StudioSessionManifest.self, from: url)
    }

    // MARK: - Cells

    /// `cells/` at the project root — one subdirectory per design cell.
    func cellsDirectoryURL(inProjectAt projectRoot: URL) -> URL {
        projectRoot.appending(path: Self.cellsDirectoryName)
    }

    func cellSchematicURL(cellName: String, inProjectAt projectRoot: URL) throws -> URL {
        try cellFileURL(Self.cellSchematicFileName, cellName: cellName, inProjectAt: projectRoot)
    }

    func cellLayoutDocumentURL(cellName: String, inProjectAt projectRoot: URL) throws -> URL {
        try cellFileURL(Self.cellLayoutFileName, cellName: cellName, inProjectAt: projectRoot)
    }

    /// Names of all cells persisted in the project, sorted. A cell exists
    /// when `cells/<name>/schematic.json` does.
    func listCellNames(forProjectAt projectRoot: URL) throws -> [String] {
        let cellsDirectory = cellsDirectoryURL(inProjectAt: projectRoot)
        guard FileManager.default.fileExists(atPath: cellsDirectory.path(percentEncoded: false)) else {
            return []
        }
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: cellsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        } catch {
            throw StudioError.projectLoadFailed(
                "Failed to scan cells directory: \(error.localizedDescription)"
            )
        }
        var cellNames: [String] = []
        for url in entries {
            let schematic = url.appending(path: Self.cellSchematicFileName)
            guard FileManager.default.fileExists(atPath: schematic.path(percentEncoded: false)) else {
                continue
            }
            let cellName = url.lastPathComponent
            guard CellInterface.isValidSPICEName(cellName) else {
                throw CellLibraryError.invalidCellName(cellName)
            }
            cellNames.append(cellName)
        }
        return cellNames.sorted()
    }

    func saveCellSchematic(
        _ document: SchematicDocument,
        cellName: String,
        forProjectAt projectRoot: URL
    ) throws {
        let url = try cellSchematicURL(cellName: cellName, inProjectAt: projectRoot)
        try ensureDirectory(at: url.deletingLastPathComponent())
        try writeJSON(document, to: url, forProjectAt: projectRoot)
    }

    func loadCellSchematic(cellName: String, forProjectAt projectRoot: URL) throws -> SchematicDocument {
        let url = try cellSchematicURL(cellName: cellName, inProjectAt: projectRoot)
        return try readJSON(SchematicDocument.self, from: url)
    }

    /// Promotes an imported SPICE schematic into the project's canonical cell
    /// artifacts. This keeps project-open, layout preflight, and later flow
    /// stages reading the same cell state instead of depending on an
    /// in-memory reconstruction that disappears on reopen.
    func saveMaterializedSchematic(
        _ result: SPICESchematicImportResult,
        forProjectAt projectRoot: URL
    ) async throws {
        for cell in result.cells {
            try saveCellSchematic(
                cell.schematic,
                cellName: cell.name,
                forProjectAt: projectRoot
            )
        }
        try await saveStudioSessionManifest(
            StudioSessionManifest(
                topCell: result.topCellName,
                activeCell: result.activeCellName
            ),
            forProjectAt: projectRoot
        )
    }

    /// Deletes a cell's directory and everything in it. Removing a cell
    /// that is not on disk is a no-op — the in-memory cell simply was
    /// never saved.
    func removeCellDirectory(cellName: String, forProjectAt projectRoot: URL) throws {
        let directory = try cellDirectoryURL(cellName: cellName, inProjectAt: projectRoot)
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to delete cell '\(cellName)': \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Simulation Config

    func saveSimulationConfig(_ config: SimulationConfig, forProjectAt projectRoot: URL) throws {
        let url = try configurationFileURL(named: "simulation.json", inProjectAt: projectRoot)
        try writeJSON(config, to: url, forProjectAt: projectRoot)
    }

    func loadSimulationConfig(forProjectAt projectRoot: URL) throws -> SimulationConfig {
        let url = try configurationFileURL(named: "simulation.json", inProjectAt: projectRoot)
        return try readJSON(SimulationConfig.self, from: url)
    }

    /// Returns nil when the project has no simulation config yet. A present
    /// but unreadable config throws so corruption surfaces instead of the
    /// app silently opening with default analysis settings.
    func loadSimulationConfigIfPresent(forProjectAt projectRoot: URL) throws -> SimulationConfig? {
        let url = try configurationFileURL(named: "simulation.json", inProjectAt: projectRoot)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        return try readJSON(SimulationConfig.self, from: url)
    }

    // MARK: - PEX Config

    /// Ensures all PEX-related files and directories exist.
    ///
    /// Files created:
    /// - `.xcircuite/pex.json`
    /// - `pex.toml`
    /// - `tech.json` (if missing and config points to default relative path)
    /// - `.xcircuite/pex/runs/`
    func ensurePEXProjectFiles(forProjectAt projectRoot: URL) throws {
        try ensureConfigurationDirectory(forProjectAt: projectRoot)

        let pexDir = pexDirectoryURL(inProjectAt: projectRoot)
        do {
            try FileManager.default.createDirectory(
                at: pexDir,
                withIntermediateDirectories: true
            )
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to create PEX directory: \(error.localizedDescription)"
            )
        }

        let runsDir = pexRunsDirectoryURL(inProjectAt: projectRoot)
        do {
            try FileManager.default.createDirectory(
                at: runsDir,
                withIntermediateDirectories: true
            )
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to create PEX runs directory: \(error.localizedDescription)"
            )
        }

        let configURL = try pexConfigurationURL(inProjectAt: projectRoot)
        let config: PEXProjectConfig

        if FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) {
            config = try loadPEXProjectConfig(forProjectAt: projectRoot)
        } else {
            config = PEXProjectConfig()
            try savePEXProjectConfig(config, forProjectAt: projectRoot)
        }

        try writePEXTOML(config: config, forProjectAt: projectRoot)
        try writeDefaultTechTemplateIfNeeded(forProjectAt: projectRoot, config: config)
    }

    func savePEXProjectConfig(_ config: PEXProjectConfig, forProjectAt projectRoot: URL) throws {
        let url = try pexConfigurationURL(inProjectAt: projectRoot)
        try writeJSON(config, to: url, forProjectAt: projectRoot)
        try writePEXTOML(config: config, forProjectAt: projectRoot)
    }

    func loadPEXProjectConfig(forProjectAt projectRoot: URL) throws -> PEXProjectConfig {
        let url = try pexConfigurationURL(inProjectAt: projectRoot)
        return try readJSON(PEXProjectConfig.self, from: url)
    }

    /// Points the PEX and tapeout flows at `topCell` by name. OASIS carries
    /// no inherent top cell, so this name must track the exported layout's
    /// actual top cell. Self-bootstraps a default config when the project has
    /// none yet, and is a no-op when the name already matches.
    func updatePEXTopCell(_ topCell: String, forProjectAt projectRoot: URL) throws {
        let configURL = try pexConfigurationURL(inProjectAt: projectRoot)
        var config: PEXProjectConfig
        if FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) {
            config = try loadPEXProjectConfig(forProjectAt: projectRoot)
        } else {
            config = PEXProjectConfig()
        }
        guard config.topCell != topCell else { return }
        config.topCell = topCell
        try savePEXProjectConfig(config, forProjectAt: projectRoot)
    }

    func pexTOMLURL(inProjectAt projectRoot: URL) -> URL {
        projectRoot.appending(path: Self.pexTOMLFileName)
    }

    func pexWorkspaceDirectory(inProjectAt projectRoot: URL) -> URL {
        pexRunsDirectoryURL(inProjectAt: projectRoot)
    }

    // MARK: - Standard Format I/O

    /// Saves a SPICE netlist string to the project root.
    func saveNetlist(_ spice: String, named fileName: String, inProjectAt projectRoot: URL) throws {
        let url = try projectRootFileURL(named: fileName, inProjectAt: projectRoot)
        try writeText(spice, to: url)
    }

    func topNetlistURL(inProjectAt projectRoot: URL) -> URL {
        projectRoot.appending(path: "top.cir")
    }

    /// Saves a SPICE netlist string to a project-relative path.
    func saveNetlist(
        _ spice: String,
        toProjectRelativePath relativePath: String,
        inProjectAt projectRoot: URL
    ) throws {
        let url = try url(forProjectRelativePath: relativePath, inProjectAt: projectRoot)
        let parent = url.deletingLastPathComponent()
        try ensureDirectory(at: parent)
        try writeText(spice, to: url)
    }

    /// Saves a layout document in OASIS format to the project root.
    func saveLayout(
        document: LayoutDocument,
        tech: LayoutTechDatabase,
        to fileName: String,
        inProjectAt projectRoot: URL
    ) throws {
        let url = try projectRootFileURL(named: fileName, inProjectAt: projectRoot)
        let converter = MaskDataFormatConverter(tech: tech)
        do {
            try converter.exportDocument(document, to: url, format: .oasis)
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to save layout: \(error.localizedDescription)"
            )
        }
    }

    /// Saves a layout document in OASIS format to a project-relative path.
    func saveLayout(
        document: LayoutDocument,
        tech: LayoutTechDatabase,
        toProjectRelativePath relativePath: String,
        inProjectAt projectRoot: URL
    ) throws {
        let url = try url(forProjectRelativePath: relativePath, inProjectAt: projectRoot)
        let parent = url.deletingLastPathComponent()
        try ensureDirectory(at: parent)
        let converter = MaskDataFormatConverter(tech: tech)
        do {
            try converter.exportDocument(document, to: url, format: .oasis)
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to save layout: \(error.localizedDescription)"
            )
        }
    }

    /// Removes a file at the project root. Used to prune interchange
    /// artifacts such as `top.oas` when their source layout is cleared.
    /// Removing a file that is not present is a no-op.
    func removeProjectRootFile(named fileName: String, forProjectAt projectRoot: URL) throws {
        let url = try projectRootFileURL(named: fileName, inProjectAt: projectRoot)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) else {
            return
        }
        guard !isDirectory.boolValue else {
            throw StudioError.projectSaveFailed(
                "Refusing to remove directory '\(fileName)' through the project root file API."
            )
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to remove '\(fileName)': \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Per-Cell Layout Editor State

    /// Saves a cell's native layout document — the full-fidelity editor
    /// state. Interchange formats like OASIS carry mask geometry only and
    /// drop element IDs, nets, and pins, which the design-unit binding and
    /// live verification depend on.
    func saveCellLayoutDocument(
        _ document: LayoutDocument,
        cellName: String,
        forProjectAt projectRoot: URL
    ) throws {
        let url = try cellLayoutDocumentURL(cellName: cellName, inProjectAt: projectRoot)
        try ensureDirectory(at: url.deletingLastPathComponent())
        try writeJSON(document, to: url, forProjectAt: projectRoot)
    }

    /// Returns `true` when the cell has a persisted layout document.
    func hasCellLayoutDocument(cellName: String, forProjectAt projectRoot: URL) -> Bool {
        do {
            let url = try cellLayoutDocumentURL(cellName: cellName, inProjectAt: projectRoot)
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        } catch {
            // An invalid cell name cannot have been persisted.
            return false
        }
    }

    func loadCellLayoutDocument(cellName: String, forProjectAt projectRoot: URL) throws -> LayoutDocument {
        let url = try cellLayoutDocumentURL(cellName: cellName, inProjectAt: projectRoot)
        return try readJSON(LayoutDocument.self, from: url)
    }

    /// Removes a cell's persisted layout artifacts (document + design
    /// unit). Called when the cell's layout is emptied so stale artifacts
    /// cannot resurface on next open.
    func removeCellLayoutArtifacts(cellName: String, forProjectAt projectRoot: URL) throws {
        for fileName in [Self.cellLayoutFileName, Self.cellDesignUnitFileName] {
            let url = try cellFileURL(fileName, cellName: cellName, inProjectAt: projectRoot)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                continue
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw StudioError.projectSaveFailed(
                    "Failed to remove \(fileName) of cell '\(cellName)': \(error.localizedDescription)"
                )
            }
        }
    }

    func saveLayoutTech(_ tech: LayoutTechDatabase, forProjectAt projectRoot: URL) throws {
        let url = try configurationFileURL(named: Self.layoutTechFileName, inProjectAt: projectRoot)
        try writeJSON(tech, to: url, forProjectAt: projectRoot)
    }

    func loadLayoutTech(forProjectAt projectRoot: URL) throws -> LayoutTechDatabase {
        let url = try configurationFileURL(named: Self.layoutTechFileName, inProjectAt: projectRoot)
        return try readJSON(LayoutTechDatabase.self, from: url)
    }

    func saveCellDesignUnit(_ unit: DesignUnit, cellName: String, forProjectAt projectRoot: URL) throws {
        let url = try cellFileURL(Self.cellDesignUnitFileName, cellName: cellName, inProjectAt: projectRoot)
        try ensureDirectory(at: url.deletingLastPathComponent())
        try writeJSON(unit, to: url, forProjectAt: projectRoot)
    }

    /// Returns nil when no design unit has been persisted for the cell. A
    /// present but unreadable file throws so corruption surfaces instead of
    /// silently degrading to an unbound layout.
    func loadCellDesignUnitIfPresent(cellName: String, forProjectAt projectRoot: URL) throws -> DesignUnit? {
        let url = try cellFileURL(Self.cellDesignUnitFileName, cellName: cellName, inProjectAt: projectRoot)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        return try readJSON(DesignUnit.self, from: url)
    }

    /// Removes a cell's persisted design-unit binding. Called when the
    /// layout is saved without one so a stale binding cannot resurface.
    func removeCellDesignUnit(cellName: String, forProjectAt projectRoot: URL) throws {
        let url = try cellFileURL(Self.cellDesignUnitFileName, cellName: cellName, inProjectAt: projectRoot)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to remove design unit of cell '\(cellName)': \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Private

    /// Resolves `cells/<cellName>/`, validating the name first — cell names
    /// are SPICE identifiers, which also guarantees a safe path component.
    private func cellDirectoryURL(cellName: String, inProjectAt projectRoot: URL) throws -> URL {
        guard CellInterface.isValidSPICEName(cellName) else {
            throw CellLibraryError.invalidCellName(cellName)
        }
        return cellsDirectoryURL(inProjectAt: projectRoot).appending(path: cellName)
    }

    private func cellFileURL(
        _ fileName: String,
        cellName: String,
        inProjectAt projectRoot: URL
    ) throws -> URL {
        try cellDirectoryURL(cellName: cellName, inProjectAt: projectRoot).appending(path: fileName)
    }

    private func configurationFileURL(named fileName: String, inProjectAt projectRoot: URL) throws -> URL {
        try XcircuiteWorkspaceLayout(projectRoot: projectRoot).configurationURL(named: fileName)
    }

    private func pexConfigurationURL(inProjectAt projectRoot: URL) throws -> URL {
        try configurationFileURL(named: Self.pexConfigFileName, inProjectAt: projectRoot)
    }

    private func pexDirectoryURL(inProjectAt projectRoot: URL) -> URL {
        XcircuiteWorkspaceLayout(projectRoot: projectRoot)
            .workspaceURL
            .appending(path: Self.pexDirectoryName)
    }

    private func pexRunsDirectoryURL(inProjectAt projectRoot: URL) -> URL {
        pexDirectoryURL(inProjectAt: projectRoot).appending(path: Self.pexRunsDirectoryName)
    }

    private func ensureConfigurationDirectory(forProjectAt projectRoot: URL) throws {
        try ensureDirectory(at: XcircuiteWorkspaceLayout(projectRoot: projectRoot).workspaceURL)
    }

    private func ensureXcircuiteProjectManifest(
        forProjectAt projectRoot: URL,
        topDesignName: String?
    ) async throws {
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        try await workspaceStore.createWorkspace()
        if let topDesignName {
            try await workspaceStore.updateTopDesignName(topDesignName)
        }
    }

    private func writePEXTOML(config: PEXProjectConfig, forProjectAt projectRoot: URL) throws {
        let tomlURL = pexTOMLURL(inProjectAt: projectRoot)
        let contents = renderPEXTOML(config: config)
        try writeText(contents, to: tomlURL)
    }

    private func writeDefaultTechTemplateIfNeeded(
        forProjectAt projectRoot: URL,
        config: PEXProjectConfig
    ) throws {
        let techURL = try url(forProjectRelativePath: config.inputs.technology, inProjectAt: projectRoot)
        let techPath = techURL.path(percentEncoded: false)
        guard !FileManager.default.fileExists(atPath: techPath) else {
            return
        }

        let parent = techURL.deletingLastPathComponent()
        try ensureDirectory(at: parent)

        let template = """
        {
          "version": 1,
          "name": "generic-tech",
          "units": {
            "length": "um"
          },
          "layers": [],
          "vias": []
        }
        """

        try writeText(template, to: techURL)
    }

    private func url(forProjectRelativePath rawPath: String, inProjectAt projectRoot: URL) throws -> URL {
        try XcircuiteWorkspaceLayout(projectRoot: projectRoot).url(forProjectRelativePath: rawPath)
    }

    private func projectRootFileURL(named fileName: String, inProjectAt projectRoot: URL) throws -> URL {
        guard isSafeProjectRootFileName(fileName) else {
            throw StudioError.projectSaveFailed(
                "Unsafe project root file name '\(fileName)'. Expected a single non-reserved file name."
            )
        }
        return try url(forProjectRelativePath: fileName, inProjectAt: projectRoot)
    }

    private func isSafeProjectRootFileName(_ fileName: String) -> Bool {
        guard !fileName.isEmpty, fileName != ".", fileName != ".." else {
            return false
        }
        guard !fileName.hasPrefix("/"),
              !fileName.hasPrefix("~"),
              !fileName.contains("/"),
              !fileName.contains("\\") else {
            return false
        }
        guard fileName != XcircuiteWorkspaceLayout.directoryName,
              fileName != Self.cellsDirectoryName else {
            return false
        }
        return true
    }

    private func renderPEXTOML(config: PEXProjectConfig) -> String {
        var lines: [String] = []

        lines.append("[project]")
        lines.append("name = \"circuit-studio\"")

        lines.append("")
        lines.append("[inputs]")
        lines.append("layout = \"\(escapeTOML(config.inputs.layout))\"")
        lines.append("netlist = \"\(escapeTOML(config.inputs.netlist))\"")
        lines.append("top_cell = \"\(escapeTOML(config.topCell))\"")

        lines.append("")
        lines.append("[technology]")
        lines.append("path = \"\(escapeTOML(config.inputs.technology))\"")

        lines.append("")
        lines.append("[runtime]")
        lines.append("backend = \"\(escapeTOML(config.normalizedBackendID ?? ""))\"")
        lines.append("max_jobs = \(max(1, config.options.maxParallelJobs))")
        lines.append("include_coupling = \(config.options.includeCouplingCaps)")

        if let minCapacitance = config.options.minCapacitanceF {
            lines.append("min_cap_f = \(minCapacitance)")
        }
        if let minResistance = config.options.minResistanceOhm {
            lines.append("min_res_ohm = \(minResistance)")
        }
        lines.append("strict = \(config.options.strictValidation)")

        lines.append("")
        lines.append("[output]")
        lines.append("workspace = \"\(escapeTOML(config.output.workspace))\"")

        for corner in config.normalizedCorners {
            lines.append("")
            lines.append("[[corners]]")
            lines.append("id = \"\(escapeTOML(corner))\"")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func escapeTOML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL, forProjectAt projectRoot: URL) throws {
        _ = try projectRelativePath(for: url, inProjectAt: projectRoot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(value).write(to: url, options: [.atomic])
        } catch {
            throw StudioError.projectSaveFailed(error.localizedDescription)
        }
    }

    private func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: url))
        } catch {
            throw StudioError.projectLoadFailed(error.localizedDescription)
        }
    }

    private func writeText(_ text: String, to url: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw StudioError.projectSaveFailed("Text is not valid UTF-8.")
        }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw StudioError.projectSaveFailed(error.localizedDescription)
        }
    }

    private func ensureDirectory(at url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw StudioError.projectSaveFailed(error.localizedDescription)
        }
    }

    private func projectRelativePath(for url: URL, inProjectAt projectRoot: URL) throws -> String {
        let rootPath = projectRoot.standardizedFileURL.path(percentEncoded: false)
        let filePath = url.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else {
            throw StudioError.projectSaveFailed("Path is outside the project root.")
        }
        let relativePath = String(filePath.dropFirst(prefix.count))
        try XcircuiteWorkspaceLayout.validateProjectRelativePath(relativePath)
        return relativePath
    }
}
