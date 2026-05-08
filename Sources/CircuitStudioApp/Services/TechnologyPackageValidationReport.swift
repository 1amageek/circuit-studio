import Foundation

public struct TechnologyPackageValidationReport: Sendable, Hashable, Codable {
    public struct Diagnostic: Sendable, Hashable, Codable {
        public enum Severity: String, Sendable, Hashable, Codable {
            case warning
            case error
        }

        public var severity: Severity
        public var code: String
        public var message: String
        public var path: String?

        public init(severity: Severity, code: String, message: String, path: String? = nil) {
            self.severity = severity
            self.code = code
            self.message = message
            self.path = path
        }
    }

    public var diagnostics: [Diagnostic]

    public init(diagnostics: [Diagnostic] = []) {
        self.diagnostics = diagnostics
    }

    public var isValid: Bool {
        !diagnostics.contains { $0.severity == .error }
    }

    public var errors: [Diagnostic] {
        diagnostics.filter { $0.severity == .error }
    }

    public var warnings: [Diagnostic] {
        diagnostics.filter { $0.severity == .warning }
    }
}
