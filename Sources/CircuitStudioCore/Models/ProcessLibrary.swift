import Foundation

/// A single process library file reference.
public struct ProcessLibrary: Sendable, Identifiable, Codable, Hashable {
    public let id: String
    public var name: String
    public var path: String
    public var kind: ProcessLibraryKind
    public var defaultSection: String?
    public var isEnabled: Bool

    public init(
        id: String,
        name: String,
        path: String,
        kind: ProcessLibraryKind = .library,
        defaultSection: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.kind = kind
        self.defaultSection = defaultSection
        self.isEnabled = isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let path = try container.decode(String.self, forKey: .path)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? path
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? path
        self.path = path
        self.kind = try container.decodeIfPresent(ProcessLibraryKind.self, forKey: .kind) ?? .library
        self.defaultSection = try container.decodeIfPresent(String.self, forKey: .defaultSection)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(defaultSection, forKey: .defaultSection)
        try container.encode(isEnabled, forKey: .isEnabled)
    }

    public init(
        name: String,
        path: String,
        kind: ProcessLibraryKind = .library,
        defaultSection: String? = nil,
        isEnabled: Bool = true
    ) {
        self.init(
            id: path,
            name: name,
            path: path,
            kind: kind,
            defaultSection: defaultSection,
            isEnabled: isEnabled
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case kind
        case defaultSection
        case isEnabled
    }
}
