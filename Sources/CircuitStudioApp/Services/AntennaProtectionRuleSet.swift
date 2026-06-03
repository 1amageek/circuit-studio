import Foundation

public enum AntennaProtectionRuleSetError: Error, LocalizedError, Equatable {
    case invalidMaxSpanPerGateMicrons

    public var errorDescription: String? {
        switch self {
        case .invalidMaxSpanPerGateMicrons:
            return "Antenna max span per gate must be finite and positive."
        }
    }
}

public struct AntennaProtectionRuleSet: Sendable, Hashable, Codable {
    public let maxSpanPerGateMicrons: Double
    public let protectsAllUnanchoredGateNets: Bool
    public let protectsLocalGateContacts: Bool

    public init(
        maxSpanPerGateMicrons: Double = 205.0,
        protectsAllUnanchoredGateNets: Bool = true,
        protectsLocalGateContacts: Bool = true
    ) {
        self.maxSpanPerGateMicrons = maxSpanPerGateMicrons
        self.protectsAllUnanchoredGateNets = protectsAllUnanchoredGateNets
        self.protectsLocalGateContacts = protectsLocalGateContacts
    }

    public func validate() throws {
        guard maxSpanPerGateMicrons.isFinite, maxSpanPerGateMicrons > 0 else {
            throw AntennaProtectionRuleSetError.invalidMaxSpanPerGateMicrons
        }
    }

    public func requiresProtection(
        gateLoadCount: Int,
        hasDiffusionDischargeAnchor: Bool,
        spanPerGateMicrons: Double
    ) -> Bool {
        guard gateLoadCount > 0 else { return false }
        if protectsLocalGateContacts { return true }
        if !hasDiffusionDischargeAnchor && protectsAllUnanchoredGateNets { return true }
        return spanPerGateMicrons > maxSpanPerGateMicrons
    }
}
