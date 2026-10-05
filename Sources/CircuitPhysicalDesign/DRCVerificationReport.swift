import LayoutVerify

public struct DRCVerificationReport: Sendable, Hashable {
    public let violationCount: Int
    public let violationsByKind: [String: Int]
    public let passed: Bool
    /// Actual native source generation and preparation diagnostics, not inferred counters.
    public let nativeResult: LayoutDRCResult?

    public init(violationCount: Int, violationsByKind: [String: Int], passed: Bool, nativeResult: LayoutDRCResult? = nil) {
        self.violationCount = violationCount
        self.violationsByKind = violationsByKind
        self.nativeResult = nativeResult
        self.passed = passed && !(nativeResult?.diagnostics.contains(where: { $0.severity == .error }) ?? false)
    }
}
