import Foundation

public struct ExternalSignoffCommand: Sendable, Hashable, Codable {
    public let kind: ExternalSignoffToolReport.Kind
    public let toolName: String
    public let executablePath: String
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: URL?
    public let logFileName: String?
    public let timeoutSeconds: Double
    public let parserStyle: ExternalSignoffReportParser.Style?

    public init(
        kind: ExternalSignoffToolReport.Kind,
        toolName: String,
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil,
        logFileName: String? = nil,
        timeoutSeconds: Double = 300,
        parserStyle: ExternalSignoffReportParser.Style? = nil
    ) {
        self.kind = kind
        self.toolName = toolName
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.logFileName = logFileName
        self.timeoutSeconds = timeoutSeconds
        self.parserStyle = parserStyle
    }
}
