public protocol ActivityQuerying: Sendable {
    func activities(for query: ActivityQuery) async throws -> [Activity]
}
