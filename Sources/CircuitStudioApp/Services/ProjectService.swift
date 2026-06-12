import Foundation
import CircuitStudioCore
import LayoutCore
import LayoutTech
import LayoutIO
import XcircuitePackage

/// Manages `.xcircuite/` project directory for persistent workspace state.
public struct ProjectService: Sendable {

    private static let pexConfigFileName = "pex.json"
    private static let pexDirectoryName = "pex"
    private static let pexRunsDirectoryName = "runs"
    private static let pexTOMLFileName = "pex.toml"

    private let packageStore: XcircuitePackageStore

    public init(packageStore: XcircuitePackageStore = XcircuitePackageStore()) {
        self.packageStore = packageStore
    }

    // MARK: - Project Lifecycle

    /// Creates a new project at the given directory, initializing `.xcircuite/`.
    func createProject(at directory: URL) throws {
        try packageStore.createPackage(at: directory)

        // Write default workspace config
        let defaultConfig = WorkspaceConfig()
        try saveWorkspaceConfig(defaultConfig, forProjectAt: directory)

        // Bootstrap PEX files so the project is immediately runnable by `pexengine`.
        try ensurePEXProjectFiles(forProjectAt: directory)
    }

    /// Seeds a project with template content (sample netlist, schematic
    /// placement and simulation config) so it opens as a working example.
    func installTemplate(_ content: ProjectTemplateContent, forProjectAt projectRoot: URL) throws {
        try saveNetlist(content.netlist, named: content.netlistFileName, inProjectAt: projectRoot)
        try saveSchematicPlacement(content.schematicPlacement, forProjectAt: projectRoot)
        try saveSimulationConfig(content.simulationConfig, forProjectAt: projectRoot)
    }

    /// Returns `true` if the directory contains a `.xcircuite/` folder.
    func isProject(_ directory: URL) -> Bool {
        packageStore.isPackage(at: directory)
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

    // MARK: - Schematic Placement

    func saveSchematicPlacement(_ placement: SchematicPlacement, forProjectAt projectRoot: URL) throws {
        let url = try configurationFileURL(named: "schematic-placement.json", inProjectAt: projectRoot)
        try writeJSON(placement, to: url, forProjectAt: projectRoot)
    }

    func loadSchematicPlacement(forProjectAt projectRoot: URL) throws -> SchematicPlacement {
        let url = try configurationFileURL(named: "schematic-placement.json", inProjectAt: projectRoot)
        return try readJSON(SchematicPlacement.self, from: url)
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

    func pexTOMLURL(inProjectAt projectRoot: URL) -> URL {
        projectRoot.appending(path: Self.pexTOMLFileName)
    }

    func pexWorkspaceDirectory(inProjectAt projectRoot: URL) -> URL {
        pexRunsDirectoryURL(inProjectAt: projectRoot)
    }

    // MARK: - Standard Format I/O

    /// Saves a SPICE netlist string to the project root.
    func saveNetlist(_ spice: String, named fileName: String, inProjectAt projectRoot: URL) throws {
        let url = projectRoot.appending(path: fileName)
        try packageStore.writeText(spice, to: url)
    }

    /// Saves a SPICE netlist string to a project-relative path.
    func saveNetlist(
        _ spice: String,
        toProjectRelativePath relativePath: String,
        inProjectAt projectRoot: URL
    ) throws {
        let url = try url(forProjectRelativePath: relativePath, inProjectAt: projectRoot)
        let parent = url.deletingLastPathComponent()
        try packageStore.ensureDirectory(at: parent)
        try packageStore.writeText(spice, to: url)
    }

    /// Saves a layout document in OASIS format to the project root.
    func saveLayout(
        document: LayoutDocument,
        tech: LayoutTechDatabase,
        to fileName: String,
        inProjectAt projectRoot: URL
    ) throws {
        let url = projectRoot.appending(path: fileName)
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
        try packageStore.ensureDirectory(at: parent)
        let converter = MaskDataFormatConverter(tech: tech)
        do {
            try converter.exportDocument(document, to: url, format: .oasis)
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to save layout: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Private

    private func configurationFileURL(named fileName: String, inProjectAt projectRoot: URL) throws -> URL {
        try packageStore.configurationURL(named: fileName, inProjectAt: projectRoot)
    }

    private func pexConfigurationURL(inProjectAt projectRoot: URL) throws -> URL {
        try configurationFileURL(named: Self.pexConfigFileName, inProjectAt: projectRoot)
    }

    private func pexDirectoryURL(inProjectAt projectRoot: URL) -> URL {
        packageStore
            .packageURL(forProjectAt: projectRoot)
            .appending(path: Self.pexDirectoryName)
    }

    private func pexRunsDirectoryURL(inProjectAt projectRoot: URL) -> URL {
        pexDirectoryURL(inProjectAt: projectRoot).appending(path: Self.pexRunsDirectoryName)
    }

    private func ensureConfigurationDirectory(forProjectAt projectRoot: URL) throws {
        try packageStore.ensurePackageDirectory(forProjectAt: projectRoot)
    }

    private func writePEXTOML(config: PEXProjectConfig, forProjectAt projectRoot: URL) throws {
        let tomlURL = pexTOMLURL(inProjectAt: projectRoot)
        let contents = renderPEXTOML(config: config)
        try packageStore.writeText(contents, to: tomlURL)
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
        try packageStore.ensureDirectory(at: parent)

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

        try packageStore.writeText(template, to: techURL)
    }

    private func url(forProjectRelativePath rawPath: String, inProjectAt projectRoot: URL) throws -> URL {
        try packageStore.url(forProjectRelativePath: rawPath, inProjectAt: projectRoot)
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
        lines.append("backend = \"\(escapeTOML(config.backendID))\"")
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
        try packageStore.writeJSON(value, to: url, forProjectAt: projectRoot)
    }

    private func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try packageStore.readJSON(type, from: url)
    }
}
