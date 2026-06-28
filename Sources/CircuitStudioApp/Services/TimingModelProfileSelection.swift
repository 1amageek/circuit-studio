import Foundation

public struct TimingModelProfileSelection: Sendable, Hashable, Codable {
    public enum SourceKind: String, Sendable, Hashable, Codable {
        case bundledResource = "bundled-resource"
        case externalFile = "external-file"
    }

    public static let currentSchemaVersion = 1
    private static let expectedKind = "timing-model-profile-selection"

    public let schemaVersion: Int
    public let kind: String
    public let runID: String
    public let selectedAt: Date
    public let sourceKind: SourceKind
    public let selectionReason: String
    public let catalogID: String?
    public let catalogPath: String?
    public let profileSchemaVersion: Int
    public let profile: TimingModelProfileReference
    public let technology: TimingTechnologyContext

    public init(
        runID: String,
        selectedAt: Date = Date(),
        sourceKind: SourceKind,
        selectionReason: String,
        catalogID: String? = nil,
        catalogPath: String? = nil,
        profileSchemaVersion: Int,
        profile: TimingModelProfileReference,
        technology: TimingTechnologyContext
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.kind = Self.expectedKind
        self.runID = runID
        self.selectedAt = selectedAt
        self.sourceKind = sourceKind
        self.selectionReason = selectionReason
        self.catalogID = catalogID
        self.catalogPath = catalogPath
        self.profileSchemaVersion = profileSchemaVersion
        self.profile = profile
        self.technology = technology
    }
}

extension TimingModelProfileSelection {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case kind
        case runID
        case selectedAt
        case sourceKind
        case selectionReason
        case catalogID
        case catalogPath
        case profileSchemaVersion
        case profile
        case technology
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard decodedSchemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported timing model profile selection schema version \(decodedSchemaVersion)."
            )
        }
        let decodedKind = try container.decode(String.self, forKey: .kind)
        guard decodedKind == Self.expectedKind else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unsupported timing model profile selection kind \(decodedKind)."
            )
        }

        schemaVersion = decodedSchemaVersion
        kind = decodedKind
        runID = try container.decode(String.self, forKey: .runID)
        selectedAt = try TimingArtifactDateCoding.decode(from: container, forKey: .selectedAt)
        sourceKind = try container.decode(SourceKind.self, forKey: .sourceKind)
        selectionReason = try container.decode(String.self, forKey: .selectionReason)
        catalogID = try container.decodeIfPresent(String.self, forKey: .catalogID)
        catalogPath = try container.decodeIfPresent(String.self, forKey: .catalogPath)
        profileSchemaVersion = try container.decode(Int.self, forKey: .profileSchemaVersion)
        profile = try container.decode(TimingModelProfileReference.self, forKey: .profile)
        technology = try container.decode(TimingTechnologyContext.self, forKey: .technology)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(kind, forKey: .kind)
        try container.encode(runID, forKey: .runID)
        try TimingArtifactDateCoding.encode(selectedAt, to: &container, forKey: .selectedAt)
        try container.encode(sourceKind, forKey: .sourceKind)
        try container.encode(selectionReason, forKey: .selectionReason)
        try container.encodeIfPresent(catalogID, forKey: .catalogID)
        try container.encodeIfPresent(catalogPath, forKey: .catalogPath)
        try container.encode(profileSchemaVersion, forKey: .profileSchemaVersion)
        try container.encode(profile, forKey: .profile)
        try container.encode(technology, forKey: .technology)
    }
}
