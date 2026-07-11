public protocol ActivityRecording: Sendable {
    func record(_ activity: Activity) async throws
    func record(_ activities: [Activity]) async throws
}
