import Foundation
import DesignFlowKernel

public struct FlowRunnerFailureEnvelope: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    public static let envelopeKind = "flow-runner-failure"

    public let schemaVersion: Int
    public let kind: String
    public let flowCommand: String
    public let errorKind: String
    public let errorType: String
    public let message: String
    public let helpHint: String?
    public let runID: String?
    public let projectRoot: String?
    public let manifest: String?
    public let stage: String?
    public let manifestInspectionError: String?
    public let recommendation: String
    public let nextActions: [FlowRunNextAction]

    public init(
        errorKind: String,
        errorType: String,
        message: String,
        helpHint: String? = nil,
        runID: String? = nil,
        projectRoot: String? = nil,
        manifest: String? = nil,
        stage: String? = nil,
        manifestInspectionError: String? = nil,
        recommendation: String,
        nextActions: [FlowRunNextAction] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.kind = Self.envelopeKind
        self.flowCommand = "failed"
        self.errorKind = errorKind
        self.errorType = errorType
        self.message = message
        self.helpHint = helpHint
        self.runID = runID
        self.projectRoot = projectRoot
        self.manifest = manifest
        self.stage = stage
        self.manifestInspectionError = manifestInspectionError
        self.recommendation = recommendation
        self.nextActions = nextActions
    }
}

extension FlowRunnerFailureEnvelope {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case kind
        case flowCommand
        case errorKind
        case errorType
        case message
        case helpHint
        case runID
        case projectRoot
        case manifest
        case stage
        case manifestInspectionError
        case recommendation
        case nextActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        kind = try container.decode(String.self, forKey: .kind)
        flowCommand = try container.decode(String.self, forKey: .flowCommand)
        errorKind = try container.decode(String.self, forKey: .errorKind)
        errorType = try container.decode(String.self, forKey: .errorType)
        message = try container.decode(String.self, forKey: .message)
        helpHint = try container.decodeIfPresent(String.self, forKey: .helpHint)
        runID = try container.decodeIfPresent(String.self, forKey: .runID)
        projectRoot = try container.decodeIfPresent(String.self, forKey: .projectRoot)
        manifest = try container.decodeIfPresent(String.self, forKey: .manifest)
        stage = try container.decodeIfPresent(String.self, forKey: .stage)
        manifestInspectionError = try container.decodeIfPresent(String.self, forKey: .manifestInspectionError)
        recommendation = try container.decode(String.self, forKey: .recommendation)
        nextActions = try container.decodeIfPresent([FlowRunNextAction].self, forKey: .nextActions) ?? []
    }
}
