import Foundation
import LayoutCore
import LayoutTech

public enum LayoutTechnologyCatalogError: Error, Sendable, Hashable, LocalizedError {
    case missingBundledResource(String)
    case unsupportedSchemaVersion(Int)
    case invalidKind(String)
    case emptyField(String)
    case emptyCatalog
    case duplicateTechnologyID(String)
    case missingTechnologyResource(String)
    case conflictingTechnologyReference(String)
    case technologyNotFound(String)
    case missingDefaultTechnology

    public var errorDescription: String? {
        switch self {
        case .missingBundledResource(let resourceName):
            return "Missing bundled layout technology catalog resource '\(resourceName)'."
        case .unsupportedSchemaVersion(let version):
            return "Unsupported layout technology catalog schema version: \(version)."
        case .invalidKind(let kind):
            return "Unsupported layout technology catalog kind '\(kind)'."
        case .emptyField(let field):
            return "Layout technology catalog field '\(field)' must not be empty."
        case .emptyCatalog:
            return "Layout technology catalog must contain at least one technology."
        case .duplicateTechnologyID(let technologyID):
            return "Layout technology catalog declares duplicate technology ID '\(technologyID)'."
        case .missingTechnologyResource(let technologyID):
            return "Layout technology catalog entry '\(technologyID)' must declare a technology resource or path."
        case .conflictingTechnologyReference(let technologyID):
            return "Layout technology catalog entry '\(technologyID)' must not declare both a technology resource and path."
        case .technologyNotFound(let technologyID):
            return "Layout technology catalog does not contain technology ID '\(technologyID)'."
        case .missingDefaultTechnology:
            return "Layout technology catalog has no default technology."
        }
    }
}

public struct LayoutTechnologyCatalog: Codable, Sendable, Hashable {
    public struct Entry: Codable, Sendable, Hashable {
        public let technologyID: String
        public let displayName: String?
        public let processName: String?
        public let technologyResourceName: String?
        public let technologyPath: String?
        public let routingProfileResourceName: String?
        public let defaultTechnology: Bool

        public init(
            technologyID: String,
            displayName: String? = nil,
            processName: String? = nil,
            technologyResourceName: String? = nil,
            technologyPath: String? = nil,
            routingProfileResourceName: String? = nil,
            defaultTechnology: Bool = false
        ) {
            self.technologyID = technologyID
            self.displayName = displayName
            self.processName = processName
            self.technologyResourceName = technologyResourceName
            self.technologyPath = technologyPath
            self.routingProfileResourceName = routingProfileResourceName
            self.defaultTechnology = defaultTechnology
        }

        private enum CodingKeys: String, CodingKey {
            case technologyID
            case displayName
            case processName
            case technologyResourceName
            case technologyPath
            case routingProfileResourceName
            case defaultTechnology
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            technologyID = try container.decode(String.self, forKey: .technologyID)
            displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            processName = try container.decodeIfPresent(String.self, forKey: .processName)
            technologyResourceName = try container.decodeIfPresent(String.self, forKey: .technologyResourceName)
            technologyPath = try container.decodeIfPresent(String.self, forKey: .technologyPath)
            routingProfileResourceName = try container.decodeIfPresent(String.self, forKey: .routingProfileResourceName)
            defaultTechnology = try container.decodeIfPresent(Bool.self, forKey: .defaultTechnology) ?? false
        }
    }

    public static let currentSchemaVersion = 1
    public static let expectedKind = "layout-technology-catalog"
    public static let defaultBundledResourceName = "layout-technology-catalog"

