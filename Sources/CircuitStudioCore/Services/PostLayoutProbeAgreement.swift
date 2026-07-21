import Foundation

public struct PostLayoutProbeAgreement: Sendable, Hashable, Codable {
    public let probe: String
    public let maxAbsoluteDeltaV: Double
    public let sampleCount: Int

    public init(probe: String, maxAbsoluteDeltaV: Double, sampleCount: Int) throws {
        let normalizedProbe = probe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProbe.isEmpty else {
            throw PostLayoutOracleAgreementError.emptyProbe
        }
        guard maxAbsoluteDeltaV.isFinite, maxAbsoluteDeltaV >= 0 else {
            throw PostLayoutOracleAgreementError.invalidMaximumAbsoluteDelta(
                probe: normalizedProbe,
                value: maxAbsoluteDeltaV
            )
        }
        guard sampleCount > 0 else {
            throw PostLayoutOracleAgreementError.invalidSampleCount(
                probe: normalizedProbe,
                value: sampleCount
            )
        }
        self.probe = normalizedProbe
        self.maxAbsoluteDeltaV = maxAbsoluteDeltaV
        self.sampleCount = sampleCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            probe: container.decode(String.self, forKey: .probe),
            maxAbsoluteDeltaV: container.decode(Double.self, forKey: .maxAbsoluteDeltaV),
            sampleCount: container.decode(Int.self, forKey: .sampleCount)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case probe
        case maxAbsoluteDeltaV
        case sampleCount
    }
}
