import Foundation
import CircuitStudioCore
import XcircuitePackage

extension DesignFlowService {
    func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    func writeActionLog(_ actions: [DesignFlowDesignEditAction], to url: URL) throws {
        try writeJSONLines(actions, to: url)
    }

    func writeLayoutActionLog(_ actions: [DesignFlowLayoutEditAction], to url: URL) throws {
        try writeJSONLines(actions, to: url)
    }

    func writeJSONLines<T: Encodable>(_ values: [T], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = try values.map { value -> String in
            let data = try encoder.encode(value)
            guard let line = String(data: data, encoding: .utf8) else {
                throw StudioError.projectSaveFailed("Failed to encode action log.")
            }
            return line
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func designEditArtifactDirectory(for command: DesignFlowCommand, outputURL: URL) -> URL {
        let root = command.projectRootPath.map { URL(filePath: $0) }
            ?? outputURL.deletingLastPathComponent()
        let runID = command.runID ?? Self.timestamp()
        return root
            .appending(path: ".xcircuite")
            .appending(path: "design-edits")
            .appending(path: runID)
    }

    func layoutEditArtifactDirectory(for command: DesignFlowCommand, outputURL: URL) -> URL {
        let root = command.projectRootPath.map { URL(filePath: $0) }
            ?? outputURL.deletingLastPathComponent()
        let runID = command.runID ?? Self.timestamp()
        return root
            .appending(path: ".xcircuite")
            .appending(path: "layout-edits")
            .appending(path: runID)
    }

    func layoutTrustArtifactDirectory(for command: DesignFlowCommand) -> URL {
        runArtifactDirectory(for: command, fallbackRootName: "layout-trust-runs")
            .appending(path: "layout")
    }

    func verificationArtifactDirectory(for command: DesignFlowCommand) -> URL {
        runArtifactDirectory(for: command, fallbackRootName: "verification-runs")
    }

    func runArtifactDirectory(for command: DesignFlowCommand, fallbackRootName: String) -> URL {
        let root = command.projectRootPath.map { URL(filePath: $0) }
            ?? URL(filePath: FileManager.default.currentDirectoryPath)
                .appending(path: fallbackRootName)
        let runID = command.runID ?? Self.timestamp()
        return root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: runID)
    }

    func actionLogPath(projectRoot: URL, runID: String) -> String {
        projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: runID)
            .appending(path: "actions.jsonl")
            .path(percentEncoded: false)
    }

    func absolutePath(
        for reference: XcircuiteFileReference,
        projectRoot: URL
    ) -> String {
        projectRoot
            .appending(path: reference.path)
            .path(percentEncoded: false)
    }

    func defaultCommandProjectRoot(fixtureName: String) -> String {
        URL(filePath: FileManager.default.currentDirectoryPath)
            .appending(path: "round-trip-runs")
            .appending(path: fixtureName)
            .path(percentEncoded: false)
    }

    static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ".", with: "")
    }
}
