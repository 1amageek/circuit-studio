public struct DRCVerificationReport: Sendable, Hashable {
    public let violationCount: Int
    public let violationsByKind: [String: Int]
    public let passed: Bool

    public init(violationCount: Int, violationsByKind: [String: Int], passed: Bool) {
        self.violationCount = violationCount
        self.violationsByKind = violationsByKind
        self.passed = passed
    }
}
