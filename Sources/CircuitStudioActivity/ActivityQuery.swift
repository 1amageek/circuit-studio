import Foundation

public struct ActivityQuery: Sendable, Hashable {
    public let projectID: String?
    public let runID: String?
    public let stageID: String?
    public let kind: String?
    public let status: Activity.Status?
    public let actorKind: Activity.ActorKind?
    public let limit: Int

    public init(
        projectID: String? = nil,
        runID: String? = nil,
        stageID: String? = nil,
        kind: String? = nil,
        status: Activity.Status? = nil,
        actorKind: Activity.ActorKind? = nil,
        limit: Int = 200
    ) {
        self.projectID = projectID
        self.runID = runID
        self.stageID = stageID
        self.kind = kind
        self.status = status
        self.actorKind = actorKind
        self.limit = max(1, min(limit, 10_000))
    }
}
