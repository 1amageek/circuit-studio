import Foundation

/// In-memory launch configuration. This type is intentionally not `Codable`
/// because arguments and environment values can contain credentials.
public struct ExternalSignoffCommand: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public let kind: ExternalSignoffToolReport.Kind
    public let toolName: String
    public let executablePath: String
    public let arguments: [String]
    public let sensitiveArgumentIndexes: [Int]
    public let environment: [String: String]
    /// Environment values that must be removed from captured output and diagnostics.
    /// Non-secret values remain observable because signoff parsers may depend on them.
    public let sensitiveEnvironmentKeys: Set<String>
    public let workingDirectory: URL?
    public let logFileName: String?
    public let timeoutSeconds: Double
    public let parserStyle: ExternalSignoffReportParser.Style?

    public init(
        kind: ExternalSignoffToolReport.Kind,
        toolName: String,
        executablePath: String,
        arguments: [String] = [],
        sensitiveArgumentIndexes: [Int] = [],
        environment: [String: String] = [:],
        sensitiveEnvironmentKeys: Set<String> = [],
        workingDirectory: URL? = nil,
        logFileName: String? = nil,
        timeoutSeconds: Double = 300,
        parserStyle: ExternalSignoffReportParser.Style? = nil
    ) {
        self.kind = kind
        self.toolName = toolName
        self.executablePath = executablePath
        self.arguments = arguments
        self.sensitiveArgumentIndexes = sensitiveArgumentIndexes
        self.environment = environment
        self.sensitiveEnvironmentKeys = sensitiveEnvironmentKeys
        self.workingDirectory = workingDirectory
        self.logFileName = logFileName
        self.timeoutSeconds = timeoutSeconds
        self.parserStyle = parserStyle
    }

    public var description: String {
        let sensitiveIndexes = Set(sensitiveArgumentIndexes)
        let effectiveEnvironment = ProcessInfo.processInfo.environment.merging(environment) {
            _, supplied in supplied
        }
        let sensitiveValues = sensitiveArgumentIndexes.compactMap { index in
            arguments.indices.contains(index) ? arguments[index] : nil
        } + sensitiveEnvironmentKeys.compactMap { effectiveEnvironment[$0] }
        let sanitizedArguments = arguments.enumerated().map { index, argument in
            sensitiveIndexes.contains(index) ? "<redacted>" : sanitize(argument, values: sensitiveValues)
        }
        return [
            "ExternalSignoffCommand(kind: \(kind.rawValue)",
            "toolName: \(sanitize(toolName, values: sensitiveValues))",
            "executablePath: \(sanitize(executablePath, values: sensitiveValues))",
            "arguments: \(sanitizedArguments)",
            "environmentKeys: \(environment.keys.sorted()))",
        ].joined(separator: ", ")
    }

    public var debugDescription: String { description }

    private func sanitize(_ value: String, values: [String]) -> String {
        let secrets = Set(values.filter { !$0.isEmpty }).sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs < rhs
        }
        return secrets.reduce(value) { partialResult, secret in
            partialResult.replacingOccurrences(of: secret, with: "<redacted>")
        }
    }
}
