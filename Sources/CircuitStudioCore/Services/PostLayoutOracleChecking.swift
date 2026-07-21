public protocol PostLayoutOracleChecking: Sendable {
    var isAvailable: Bool { get }

    func crossCheck(
        deck: String,
        command: AnalysisCommand,
        probes: [String],
        toleranceV: Double
    ) async throws -> PostLayoutOracleAgreement
}
