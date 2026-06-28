import Foundation

public enum SignoffRuleClassificationProfileError: Error, Sendable, Hashable {
    case missingBundledResource(String)
}

public enum SignoffRuleClassificationProfileValidationError: Error, Sendable, Hashable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case emptyField(String)
    case emptyRules
    case duplicateRuleID(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported signoff rule classification profile schema version: \(version)."
        case .emptyField(let field):
            return "Signoff rule classification profile field '\(field)' must not be empty."
        case .emptyRules:
            return "Signoff rule classification profile must define at least one rule classification."
        case .duplicateRuleID(let ruleID):
            return "Signoff rule classification profile contains duplicate rule ID '\(ruleID)'."
        }
    }
}

public struct SignoffRuleClassificationProfile: Codable, Sendable, Hashable {
    public struct Rule: Codable, Sendable, Hashable {
        public let ruleID: String
        public let reason: String
        public let suggestedActions: [String]

        public init(ruleID: String, reason: String, suggestedActions: [String]) {
            self.ruleID = ruleID
            self.reason = reason
            self.suggestedActions = suggestedActions
        }
    }

    public let schemaVersion: Int
    public let profileID: String
    public let rules: [Rule]

    public init(schemaVersion: Int, profileID: String, rules: [Rule]) throws {
        self.schemaVersion = schemaVersion
        self.profileID = profileID
        self.rules = rules
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.profileID = try container.decode(String.self, forKey: .profileID)
        self.rules = try container.decode([Rule].self, forKey: .rules)
        try validate()
    }

    public static func load(from url: URL) throws -> SignoffRuleClassificationProfile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SignoffRuleClassificationProfile.self, from: data)
    }

    public static func bundled(resourceName: String) throws -> SignoffRuleClassificationProfile {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw SignoffRuleClassificationProfileError.missingBundledResource(resourceName)
        }
        return try load(from: url)
    }

    public func classificationByRuleID() throws -> [String: Rule] {
        var result: [String: Rule] = [:]
        for rule in rules {
            let key = rule.ruleID.lowercased()
            guard result[key] == nil else {
                throw SignoffRuleClassificationProfileValidationError.duplicateRuleID(rule.ruleID)
            }
            result[key] = rule
        }
        return result
    }

    private func validate() throws {
        guard schemaVersion == 1 else {
            throw SignoffRuleClassificationProfileValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        try Self.requireNonEmpty(profileID, field: "profileID")
        guard !rules.isEmpty else {
            throw SignoffRuleClassificationProfileValidationError.emptyRules
        }
        var seen: Set<String> = []
        for (index, rule) in rules.enumerated() {
            try Self.requireNonEmpty(rule.ruleID, field: "rules[\(index)].ruleID")
            try Self.requireNonEmpty(rule.reason, field: "rules[\(index)].reason")
            guard seen.insert(rule.ruleID.lowercased()).inserted else {
                throw SignoffRuleClassificationProfileValidationError.duplicateRuleID(rule.ruleID)
            }
            for (actionIndex, action) in rule.suggestedActions.enumerated() {
                try Self.requireNonEmpty(action, field: "rules[\(index)].suggestedActions[\(actionIndex)]")
            }
        }
    }

    private static func requireNonEmpty(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SignoffRuleClassificationProfileValidationError.emptyField(field)
        }
    }
}
