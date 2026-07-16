import Foundation
import DesignFlowKernel
import Xcircuite

public enum RoundTripRunDirectory {
    public static let manifestFileName = "round-trip-manifest.json"

    public static func runsDirectory(projectRoot: URL) -> URL {
        projectRoot
            .appending(path: XcircuiteWorkspaceLayout.directoryName)
            .appending(path: "runs")
    }

    public static func runDirectory(projectRoot: URL, runID: String) throws -> URL {
        try XcircuiteWorkspaceLayout(projectRoot: projectRoot).runDirectoryURL(for: runID)
    }

    public static func manifestURL(projectRoot: URL, runID: String) throws -> URL {
        try runDirectory(projectRoot: projectRoot, runID: runID)
            .appending(path: manifestFileName)
    }
}
