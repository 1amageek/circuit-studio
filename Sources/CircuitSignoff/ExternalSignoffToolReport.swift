public struct ExternalSignoffToolReport: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case drc
        case lvs
        case antenna
        case density
    }

    public let kind: Kind
    public let toolName: String
    public let success: Bool
    /// Indicates that the driver emitted its authoritative terminal marker.
    /// A successful process exit without this evidence is not a completed check.
    public let completed: Bool
    public let parserStyle: ExternalSignoffReportParser.Style
    public let logPath: String
    public let diagnostics: [ExternalSignoffDiagnostic]

    public init(
        kind: Kind,
        toolName: String,
        success: Bool,
        completed: Bool = true,
        parserStyle: ExternalSignoffReportParser.Style = .generic,
        logPath: String,
        diagnostics: [ExternalSignoffDiagnostic] = []
    ) {
        self.kind = kind
        self.toolName = toolName
        self.success = success
        self.completed = completed
        self.parserStyle = parserStyle
        self.logPath = logPath
        self.diagnostics = diagnostics
    }

    /// A report passes only after successful execution, verified completion, and
    /// the absence of error diagnostics.
    public var passed: Bool {
        success && completed && !diagnostics.contains { $0.severity == .error }
    }
}
