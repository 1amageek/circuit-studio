public enum BenchmarkError: Error, CustomStringConvertible {
    case invalidSampleCount(name: String, count: Int)
    case invalidIterationsPerSample(name: String, count: Int)
    case nonFiniteChecksum(String)
    case nonPositiveDuration(String)
    case missingRowMajorStorage(String)
    case referenceMismatch(name: String, lhs: Double, rhs: Double)
    case unexpectedReportStatus(String)

    public var description: String {
        switch self {
        case .invalidSampleCount(let name, let count):
            return "\(name) expected a positive sample count, got \(count)."
        case .invalidIterationsPerSample(let name, let count):
            return "\(name) expected positive iterations per sample, got \(count)."
        case .nonFiniteChecksum(let name):
            return "\(name) produced a non-finite checksum."
        case .nonPositiveDuration(let name):
            return "\(name) produced a non-positive median duration."
        case .missingRowMajorStorage(let name):
            return "\(name) did not expose row-major storage."
        case .referenceMismatch(let name, let lhs, let rhs):
            return "\(name) reference mismatch: \(lhs) vs \(rhs)."
        case .unexpectedReportStatus(let status):
            return "post-layout comparison returned unexpected status: \(status)."
        }
    }
}
