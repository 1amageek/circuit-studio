import Foundation

public struct ActivityReconciliationResult: Sendable, Hashable {
    public let projectID: String
    public let runCount: Int
    public let activityCount: Int

    public init(projectID: String, runCount: Int, activityCount: Int) {
        self.projectID = projectID
        self.runCount = runCount
        self.activityCount = activityCount
    }
}