    public let schemaVersion: Int
    public let kind: String
    public let catalogID: String
    public let technologies: [Entry]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        kind: String = Self.expectedKind,
        catalogID: String,
        technologies: [Entry]
    ) throws {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.catalogID = catalogID
        self.technologies = technologies
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        kind = try container.decode(String.self, forKey: .kind)
        catalogID = try container.decode(String.self, forKey: .catalogID)
        technologies = try container.decode([Entry].self, forKey: .technologies)
        try validate()
    }

    public static func load(from url: URL) throws -> LayoutTechnologyCatalog {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LayoutTechnologyCatalog.self, from: data)
    }

    public static func bundled(resourceName: String = Self.defaultBundledResourceName) throws -> LayoutTechnologyCatalog {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw LayoutTechnologyCatalogError.missingBundledResource(resourceName)
        }
        return try load(from: url)
    }

    public static func defaultEntry(
        catalogResourceName: String = Self.defaultBundledResourceName
    ) throws -> Entry {
        try bundled(resourceName: catalogResourceName).entry()
    }

    public static func loadDefaultTechnology(
        catalogResourceName: String = Self.defaultBundledResourceName
    ) throws -> LayoutTechDatabase {
        try bundled(resourceName: catalogResourceName).loadTechnology()
    }

    public static func loadDefaultRoutingProfile(
        catalogResourceName: String = Self.defaultBundledResourceName
    ) throws -> LayoutRoutingProfile {
        let entry = try defaultEntry(catalogResourceName: catalogResourceName)
        guard let resourceName = entry.routingProfileResourceName else {
            throw LayoutTechnologyCatalogError.missingTechnologyResource(entry.technologyID)
        }
        return try LayoutRoutingProfile.bundled(resourceName: resourceName)
    }

    public static func defaultLayer(_ name: String, purpose: String? = nil) -> LayoutLayerID {
        LayoutTechnologyResource.layer(name, purpose: purpose)
    }

    public func entry(technologyID: String? = nil) throws -> Entry {
        if let technologyID {
            guard let entry = technologies.first(where: { $0.technologyID == technologyID }) else {
                throw LayoutTechnologyCatalogError.technologyNotFound(technologyID)
            }
            return entry
        }
        guard let entry = technologies.first(where: \.defaultTechnology) ?? technologies.first else {
            throw LayoutTechnologyCatalogError.missingDefaultTechnology
        }
        return entry
    }

    public func loadTechnology(technologyID: String? = nil) throws -> LayoutTechDatabase {
        let entry = try entry(technologyID: technologyID)
        if let resourceName = entry.technologyResourceName {
            return try LayoutTechnologyResource.bundled(resourceName: resourceName)
        }
        if let technologyPath = entry.technologyPath {
            return try LayoutTechnologyResource.load(from: URL(fileURLWithPath: technologyPath))
        }
        throw LayoutTechnologyCatalogError.missingTechnologyResource(entry.technologyID)
    }

    public func loadRoutingProfile(technologyID: String? = nil) throws -> LayoutRoutingProfile {
        let entry = try entry(technologyID: technologyID)
        guard let resourceName = entry.routingProfileResourceName else {
            throw LayoutTechnologyCatalogError.missingTechnologyResource(entry.technologyID)
        }
        return try LayoutRoutingProfile.bundled(resourceName: resourceName)
    }

    private func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LayoutTechnologyCatalogError.unsupportedSchemaVersion(schemaVersion)
        }
        guard kind == Self.expectedKind else {
            throw LayoutTechnologyCatalogError.invalidKind(kind)
        }
        try Self.requireNonEmpty(catalogID, field: "catalogID")
        guard !technologies.isEmpty else {
            throw LayoutTechnologyCatalogError.emptyCatalog
        }

        var seenTechnologyIDs: Set<String> = []
        var hasDefault = false
        for (index, entry) in technologies.enumerated() {
            try Self.requireNonEmpty(entry.technologyID, field: "technologies[\(index)].technologyID")
            guard seenTechnologyIDs.insert(entry.technologyID).inserted else {
                throw LayoutTechnologyCatalogError.duplicateTechnologyID(entry.technologyID)
            }
            if let displayName = entry.displayName {
                try Self.requireNonEmpty(displayName, field: "technologies[\(index)].displayName")
            }
            if let processName = entry.processName {
                try Self.requireNonEmpty(processName, field: "technologies[\(index)].processName")
            }
            let hasResource = entry.technologyResourceName?.isEmpty == false
            let hasPath = entry.technologyPath?.isEmpty == false
            guard hasResource || hasPath else {
                throw LayoutTechnologyCatalogError.missingTechnologyResource(entry.technologyID)
            }
            guard !(hasResource && hasPath) else {
                throw LayoutTechnologyCatalogError.conflictingTechnologyReference(entry.technologyID)
            }
            if let routingProfileResourceName = entry.routingProfileResourceName {
                try Self.requireNonEmpty(
                    routingProfileResourceName,
                    field: "technologies[\(index)].routingProfileResourceName"
                )
            }
            if entry.defaultTechnology {
                hasDefault = true
            }
        }
        guard hasDefault else {
            throw LayoutTechnologyCatalogError.missingDefaultTechnology
        }
    }

    private static func requireNonEmpty(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LayoutTechnologyCatalogError.emptyField(field)
        }
    }
}
