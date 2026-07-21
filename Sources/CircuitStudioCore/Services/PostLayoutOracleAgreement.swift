import Foundation

public struct PostLayoutOracleAgreement: Sendable, Hashable, Codable {
    public let probes: [PostLayoutProbeAgreement]
    public let toleranceV: Double

    public init(probes: [PostLayoutProbeAgreement], toleranceV: Double) throws {
        _ = try Self.normalizedUniqueProbeNames(probes.map(\.probe))
        try Self.validate(toleranceV: toleranceV)
        self.probes = probes
        self.toleranceV = toleranceV
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            probes: container.decode([PostLayoutProbeAgreement].self, forKey: .probes),
            toleranceV: container.decode(Double.self, forKey: .toleranceV)
        )
    }

    public static func validate(toleranceV: Double) throws {
        guard toleranceV.isFinite, toleranceV >= 0 else {
            throw PostLayoutOracleAgreementError.invalidTolerance(toleranceV)
        }
    }

    static func normalizedUniqueProbeNames(_ probeNames: [String]) throws -> [String] {
        guard !probeNames.isEmpty else {
            throw PostLayoutOracleAgreementError.noProbeAgreements
        }
        var canonicalNames: Set<String> = []
        return try probeNames.map { probeName in
            let normalized = probeName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw PostLayoutOracleAgreementError.emptyProbe
            }
            let canonical = normalized.lowercased()
            guard canonicalNames.insert(canonical).inserted else {
                throw PostLayoutOracleAgreementError.duplicateProbe(normalized)
            }
            return normalized
        }
    }

    public var maxDivergenceV: Double {
        probes.map(\.maxAbsoluteDeltaV).max() ?? .infinity
    }

    public var isConsistent: Bool {
        maxDivergenceV <= toleranceV
    }

    private enum CodingKeys: String, CodingKey {
        case probes
        case toleranceV
    }
}
