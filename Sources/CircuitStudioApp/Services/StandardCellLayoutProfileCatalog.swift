import Foundation

public enum StandardCellLayoutProfileCatalogError: Error, Sendable, Hashable, LocalizedError {
    case missingBundledResource(String)
    case unsupportedSchemaVersion(Int)
    case invalidKind(String)
    case emptyField(String)
    case emptyCatalog
    case duplicateProfileID(String)
    case missingProfileReference(String)
    case conflictingProfileReference(String)
    case profileNotFound(String)
    case missingDefaultProfile

    public var errorDescription: String? {
        switch self {
        case .missingBundledResource(let resourceName):
            return "Missing bundled standard-cell layout profile catalog resource '\(resourceName)'."
        case .unsupportedSchemaVersion(let version):
            return "Unsupported standard-cell layout profile catalog schema version: \(version)."
        case .invalidKind(let kind):
            return "Unsupported standard-cell layout profile catalog kind '\(kind)'."
        case .emptyField(let field):
            return "Standard-cell layout profile catalog field '\(field)' must not be empty."
        case .emptyCatalog:
            return "Standard-cell layout profile catalog must contain at least one profile."
        case .duplicateProfileID(let profileID):
            return "Standard-cell layout profile catalog declares duplicate profile ID '\(profileID)'."
        case .missingProfileReference(let profileID):
            return "Standard-cell layout profile catalog entry '\(profileID)' must declare a profile resource or path."
        case .conflictingProfileReference(let profileID):
            return "Standard-cell layout profile catalog entry '\(profileID)' must not declare both a profile resource and path."
        case .profileNotFound(let profileID):
            return "Standard-cell layout profile catalog does not contain profile ID '\(profileID)'."
        case .missingDefaultProfile:
            return "Standard-cell layout profile catalog has no default profile."
        }
    }
}

public struct StandardCellLayoutProfileCatalog: Codable, Sendable, Hashable {
    public struct Entry: Codable, Sendable, Hashable {
        public let profileID: String
        public let displayName: String?
        public let processName: String?
        public let profileResourceName: String?
        public let profilePath: String?
        public let defaultProfile: Bool

        public init(
            profileID: String,
            displayName: String? = nil,
            processName: String? = nil,
            profileResourceName: String? = nil,
            profilePath: String? = nil,
            defaultProfile: Bool = false
        ) {
            self.profileID = profileID
            self.displayName = displayName
            self.processName = processName
            self.profileResourceName = profileResourceName
            self.profilePath = profilePath
            self.defaultProfile = defaultProfile
        }

        private enum CodingKeys: String, CodingKey {
            case profileID
            case displayName
            case processName
            case profileResourceName
            case profilePath
            case defaultProfile
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            profileID = try container.decode(String.self, forKey: .profileID)
            displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            processName = try container.decodeIfPresent(String.self, forKey: .processName)
            profileResourceName = try container.decodeIfPresent(String.self, forKey: .profileResourceName)
            profilePath = try container.decodeIfPresent(String.self, forKey: .profilePath)
            defaultProfile = try container.decodeIfPresent(Bool.self, forKey: .defaultProfile) ?? false
        }
    }

    public static let currentSchemaVersion = 1
    public static let expectedKind = "standard-cell-layout-profile-catalog"
    public static let defaultBundledResourceName = "standard-cell-layout-profile-catalog"

    public let schemaVersion: Int
    public let kind: String
    public let catalogID: String
    public let profiles: [Entry]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        kind: String = Self.expectedKind,
        catalogID: String,
        profiles: [Entry]
    ) throws {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.catalogID = catalogID
        self.profiles = profiles
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        kind = try container.decode(String.self, forKey: .kind)
        catalogID = try container.decode(String.self, forKey: .catalogID)
        profiles = try container.decode([Entry].self, forKey: .profiles)
        try validate()
    }

    public static func load(from url: URL) throws -> StandardCellLayoutProfileCatalog {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StandardCellLayoutProfileCatalog.self, from: data)
    }

    public static func bundled(resourceName: String = Self.defaultBundledResourceName) throws -> StandardCellLayoutProfileCatalog {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw StandardCellLayoutProfileCatalogError.missingBundledResource(resourceName)
        }
        return try load(from: url)
    }

    public static func loadDefaultProfile(
        catalogResourceName: String = Self.defaultBundledResourceName
    ) throws -> StandardCellLayoutProfile {
        try bundled(resourceName: catalogResourceName).loadProfile()
    }

    public func entry(profileID: String? = nil) throws -> Entry {
        if let profileID {
            guard let entry = profiles.first(where: { $0.profileID == profileID }) else {
                throw StandardCellLayoutProfileCatalogError.profileNotFound(profileID)
            }
            return entry
        }
        guard let entry = profiles.first(where: \.defaultProfile) ?? profiles.first else {
            throw StandardCellLayoutProfileCatalogError.missingDefaultProfile
        }
        return entry
    }

    public func loadProfile(profileID: String? = nil) throws -> StandardCellLayoutProfile {
        let entry = try entry(profileID: profileID)
        if let resourceName = entry.profileResourceName {
            return try StandardCellLayoutProfile.bundled(resourceName: resourceName)
        }
        if let profilePath = entry.profilePath {
            return try StandardCellLayoutProfile.load(from: URL(fileURLWithPath: profilePath))
        }
        throw StandardCellLayoutProfileCatalogError.missingProfileReference(entry.profileID)
    }

    private func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw StandardCellLayoutProfileCatalogError.unsupportedSchemaVersion(schemaVersion)
        }
        guard kind == Self.expectedKind else {
            throw StandardCellLayoutProfileCatalogError.invalidKind(kind)
        }
        try Self.requireNonEmpty(catalogID, field: "catalogID")
        guard !profiles.isEmpty else {
            throw StandardCellLayoutProfileCatalogError.emptyCatalog
        }

        var seenProfileIDs: Set<String> = []
        var hasDefault = false
        for (index, entry) in profiles.enumerated() {
            try Self.requireNonEmpty(entry.profileID, field: "profiles[\(index)].profileID")
            guard seenProfileIDs.insert(entry.profileID).inserted else {
                throw StandardCellLayoutProfileCatalogError.duplicateProfileID(entry.profileID)
            }
            if let displayName = entry.displayName {
                try Self.requireNonEmpty(displayName, field: "profiles[\(index)].displayName")
            }
            if let processName = entry.processName {
                try Self.requireNonEmpty(processName, field: "profiles[\(index)].processName")
            }
            let hasResource = entry.profileResourceName?.isEmpty == false
            let hasPath = entry.profilePath?.isEmpty == false
            guard hasResource || hasPath else {
                throw StandardCellLayoutProfileCatalogError.missingProfileReference(entry.profileID)
            }
            guard !(hasResource && hasPath) else {
                throw StandardCellLayoutProfileCatalogError.conflictingProfileReference(entry.profileID)
            }
            if entry.defaultProfile {
                hasDefault = true
            }
        }
        guard hasDefault else {
            throw StandardCellLayoutProfileCatalogError.missingDefaultProfile
        }
    }

    private static func requireNonEmpty(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StandardCellLayoutProfileCatalogError.emptyField(field)
        }
    }
}
