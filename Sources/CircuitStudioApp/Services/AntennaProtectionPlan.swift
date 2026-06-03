import Foundation

public enum AntennaProtectionPlanValidationError: Error, LocalizedError, Equatable {
    case emptyDesignName
    case duplicateSiteID(String)
    case emptySiteField(siteID: String, field: String)
    case invalidGateLoadCount(siteID: String, value: Int)
    case invalidGeometry(siteID: String)

    public var errorDescription: String? {
        switch self {
        case .emptyDesignName:
            return "Antenna protection plan design name must not be empty."
        case .duplicateSiteID(let siteID):
            return "Antenna protection plan contains duplicate site ID \(siteID)."
        case .emptySiteField(let siteID, let field):
            return "Antenna protection site \(siteID) has an empty \(field)."
        case .invalidGateLoadCount(let siteID, let value):
            return "Antenna protection site \(siteID) has invalid gate load count \(value)."
        case .invalidGeometry(let siteID):
            return "Antenna protection site \(siteID) has invalid geometry."
        }
    }
}

public struct AntennaProtectionPlan: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1
    public static let artifactKind = "antenna-protection-plan"
    private static let expectedKind = artifactKind

    public enum Strategy: String, Sendable, Hashable, Codable {
        case diffusionTie
    }

    public struct Site: Sendable, Hashable, Codable {
        public let id: String
        public let net: String
        public let instanceName: String
        public let gateName: String
        public let centerXMicrons: Double
        public let trackYMicrons: Double
        public let gateLoadCount: Int
        public let hasDiffusionDischargeAnchor: Bool
        public let spanMicrons: Double
        public let spanPerGateMicrons: Double
        public let strategy: Strategy
        public let reason: String

        public init(
            id: String,
            net: String,
            instanceName: String,
            gateName: String,
            centerXMicrons: Double,
            trackYMicrons: Double,
            gateLoadCount: Int,
            hasDiffusionDischargeAnchor: Bool,
            spanMicrons: Double,
            spanPerGateMicrons: Double,
            strategy: Strategy,
            reason: String
        ) {
            self.id = id
            self.net = net
            self.instanceName = instanceName
            self.gateName = gateName
            self.centerXMicrons = centerXMicrons
            self.trackYMicrons = trackYMicrons
            self.gateLoadCount = gateLoadCount
            self.hasDiffusionDischargeAnchor = hasDiffusionDischargeAnchor
            self.spanMicrons = spanMicrons
            self.spanPerGateMicrons = spanPerGateMicrons
            self.strategy = strategy
            self.reason = reason
        }
    }

    public let schemaVersion: Int
    public let kind: String
    public let designName: String
    public let ruleSet: AntennaProtectionRuleSet
    public let sites: [Site]

    public init(
        designName: String,
        ruleSet: AntennaProtectionRuleSet,
        sites: [Site]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.kind = Self.expectedKind
        self.designName = designName
        self.ruleSet = ruleSet
        self.sites = sites
    }

    public var isEmpty: Bool {
        sites.isEmpty
    }

    public var siteIDs: Set<String> {
        Set(sites.map(\.id))
    }

    public func validate() throws {
        guard !designName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AntennaProtectionPlanValidationError.emptyDesignName
        }
        try ruleSet.validate()

        var seenSiteIDs: Set<String> = []
        for site in sites {
            try validate(site)
            guard seenSiteIDs.insert(site.id).inserted else {
                throw AntennaProtectionPlanValidationError.duplicateSiteID(site.id)
            }
        }
    }

    private func validate(_ site: Site) throws {
        try validateNonEmpty(site.id, siteID: site.id, field: "id")
        try validateNonEmpty(site.net, siteID: site.id, field: "net")
        try validateNonEmpty(site.instanceName, siteID: site.id, field: "instanceName")
        try validateNonEmpty(site.gateName, siteID: site.id, field: "gateName")
        try validateNonEmpty(site.reason, siteID: site.id, field: "reason")
        guard site.gateLoadCount > 0 else {
            throw AntennaProtectionPlanValidationError.invalidGateLoadCount(
                siteID: site.id,
                value: site.gateLoadCount
            )
        }
        guard site.centerXMicrons.isFinite,
              site.trackYMicrons.isFinite,
              site.spanMicrons.isFinite,
              site.spanPerGateMicrons.isFinite,
              site.spanMicrons >= 0,
              site.spanPerGateMicrons >= 0 else {
            throw AntennaProtectionPlanValidationError.invalidGeometry(siteID: site.id)
        }
    }

    private func validateNonEmpty(_ value: String, siteID: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AntennaProtectionPlanValidationError.emptySiteField(siteID: siteID, field: field)
        }
    }
}

extension AntennaProtectionPlan: ArtifactPayloadValidating {
    public func validateForPersistence() throws {
        try validate()
    }
}

extension AntennaProtectionPlan {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case kind
        case designName
        case ruleSet
        case sites
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard decodedSchemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported antenna protection plan schema version \(decodedSchemaVersion)."
            )
        }
        let decodedKind = try container.decode(String.self, forKey: .kind)
        guard decodedKind == Self.expectedKind else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unsupported antenna protection plan kind \(decodedKind)."
            )
        }
        schemaVersion = decodedSchemaVersion
        kind = decodedKind
        designName = try container.decode(String.self, forKey: .designName)
        ruleSet = try container.decode(AntennaProtectionRuleSet.self, forKey: .ruleSet)
        sites = try container.decode([Site].self, forKey: .sites)
        try validate()
    }
}
