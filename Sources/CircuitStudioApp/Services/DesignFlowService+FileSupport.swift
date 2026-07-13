import Foundation
import CircuitStudioCore
import DesignFlowKernel

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

    func designEditArtifactDirectory(for command: DesignFlowCommand, outputURL: URL) throws -> URL {
        let root = command.projectRootPath.map { URL(filePath: $0) }
            ?? outputURL.deletingLastPathComponent()
        let runID = try validatedRunID(command.runID)
        return root
            .appending(path: ".xcircuite")
            .appending(path: "design-edits")
            .appending(path: runID)
    }

    func layoutEditArtifactDirectory(for command: DesignFlowCommand, outputURL: URL) throws -> URL {
        let root = command.projectRootPath.map { URL(filePath: $0) }
            ?? outputURL.deletingLastPathComponent()
        let runID = try validatedRunID(command.runID)
        return root
            .appending(path: ".xcircuite")
            .appending(path: "layout-edits")
            .appending(path: runID)
    }

    func layoutTrustArtifactDirectory(for command: DesignFlowCommand) throws -> URL {
        try runArtifactDirectory(for: command, fallbackRootName: "layout-trust-runs")
            .appending(path: "layout")
    }

    func verificationArtifactDirectory(for command: DesignFlowCommand) throws -> URL {
        try runArtifactDirectory(for: command, fallbackRootName: "verification-runs")
    }

    func runArtifactDirectory(for command: DesignFlowCommand, fallbackRootName: String) throws -> URL {
        let root = command.projectRootPath.map { URL(filePath: $0) }
            ?? URL(filePath: FileManager.default.currentDirectoryPath)
                .appending(path: fallbackRootName)
        let runID = try validatedRunID(command.runID)
        return root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: runID)
    }

    func actionLogPath(projectRoot: URL, runID: String) throws -> String {
        try HeadlessRoundTripService.validateRunID(runID)
        return projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: runID)
            .appending(path: "actions.jsonl")
            .path(percentEncoded: false)
    }

    func absolutePath(
        for reference: XcircuiteFileReference,
        projectRoot: URL
    ) throws -> String {
        try projectContainedURL(forRelativePath: reference.path, projectRoot: projectRoot)
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

    private func validatedRunID(_ runID: String?) throws -> String {
        let value = runID ?? Self.timestamp()
        try HeadlessRoundTripService.validateRunID(value)
        return value
    }

    private func projectContainedURL(forRelativePath path: String, projectRoot: URL) throws -> URL {
        try validateProjectRelativeArtifactPath(path)
        let root = projectRoot.standardizedFileURL
        let url = root.appending(path: path).standardizedFileURL
        let rootPath = root.path(percentEncoded: false)
        let resolvedPath = url.path(percentEncoded: false)
        guard resolvedPath == rootPath || resolvedPath.hasPrefix(rootPath + "/") else {
            throw StudioError.projectLoadFailed("Artifact reference escapes project root: \(path)")
        }
        return url
    }

    private func validateProjectRelativeArtifactPath(_ path: String) throws {
        guard !path.isEmpty else {
            throw StudioError.projectLoadFailed("Artifact reference path is empty.")
        }
        guard !path.hasPrefix("/") else {
            throw StudioError.projectLoadFailed("Artifact reference must be project-relative: \(path)")
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let isSafe = components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
        guard isSafe else {
            throw StudioError.projectLoadFailed("Artifact reference contains an unsafe path component: \(path)")
        }
    }
}
