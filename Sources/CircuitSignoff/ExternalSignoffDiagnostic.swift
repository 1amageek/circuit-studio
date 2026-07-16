public struct ExternalSignoffDiagnostic: Sendable, Hashable, Codable {
    public enum Severity: String, Sendable, Hashable, Codable {
        case info
        case warning
        case error
    }

    public let severity: Severity
    public let message: String
    public let ruleID: String?
    public let componentName: String?
    public let netName: String?
    public let rawLine: String

    public init(
        severity: Severity,
        message: String,
        ruleID: String? = nil,
        componentName: String? = nil,
        netName: String? = nil,
        rawLine: String
    ) {
        self.severity = severity
        self.message = message
        self.ruleID = ruleID
        self.componentName = componentName
        self.netName = netName
        self.rawLine = rawLine
    }
}
