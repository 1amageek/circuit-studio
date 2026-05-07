import Foundation
import CircuitStudioCore
import LayoutCore
import LayoutTech
import LayoutIO

/// Manages `.xcircuite/` project directory for persistent workspace state.
public struct ProjectService: Sendable {

    private static let configDir = ".xcircuite"
    private static let pexConfigFileName = "pex.json"
    private static let pexDirectoryName = "pex"
    private static let pexRunsDirectoryName = "runs"
    private static let pexTOMLFileName = "pex.toml"

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder = JSONDecoder()

    public init() {}

    // MARK: - Project Lifecycle

    /// Creates a new project at the given directory, initializing `.xcircuite/`.
    func createProject(at directory: URL) throws {
        let configURL = directory.appending(path: Self.configDir)
        do {
            try FileManager.default.createDirectory(
                at: configURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to create project directory: \(error.localizedDescription)"
            )
        }

        // Write default workspace config
        let defaultConfig = WorkspaceConfig()
        try saveWorkspaceConfig(defaultConfig, projectRoot: directory)

        // Bootstrap PEX files so the project is immediately runnable by `pexengine`.
        try ensurePEXProjectFiles(projectRoot: directory)
    }

    /// Returns `true` if the directory contains a `.xcircuite/` folder.
    func isProject(_ directory: URL) -> Bool {
        var isDir: ObjCBool = false
        let configURL = directory.appending(path: Self.configDir)
        return FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false), isDirectory: &isDir)
            && isDir.boolValue
    }

    // MARK: - Workspace Config

    func saveWorkspaceConfig(_ config: WorkspaceConfig, projectRoot: URL) throws {
        let url = configFileURL(projectRoot: projectRoot, fileName: "workspace.json")
        try writeJSON(config, to: url, projectRoot: projectRoot)
    }

    func loadWorkspaceConfig(projectRoot: URL) throws -> WorkspaceConfig {
        let url = configFileURL(projectRoot: projectRoot, fileName: "workspace.json")
        return try readJSON(WorkspaceConfig.self, from: url)
    }

    // MARK: - Schematic Placement

    func saveSchematicPlacement(_ placement: SchematicPlacement, projectRoot: URL) throws {
        let url = configFileURL(projectRoot: projectRoot, fileName: "schematic-placement.json")
        try writeJSON(placement, to: url, projectRoot: projectRoot)
    }

    func loadSchematicPlacement(projectRoot: URL) throws -> SchematicPlacement {
        let url = configFileURL(projectRoot: projectRoot, fileName: "schematic-placement.json")
        return try readJSON(SchematicPlacement.self, from: url)
    }

    // MARK: - Simulation Config

    func saveSimulationConfig(_ config: SimulationConfig, projectRoot: URL) throws {
        let url = configFileURL(projectRoot: projectRoot, fileName: "simulation.json")
        try writeJSON(config, to: url, projectRoot: projectRoot)
    }

    func loadSimulationConfig(projectRoot: URL) throws -> SimulationConfig {
        let url = configFileURL(projectRoot: projectRoot, fileName: "simulation.json")
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
    func ensurePEXProjectFiles(projectRoot: URL) throws {
        try ensureConfigDir(projectRoot: projectRoot)

        let pexDir = pexDirectoryURL(projectRoot: projectRoot)
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

        let runsDir = pexRunsDirectoryURL(projectRoot: projectRoot)
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

        let configURL = pexConfigFileURL(projectRoot: projectRoot)
        let config: PEXProjectConfig

        if FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) {
            config = try loadPEXProjectConfig(projectRoot: projectRoot)
        } else {
            config = PEXProjectConfig()
            try savePEXProjectConfig(config, projectRoot: projectRoot)
        }

        try writePEXTOML(config: config, projectRoot: projectRoot)
        try writeDefaultTechTemplateIfNeeded(projectRoot: projectRoot, config: config)
    }

    func savePEXProjectConfig(_ config: PEXProjectConfig, projectRoot: URL) throws {
        let url = pexConfigFileURL(projectRoot: projectRoot)
        try writeJSON(config, to: url, projectRoot: projectRoot)
        try writePEXTOML(config: config, projectRoot: projectRoot)
    }

    func loadPEXProjectConfig(projectRoot: URL) throws -> PEXProjectConfig {
        let url = pexConfigFileURL(projectRoot: projectRoot)
        return try readJSON(PEXProjectConfig.self, from: url)
    }

    func pexConfigPath(projectRoot: URL) -> URL {
        projectRoot.appending(path: Self.pexTOMLFileName)
    }

    func pexWorkspaceDirectory(projectRoot: URL) -> URL {
        pexRunsDirectoryURL(projectRoot: projectRoot)
    }

    // MARK: - Standard Format I/O

    /// Saves a SPICE netlist string to the project root.
    func saveNetlist(_ spice: String, fileName: String, projectRoot: URL) throws {
        let url = projectRoot.appending(path: fileName)
        do {
            try spice.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to save netlist: \(error.localizedDescription)"
            )
        }
    }

    /// Saves a SPICE netlist string to a project-relative or absolute path.
    func saveNetlist(_ spice: String, relativePath: String, projectRoot: URL) throws {
        let url = resolveProjectPath(relativePath, projectRoot: projectRoot)
        let parent = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to create netlist directory: \(error.localizedDescription)"
            )
        }
        do {
            try spice.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to save netlist: \(error.localizedDescription)"
            )
        }
    }

    /// Saves a layout document in OASIS format to the project root.
    func saveLayout(
        document: LayoutDocument,
        tech: LayoutTechDatabase,
        to fileName: String,
        projectRoot: URL
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

    /// Saves a layout document in OASIS format to a project-relative or absolute path.
    func saveLayout(
        document: LayoutDocument,
        tech: LayoutTechDatabase,
        relativePath: String,
        projectRoot: URL
    ) throws {
        let url = resolveProjectPath(relativePath, projectRoot: projectRoot)
        let parent = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to create layout directory: \(error.localizedDescription)"
            )
        }
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

    private func configFileURL(projectRoot: URL, fileName: String) -> URL {
        let configDir = projectRoot.appending(path: Self.configDir)
        return configDir.appending(path: fileName)
    }

    private func pexConfigFileURL(projectRoot: URL) -> URL {
        configFileURL(projectRoot: projectRoot, fileName: Self.pexConfigFileName)
    }

    private func pexDirectoryURL(projectRoot: URL) -> URL {
        let configDir = projectRoot.appending(path: Self.configDir)
        return configDir.appending(path: Self.pexDirectoryName)
    }

    private func pexRunsDirectoryURL(projectRoot: URL) -> URL {
        pexDirectoryURL(projectRoot: projectRoot).appending(path: Self.pexRunsDirectoryName)
    }

    private func ensureConfigDir(projectRoot: URL) throws {
        let configDir = projectRoot.appending(path: Self.configDir)
        if !FileManager.default.fileExists(atPath: configDir.path(percentEncoded: false)) {
            do {
                try FileManager.default.createDirectory(
                    at: configDir,
                    withIntermediateDirectories: true
                )
            } catch {
                throw StudioError.projectSaveFailed(
                    "Failed to create .xcircuite directory: \(error.localizedDescription)"
                )
            }
        }
    }

    private func writePEXTOML(config: PEXProjectConfig, projectRoot: URL) throws {
        let tomlURL = projectRoot.appending(path: Self.pexTOMLFileName)
        let contents = renderPEXTOML(config: config)
        do {
            try contents.write(to: tomlURL, atomically: true, encoding: .utf8)
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to write \(Self.pexTOMLFileName): \(error.localizedDescription)"
            )
        }
    }

    private func writeDefaultTechTemplateIfNeeded(projectRoot: URL, config: PEXProjectConfig) throws {
        let techURL = resolveProjectPath(config.inputs.technology, projectRoot: projectRoot)
        let techPath = techURL.path(percentEncoded: false)
        guard !FileManager.default.fileExists(atPath: techPath) else {
            return
        }

        let parent = techURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to create tech directory: \(error.localizedDescription)"
            )
        }

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

        do {
            try template.write(to: techURL, atomically: true, encoding: .utf8)
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to write default technology template: \(error.localizedDescription)"
            )
        }
    }

    private func resolveProjectPath(_ rawPath: String, projectRoot: URL) -> URL {
        let expanded = NSString(string: rawPath).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(filePath: expanded)
        }
        return projectRoot.appending(path: expanded)
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

    private func writeJSON<T: Encodable>(_ value: T, to url: URL, projectRoot: URL) throws {
        try ensureConfigDir(projectRoot: projectRoot)
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to encode: \(error.localizedDescription)"
            )
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to write \(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    private func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StudioError.projectLoadFailed(
                "Failed to read \(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw StudioError.projectLoadFailed(
                "Failed to decode \(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }
}
