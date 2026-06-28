import Foundation

public enum TimingModelProfileCatalogError: Error, Sendable, Hashable, LocalizedError {
    case missingBundledResource(String)
    case unsupportedSchemaVersion(Int)
    case invalidKind(String)
    case emptyField(String)
    case emptyCatalog
    case duplicateProfileID(String)
    case missingProfileReference(String)
    case conflictingProfileReference(String)
    case profileNotFound(String)
    case cornerNotFound(String)
    case ambiguousCorner(String, [String])
    case profileCornerMismatch(profileID: String, expectedCornerID: String, actualCornerID: String?)
    case missingDefaultProfile

    public var errorDescription: String? {
        switch self {
        case .missingBundledResource(let resourceName):
            return "Missing bundled timing model profile catalog resource '\(resourceName)'."
        case .unsupportedSchemaVersion(let version):
            return "Unsupported timing model profile catalog schema version: \(version)."
        case .invalidKind(let kind):
            return "Unsupported timing model profile catalog kind '\(kind)'."
        case .emptyField(let field):
            return "Timing model profile catalog field '\(field)' must not be empty."
        case .emptyCatalog:
            return "Timing model profile catalog must contain at least one profile."
        case .duplicateProfileID(let profileID):
            return "Timing model profile catalog declares duplicate profile ID '\(profileID)'."
        case .missingProfileReference(let profileID):
            return "Timing model profile catalog entry '\(profileID)' must declare a profile resource or profile path."
        case .conflictingProfileReference(let profileID):
            return "Timing model profile catalog entry '\(profileID)' must not declare both a profile resource and profile path."
        case .profileNotFound(let profileID):
            return "Timing model profile catalog does not contain profile ID '\(profileID)'."
        case .cornerNotFound(let cornerID):
            return "Timing model profile catalog does not contain corner ID '\(cornerID)'."
        case .ambiguousCorner(let cornerID, let profileIDs):
            return "Timing model profile catalog corner ID '\(cornerID)' matches multiple profiles: \(profileIDs.joined(separator: ", "))."
        case .profileCornerMismatch(let profileID, let expectedCornerID, let actualCornerID):
            return "Timing model profile catalog entry '\(profileID)' has corner ID '\(actualCornerID ?? "")', not '\(expectedCornerID)'."
        case .missingDefaultProfile:
            return "Timing model profile catalog has no default profile."
        }
    }
}

public struct TimingModelProfileCatalog: Codable, Sendable, Hashable {
    public struct Entry: Codable, Sendable, Hashable {
        public let profileID: String
        public let displayName: String?
        public let cornerID: String?
        public let profileResourceName: String?
        public let profilePath: String?
        public let defaultProfile: Bool

        public init(
            profileID: String,
            displayName: String? = nil,
            cornerID: String? = nil,
            profileResourceName: String? = nil,
            profilePath: String? = nil,
            defaultProfile: Bool = false
        ) {
            self.profileID = profileID
            self.displayName = displayName
            self.cornerID = cornerID
            self.profileResourceName = profileResourceName
            self.profilePath = profilePath
            self.defaultProfile = defaultProfile
        }

        private enum CodingKeys: String, CodingKey {
            case profileID
            case displayName
            case cornerID
            case profileResourceName
            case profilePath
            case defaultProfile
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            profileID = try container.decode(String.self, forKey: .profileID)
            displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            cornerID = try container.decodeIfPresent(String.self, forKey: .cornerID)
            profileResourceName = try container.decodeIfPresent(String.self, forKey: .profileResourceName)
            profilePath = try container.decodeIfPresent(String.self, forKey: .profilePath)
            defaultProfile = try container.decodeIfPresent(Bool.self, forKey: .defaultProfile) ?? false
        }
    }

    public static let currentSchemaVersion = 1
    public static let expectedKind = "timing-model-profile-catalog"
    public static let defaultBundledResourceName = "timing-model-profile-catalog"

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

