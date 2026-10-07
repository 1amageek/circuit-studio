import Foundation

public struct PEXExtractionRequest: Sendable, Hashable {
    public let configURL: URL
    public let workspaceDirectory: URL?
    public let cornerID: String
    /// Explicit caller path resolved against the caller's current directory.
    public let executablePath: String?

    public init(
        configURL: URL,
        workspaceDirectory: URL? = nil,
        cornerID: String = "tt_25c_1v0",
        executablePath: String? = nil
    ) {
        self.configURL = configURL
        self.workspaceDirectory = workspaceDirectory
        self.cornerID = cornerID
        self.executablePath = executablePath
    }
}
