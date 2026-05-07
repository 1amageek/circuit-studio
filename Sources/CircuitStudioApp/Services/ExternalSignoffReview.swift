import Foundation

public struct ExternalSignoffReview: Sendable, Hashable, Codable {
    public let reports: [ExternalSignoffToolReport]
    public let approvedBy: String?
    public let approvedAt: Date?
    public let waiverIDs: [String]

    public init(
        reports: [ExternalSignoffToolReport],
        approvedBy: String? = nil,
        approvedAt: Date? = nil,
        waiverIDs: [String] = []
    ) {
        self.reports = reports
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.waiverIDs = waiverIDs
    }

    public var passed: Bool {
        !reports.isEmpty && reports.allSatisfy(\.passed)
    }

    public var isApproved: Bool {
        approvedBy?.isEmpty == false && approvedAt != nil
    }

    public var isReadyForPEX: Bool {
        passed && isApproved
    }

    public func approving(
        by reviewer: String,
        at date: Date,
        waiverIDs: [String]? = nil
    ) -> ExternalSignoffReview {
        ExternalSignoffReview(
            reports: reports,
            approvedBy: reviewer,
            approvedAt: date,
            waiverIDs: waiverIDs ?? self.waiverIDs
        )
    }
}

public struct ExternalSignoffToolReport: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case drc
        case lvs
    }

    public let kind: Kind
    public let toolName: String
    public let success: Bool
    public let logPath: String
    public let diagnostics: [ExternalSignoffDiagnostic]

    public init(
        kind: Kind,
        toolName: String,
        success: Bool,
        logPath: String,
        diagnostics: [ExternalSignoffDiagnostic] = []
    ) {
        self.kind = kind
        self.toolName = toolName
        self.success = success
        self.logPath = logPath
        self.diagnostics = diagnostics
    }

    public var passed: Bool {
        success && !diagnostics.contains { $0.severity == .error }
    }
}

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
