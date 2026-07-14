import Foundation

public struct RunReviewFailureStateSummary: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case missingArtifact = "missing-artifact"
        case integrityMismatch = "integrity-mismatch"
        case staleEvidence = "stale-evidence"
        case blockedGate = "blocked-gate"
        case decodeFailure = "decode-failure"
        case unsupportedAction = "unsupported-action"
    }

    public enum Severity: String, Sendable, Hashable, CaseIterable {
        case info
        case warning
        case error
    }

    public let states: [State]
    public let kindCounts: [Count]
    public let severityCounts: [SeverityCount]

    public init(states: [State]) {
        self.states = states
        kindCounts = Self.kindCounts(for: states)
        severityCounts = Self.severityCounts(for: states)
    }

    public var hasContent: Bool {
        !states.isEmpty
    }

    public func states(of kind: Kind) -> [State] {
        states.filter { $0.kind == kind }
    }

    public func count(of kind: Kind) -> Int {
        kindCounts.first { $0.kind == kind }?.count ?? 0
    }

    public struct State: Sendable, Hashable {
        public let stateID: String
        public let kind: Kind
        public let severity: Severity
        public let title: String
        public let message: String
        public let stageID: String?
        public let gateID: String?
        public let itemID: String?
        public let nextActionID: String?
        public let artifactReferences: [ArtifactReference]
        public let diagnosticCodes: [String]
        public let suggestedActions: [String]

        public init(
            stateID: String,
            kind: Kind,
            severity: Severity,
            title: String,
            message: String,
            stageID: String?,
            gateID: String? = nil,
            itemID: String? = nil,
            nextActionID: String? = nil,
            artifactReferences: [ArtifactReference] = [],
            diagnosticCodes: [String] = [],
            suggestedActions: [String]
        ) {
            self.stateID = stateID
            self.kind = kind
            self.severity = severity
            self.title = title
            self.message = message
            self.stageID = stageID
            self.gateID = gateID
            self.itemID = itemID
            self.nextActionID = nextActionID
            self.artifactReferences = artifactReferences
            self.diagnosticCodes = diagnosticCodes
            self.suggestedActions = suggestedActions
        }
    }

    public struct ArtifactReference: Sendable, Hashable {
        public let role: String
        public let artifactID: String?
        public let stageID: String?
        public let path: String
        public let kind: String
        public let format: String
        public let integrityStatus: String?
        public let integrityMessage: String?

        public init(
            role: String,
            artifactID: String?,
            stageID: String?,
            path: String,
            kind: String,
            format: String,
            integrityStatus: String?,
            integrityMessage: String?
        ) {
            self.role = role
            self.artifactID = artifactID
            self.stageID = stageID
            self.path = path
            self.kind = kind
            self.format = format
            self.integrityStatus = integrityStatus
            self.integrityMessage = integrityMessage
        }
    }

    public struct Count: Sendable, Hashable {
        public let kind: Kind
        public let count: Int

        public init(kind: Kind, count: Int) {
            self.kind = kind
            self.count = count
        }
    }

    public struct SeverityCount: Sendable, Hashable {
        public let severity: Severity
        public let count: Int

        public init(severity: Severity, count: Int) {
            self.severity = severity
            self.count = count
        }
    }

    private static func kindCounts(for states: [State]) -> [Count] {
        Kind.allCases.compactMap { kind in
            let count = states.filter { $0.kind == kind }.count
            return count > 0 ? Count(kind: kind, count: count) : nil
        }
    }

    private static func severityCounts(for states: [State]) -> [SeverityCount] {
        Severity.allCases.compactMap { severity in
            let count = states.filter { $0.severity == severity }.count
            return count > 0 ? SeverityCount(severity: severity, count: count) : nil
        }
    }
}
