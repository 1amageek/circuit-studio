import Foundation
import XcircuitePackage

public enum RoundTripRunDirectory {
    public static let manifestFileName = "round-trip-manifest.json"
    private static let canonicalRunsDirectoryName = "runs"
    private static let legacyRunsDirectoryName = "flow-runs"

    public static func ensureRunDirectory(
        projectRoot: URL,
        runID: String,
        store: XcircuitePackageStore = XcircuitePackageStore()
    ) throws -> URL {
        try store.createPackage(at: projectRoot)
        return try store.ensureRunDirectory(for: runID, inProjectAt: projectRoot)
    }

    public static func runDirectory(projectRoot: URL, runID: String) throws -> URL {
        try XcircuitePackage(projectRoot: projectRoot).runDirectoryURL(for: runID)
    }

    public static func manifestURL(projectRoot: URL, runID: String) throws -> URL {
        try runDirectory(projectRoot: projectRoot, runID: runID)
            .appending(path: manifestFileName)
    }

    public static func existingManifestURL(projectRoot: URL, runID: String) throws -> URL {
        let canonicalURL = try manifestURL(projectRoot: projectRoot, runID: runID)
        if fileExists(canonicalURL) {
            return canonicalURL
        }

        let legacyURL = legacyRunDirectory(projectRoot: projectRoot, runID: runID)
            .appending(path: manifestFileName)
        if fileExists(legacyURL) {
            return legacyURL
        }

        return canonicalURL
    }

    public static func manifestURLCandidates(projectRoot: URL, runID: String) throws -> [URL] {
        let canonicalURL = try manifestURL(projectRoot: projectRoot, runID: runID)
        let legacyURL = legacyRunDirectory(projectRoot: projectRoot, runID: runID)
            .appending(path: manifestFileName)
        guard canonicalURL.standardizedFileURL != legacyURL.standardizedFileURL else {
            return [canonicalURL]
        }
        return [canonicalURL, legacyURL]
    }

    public static func existingRunsDirectories(projectRoot: URL) -> [URL] {
        let candidates = [
            projectRoot
                .appending(path: XcircuitePackage.directoryName)
                .appending(path: canonicalRunsDirectoryName),
            projectRoot
                .appending(path: XcircuitePackage.directoryName)
                .appending(path: legacyRunsDirectoryName),
        ]
        return candidates.filter { directoryExists($0) }
    }

    private static func legacyRunDirectory(projectRoot: URL, runID: String) -> URL {
        projectRoot
            .appending(path: XcircuitePackage.directoryName)
            .appending(path: legacyRunsDirectoryName)
            .appending(path: runID)
    }

    private static func fileExists(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }
}
