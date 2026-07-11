import Foundation

public struct Activity: Sendable, Hashable, Codable, Identifiable {
    public enum SourceKind: String, Sendable, Hashable, Codable {
        case app
        case xcircuiteRun
        case xcircuiteProgress
        case xcircuiteAction
        case xcircuiteDesignDiff
    }

    public enum Status: String, Sendable, Hashable, Codable {
        case running
        case succeeded
        case failed
        case cancelled
        case blocked
        case partial
        case informational
    }

    public enum ActorKind: String, Sendable, Hashable, Codable {
        case agent
        case human
        case cli
        case system
    }

    public enum ArtifactDirection: String, Sendable, Hashable, Codable {
        case input
        case output
        case related
    }

    public struct ArtifactReference: Sendable, Hashable, Codable {
        public let path: String
        public let role: String
        public let kind: String
        public let format: String
        public let sha256: String?
        public let byteCount: Int64?
        public let direction: ArtifactDirection

        public init(
            path: String,
            role: String,
            kind: String,
            format: String,
            sha256: String? = nil,
            byteCount: Int64? = nil,
            direction: ArtifactDirection
        ) {
            self.path = path
            self.role = role
            self.kind = kind
            self.format = format
            self.sha256 = sha256
            self.byteCount = byteCount
            self.direction = direction
        }
    }

    public struct Diagnostic: Sendable, Hashable, Codable {
        public let severity: String
        public let code: String
        public let message: String

        public init(severity: String, code: String, message: String) {
            self.severity = severity
            self.code = code
            self.message = message
        }
    }

    public struct Command: Sendable, Hashable, Codable {
        public let executable: String
        public let arguments: [String]
        public let redactedArgumentCount: Int
        public let omittedArgumentCount: Int

        public init(
            executable: String,
            arguments: [String] = [],
            redactedArgumentCount: Int = 0,
            omittedArgumentCount: Int = 0
        ) {
            self.executable = executable
            self.arguments = arguments
            self.redactedArgumentCount = redactedArgumentCount
            self.omittedArgumentCount = omittedArgumentCount
        }
    }

    public let id: String
    public let projectID: String
    public let operationID: String
    public let parentOperationID: String?
    public let sourceKind: SourceKind
    public let sourceID: String
    public let sourceRevision: Int
    public let runID: String?
    public let stageID: String?
    public let actorKind: ActorKind
    public let actorIdentifier: String
    public let kind: String
    public let status: Status
    public let title: String
    public let summary: String
    public let command: Command?
    public let artifacts: [ArtifactReference]
    public let omittedArtifactCount: Int
    public let diagnostics: [Diagnostic]
    public let omittedDiagnosticCount: Int
    public let occurredAt: Date
    public let indexedAt: Date

    public init(
        id: String,
        projectID: String,
        operationID: String,
        parentOperationID: String? = nil,
        sourceKind: SourceKind,
        sourceID: String,
        sourceRevision: Int = 0,
        runID: String? = nil,
        stageID: String? = nil,
        actorKind: ActorKind,
        actorIdentifier: String,
        kind: String,
        status: Status,
        title: String,
        summary: String,
        command: Command? = nil,
        artifacts: [ArtifactReference] = [],
        omittedArtifactCount: Int = 0,
        diagnostics: [Diagnostic] = [],
        omittedDiagnosticCount: Int = 0,
        occurredAt: Date,
        indexedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.operationID = operationID
        self.parentOperationID = parentOperationID
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.sourceRevision = sourceRevision
        self.runID = runID
        self.stageID = stageID
        self.actorKind = actorKind
        self.actorIdentifier = actorIdentifier
        self.kind = kind
        self.status = status
        self.title = title
        self.summary = summary
        self.command = command
        self.artifacts = artifacts
        self.omittedArtifactCount = omittedArtifactCount
        self.diagnostics = diagnostics
        self.omittedDiagnosticCount = omittedDiagnosticCount
        self.occurredAt = occurredAt
        self.indexedAt = indexedAt
    }
}
