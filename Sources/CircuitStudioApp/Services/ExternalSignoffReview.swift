import Foundation

public struct ExternalSignoffReview: Sendable, Hashable, Codable {
    public enum ApprovalKind: String, Sendable, Hashable, Codable {
        case human
        case automated
    }

    public let reports: [ExternalSignoffToolReport]
    public let approvedBy: String?
    public let approvedAt: Date?
    public let approvalKind: ApprovalKind?
    public let waiverIDs: [String]

    public init(
        reports: [ExternalSignoffToolReport],
        approvedBy: String? = nil,
        approvedAt: Date? = nil,
        approvalKind: ApprovalKind? = nil,
        waiverIDs: [String] = []
    ) {
        self.reports = reports
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.approvalKind = approvalKind
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
        approvalKind: ApprovalKind = .human,
        waiverIDs: [String]? = nil
    ) -> ExternalSignoffReview {
        ExternalSignoffReview(
            reports: reports,
            approvedBy: reviewer,
            approvedAt: date,
            approvalKind: approvalKind,
            waiverIDs: waiverIDs ?? self.waiverIDs
        )
    }
}

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
    /// Positive proof the driver ran to a clean completion (its terminal marker was
    /// present): `DRC_DONE` for Magic DRC, `LVS_RESULT status=match` for Netgen LVS.
    /// A pass requires this — the absence of error diagnostics alone is not enough,
    /// so a tool that exits 0 with empty/truncated output cannot be a false pass.
    /// Generic logs require an explicit `SIGNOFF_RESULT status=...` line.
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

    /// A report passes only when the tool exited cleanly, ran to a verified
    /// completion, AND raised no error-severity diagnostic — all three, so a clean
    /// exit code can never stand in for evidence the check actually finished.
    public var passed: Bool {
        success && completed && !diagnostics.contains { $0.severity == .error }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, toolName, success, completed, parserStyle, logPath, diagnostics
    }

    // Backward-compatible decoding: artifacts written before `completed` existed
    // default to `true` (they predate the positive-evidence gate).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        toolName = try container.decode(String.self, forKey: .toolName)
        success = try container.decode(Bool.self, forKey: .success)
        completed = try container.decodeIfPresent(Bool.self, forKey: .completed) ?? true
        parserStyle = try container.decodeIfPresent(
            ExternalSignoffReportParser.Style.self,
            forKey: .parserStyle
        ) ?? .generic
        logPath = try container.decode(String.self, forKey: .logPath)
        diagnostics = try container.decodeIfPresent([ExternalSignoffDiagnostic].self, forKey: .diagnostics) ?? []
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
