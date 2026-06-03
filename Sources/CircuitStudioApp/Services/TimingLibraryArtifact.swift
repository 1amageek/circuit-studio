import Foundation

public struct TimingLibraryArtifact: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1
    private static let expectedKind = "timing-library"

    public let schemaVersion: Int
    public let kind: String
    public let runID: String?
    public let createdAt: Date
    public let technology: TimingTechnologyContext
    public let library: TimingLibrary
    public let modelSources: [TimingModelSource]
    public let warnings: [String]

    public init(
        runID: String? = nil,
        createdAt: Date = Date(),
        technology: TimingTechnologyContext,
        library: TimingLibrary,
        modelSources: [TimingModelSource],
        warnings: [String] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.kind = Self.expectedKind
        self.runID = runID
        self.createdAt = createdAt
        self.technology = technology
        self.library = library
        self.modelSources = modelSources
        self.warnings = warnings
    }
}

extension TimingLibraryArtifact {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case kind
        case runID
        case createdAt
        case technology
        case library
        case modelSources
        case warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard decodedSchemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported timing library artifact schema version \(decodedSchemaVersion)."
            )
        }
        let decodedKind = try container.decode(String.self, forKey: .kind)
        guard decodedKind == Self.expectedKind else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unsupported timing library artifact kind \(decodedKind)."
            )
        }
        schemaVersion = decodedSchemaVersion
        kind = decodedKind
        runID = try container.decodeIfPresent(String.self, forKey: .runID)
        createdAt = try TimingArtifactDateCoding.decode(from: container, forKey: .createdAt)
        technology = try container.decode(TimingTechnologyContext.self, forKey: .technology)
        library = try container.decode(TimingLibrary.self, forKey: .library)
        modelSources = try container.decode([TimingModelSource].self, forKey: .modelSources)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(runID, forKey: .runID)
        try TimingArtifactDateCoding.encode(createdAt, to: &container, forKey: .createdAt)
        try container.encode(technology, forKey: .technology)
        try container.encode(library, forKey: .library)
        try container.encode(modelSources, forKey: .modelSources)
        try container.encode(warnings, forKey: .warnings)
    }
}
