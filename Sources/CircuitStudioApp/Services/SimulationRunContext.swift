import Foundation

public struct SimulationRunContext: Sendable, Hashable {
    public let runID: String
    public let projectRoot: URL
    public let startedAt: Date

    public init(runID: String, projectRoot: URL, startedAt: Date) {
        self.runID = runID
        self.projectRoot = projectRoot
        self.startedAt = startedAt
    }
}