    public static func load(from url: URL) throws -> TimingModelProfileCatalog {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TimingModelProfileCatalog.self, from: data)
    }

    public static func bundled(resourceName: String = Self.defaultBundledResourceName) throws -> TimingModelProfileCatalog {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw TimingModelProfileCatalogError.missingBundledResource(resourceName)
        }
        return try load(from: url)
    }

    public func entry(profileID: String?, cornerID: String? = nil) throws -> Entry {
        if let profileID {
            guard let entry = profiles.first(where: { $0.profileID == profileID }) else {
                throw TimingModelProfileCatalogError.profileNotFound(profileID)
            }
            if let cornerID, entry.cornerID != cornerID {
                throw TimingModelProfileCatalogError.profileCornerMismatch(
                    profileID: profileID,
                    expectedCornerID: cornerID,
                    actualCornerID: entry.cornerID
                )
            }
            return entry
        }
        if let cornerID {
            let matches = profiles.filter { $0.cornerID == cornerID }
            guard !matches.isEmpty else {
                throw TimingModelProfileCatalogError.cornerNotFound(cornerID)
            }
            guard matches.count == 1, let entry = matches.first else {
                throw TimingModelProfileCatalogError.ambiguousCorner(cornerID, matches.map(\.profileID).sorted())
            }
            return entry
        }
        guard let entry = profiles.first(where: \.defaultProfile) ?? profiles.first else {
            throw TimingModelProfileCatalogError.missingDefaultProfile
        }
        return entry
    }

    private func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw TimingModelProfileCatalogError.unsupportedSchemaVersion(schemaVersion)
        }
        guard kind == Self.expectedKind else {
            throw TimingModelProfileCatalogError.invalidKind(kind)
        }
        try Self.requireNonEmpty(catalogID, field: "catalogID")
        guard !profiles.isEmpty else {
            throw TimingModelProfileCatalogError.emptyCatalog
        }

        var seenProfileIDs: Set<String> = []
        for profile in profiles {
            try Self.requireNonEmpty(profile.profileID, field: "profiles[].profileID")
            if let cornerID = profile.cornerID {
                try Self.requireNonEmpty(cornerID, field: "profiles[].cornerID")
            }
            if !seenProfileIDs.insert(profile.profileID).inserted {
                throw TimingModelProfileCatalogError.duplicateProfileID(profile.profileID)
            }
            let hasResource = profile.profileResourceName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let hasPath = profile.profilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            switch (hasResource, hasPath) {
            case (true, false), (false, true):
                break
            case (false, false):
                throw TimingModelProfileCatalogError.missingProfileReference(profile.profileID)
            case (true, true):
                throw TimingModelProfileCatalogError.conflictingProfileReference(profile.profileID)
            }
        }
    }

    private static func requireNonEmpty(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TimingModelProfileCatalogError.emptyField(field)
        }
    }
}

public struct TimingModelProfileCatalogInspection: Codable, Sendable, Hashable {
    public enum Status: String, Codable, Sendable, Hashable {
        case passed
        case failed
    }

    public struct Diagnostic: Codable, Sendable, Hashable {
        public let severity: String
        public let code: String
        public let message: String

        public init(severity: String, code: String, message: String) {
            self.severity = severity
            self.code = code
            self.message = message
        }
    }

    public struct Profile: Codable, Sendable, Hashable {
        public let profileID: String
        public let displayName: String?
        public let sourceKind: TimingModelProfileSelection.SourceKind
        public let declaredCornerID: String?
        public let profileResourceName: String?
        public let profilePath: String?
        public let defaultProfile: Bool
        public let status: Status
        public let schemaVersion: Int?
        public let processName: String?
        public let cornerID: String?
        public let deviceModelID: String?
        public let supplyVoltage: Double?
        public let deviceModelHash: String?
        public let sha256: String?
        public let diagnostics: [Diagnostic]

        public init(
            profileID: String,
            displayName: String?,
            sourceKind: TimingModelProfileSelection.SourceKind,
            declaredCornerID: String?,
            profileResourceName: String?,
            profilePath: String?,
            defaultProfile: Bool,
            status: Status,
            schemaVersion: Int?,
            processName: String?,
            cornerID: String?,
            deviceModelID: String?,
            supplyVoltage: Double?,
            deviceModelHash: String?,
            sha256: String?,
            diagnostics: [Diagnostic]
        ) {
            self.profileID = profileID
            self.displayName = displayName
            self.sourceKind = sourceKind
            self.declaredCornerID = declaredCornerID
            self.profileResourceName = profileResourceName
            self.profilePath = profilePath
            self.defaultProfile = defaultProfile
            self.status = status
            self.schemaVersion = schemaVersion
            self.processName = processName
            self.cornerID = cornerID
            self.deviceModelID = deviceModelID
            self.supplyVoltage = supplyVoltage
            self.deviceModelHash = deviceModelHash
            self.sha256 = sha256
            self.diagnostics = diagnostics
        }
    }

    public let catalogID: String
    public let catalogPath: String?
    public let profileCount: Int
    public let passedProfileCount: Int
    public let failedProfileCount: Int
    public let defaultProfileID: String?
    public let profiles: [Profile]
    public let status: Status

    public init(catalogID: String, catalogPath: String?, profiles: [Profile]) {
        self.catalogID = catalogID
        self.catalogPath = catalogPath
        self.profileCount = profiles.count
        self.passedProfileCount = profiles.filter { $0.status == .passed }.count
        self.failedProfileCount = profiles.filter { $0.status == .failed }.count
        self.defaultProfileID = profiles.first { $0.defaultProfile }?.profileID
        self.profiles = profiles
        self.status = profiles.contains { $0.status == .failed } ? .failed : .passed
    }
}
