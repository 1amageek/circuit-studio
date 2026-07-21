import Foundation

public enum PostLayoutOracleAgreementError: Error, LocalizedError, Sendable {
    case emptyProbe
    case invalidMaximumAbsoluteDelta(probe: String, value: Double)
    case invalidSampleCount(probe: String, value: Int)
    case noProbeAgreements
    case duplicateProbe(String)
    case invalidTolerance(Double)

    public var errorDescription: String? {
        switch self {
        case .emptyProbe:
            "A post-layout oracle probe name must not be empty."
        case .invalidMaximumAbsoluteDelta(let probe, let value):
            "Post-layout oracle probe '\(probe)' has invalid maximum absolute delta \(value)."
        case .invalidSampleCount(let probe, let value):
            "Post-layout oracle probe '\(probe)' has invalid sample count \(value)."
        case .noProbeAgreements:
            "A post-layout oracle agreement requires at least one probe agreement."
        case .duplicateProbe(let probe):
            "Post-layout oracle agreement contains duplicate probe '\(probe)'."
        case .invalidTolerance(let value):
            "Post-layout oracle tolerance must be finite and nonnegative, got \(value)."
        }
    }
}
