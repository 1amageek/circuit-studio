import Foundation

public struct PEXExtractionRequest: Sendable, Hashable {
    public let configURL: URL
    public let projectDirectory: URL?
    public let workspaceDirectory: URL?
    public let cornerID: String
    public let executablePath: String?

    public init(
        configURL: URL,
        projectDirectory: URL? = nil,
        workspaceDirectory: URL? = nil,
        cornerID: String = "tt_25c_1v0",
        executablePath: String? = nil
    ) {
        self.configURL = configURL
        self.projectDirectory = projectDirectory
        self.workspaceDirectory = workspaceDirectory
        self.cornerID = cornerID
        self.executablePath = executablePath
    }
}
