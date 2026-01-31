import Foundation

/// UI-facing summary of a parsed SPICE netlist.
///
/// Decoupled from CoreSpice types so the UI layer does not need to import
/// CoreSpice directly.
public struct NetlistInfo: Sendable {
    public let title: String?
    public let components: [ComponentSummary]
    public let nodes: [String]
    public let analyses: [AnalysisSummary]
    public let models: [ModelSummary]
    public let diagnostics: [NetlistDiagnostic]
    public let hasErrors: Bool

    public init(
        title: String?,
        components: [ComponentSummary],
        nodes: [String],
        analyses: [AnalysisSummary],
        models: [ModelSummary],
        diagnostics: [NetlistDiagnostic],
        hasErrors: Bool
    ) {
        self.title = title
        self.components = components
        self.nodes = nodes
        self.analyses = analyses
        self.models = models
        self.diagnostics = diagnostics
        self.hasErrors = hasErrors
    }
}

/// Summary of a single parsed component.
public struct ComponentSummary: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let nodes: [String]
    public let modelName: String?
    public let primaryValue: String?

    public init(
        name: String,
        type: String,
        nodes: [String],
        modelName: String?,
        primaryValue: String?
    ) {
        self.name = name
        self.type = type
        self.nodes = nodes
        self.modelName = modelName
        self.primaryValue = primaryValue
    }
}

/// Summary of a detected analysis command.
public struct AnalysisSummary: Sendable, Identifiable {
    public var id: String { label }
    public let label: String
    public let type: String

    public init(label: String, type: String) {
        self.label = label
        self.type = type
    }
}

/// Summary of a .model card.
public struct ModelSummary: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let parameterCount: Int

    public init(name: String, type: String, parameterCount: Int) {
        self.name = name
        self.type = type
        self.parameterCount = parameterCount
    }
}

/// A parser diagnostic message.
public struct NetlistDiagnostic: Sendable, Identifiable {
    public let id: UUID
    public let severity: Severity
    public let message: String
    public let line: Int?

    public enum Severity: String, Sendable {
        case error
        case warning
        case info
        case hint
    }

    public init(severity: Severity, message: String, line: Int?) {
        self.id = UUID()
        self.severity = severity
        self.message = message
        self.line = line
    }
}
