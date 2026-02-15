import Foundation
import CircuitStudioCore
import LayoutCore
import LayoutTech
import LayoutIO

/// Manages `.xcircuite/` project directory for persistent workspace state.
public struct ProjectService: Sendable {

    private static let configDir = ".xcircuite"

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

    // MARK: - Private

    private func configFileURL(projectRoot: URL, fileName: String) -> URL {
        let configDir = projectRoot.appending(path: Self.configDir)
        return configDir.appending(path: fileName)
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
