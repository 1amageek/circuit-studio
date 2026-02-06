import Foundation

/// A process technology definition that describes model libraries, defaults, and corners.
public struct ProcessTechnology: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var version: String?
    public var foundry: String?
    public var defaultTemperature: Double
    public var includePaths: [String]
    public var libraries: [ProcessLibrary]
    public var globalParameters: [String: Double]
    public var cornerSet: CornerSet
    public var defaultCornerID: UUID?
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        version: String? = nil,
        foundry: String? = nil,
        defaultTemperature: Double = 27.0,
        includePaths: [String] = [],
        libraries: [ProcessLibrary] = [],
        globalParameters: [String: Double] = [:],
        cornerSet: CornerSet = CornerSet(name: "Default"),
        defaultCornerID: UUID? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.foundry = foundry
        self.defaultTemperature = defaultTemperature
        self.includePaths = includePaths
        self.libraries = libraries
        self.globalParameters = globalParameters
        self.cornerSet = cornerSet
        self.defaultCornerID = defaultCornerID
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.version = try container.decodeIfPresent(String.self, forKey: .version)
        self.foundry = try container.decodeIfPresent(String.self, forKey: .foundry)
        self.defaultTemperature = try container.decodeIfPresent(Double.self, forKey: .defaultTemperature) ?? 27.0
        self.includePaths = try container.decodeIfPresent([String].self, forKey: .includePaths) ?? []
        self.libraries = try container.decodeIfPresent([ProcessLibrary].self, forKey: .libraries) ?? []
        self.globalParameters = try container.decodeIfPresent([String: Double].self, forKey: .globalParameters) ?? [:]
        self.cornerSet = try container.decodeIfPresent(CornerSet.self, forKey: .cornerSet) ?? CornerSet(name: "Default")
        self.defaultCornerID = try container.decodeIfPresent(UUID.self, forKey: .defaultCornerID)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(foundry, forKey: .foundry)
        try container.encode(defaultTemperature, forKey: .defaultTemperature)
        try container.encode(includePaths, forKey: .includePaths)
        try container.encode(libraries, forKey: .libraries)
        try container.encode(globalParameters, forKey: .globalParameters)
        try container.encode(cornerSet, forKey: .cornerSet)
        try container.encodeIfPresent(defaultCornerID, forKey: .defaultCornerID)
        try container.encode(notes, forKey: .notes)
    }

    public func corner(id: UUID?) -> Corner? {
        guard let id else { return nil }
        return cornerSet.corners.first { $0.id == id }
    }

    public func library(id: String) -> ProcessLibrary? {
        libraries.first { $0.id == id }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case version
        case foundry
        case defaultTemperature
        case includePaths
        case libraries
        case globalParameters
        case cornerSet
        case defaultCornerID
        case notes
    }
}
