import Foundation

public enum Level1DeviceModelProfileError: Error, Sendable, Hashable {
    case missingBundledResource(String)
}

public enum Level1DeviceModelProfileValidationError: Error, Sendable, Hashable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case emptyField(String)
    case nonPositiveValue(String)
    case malformedModelCard(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported level-1 device model profile schema version: \(version)."
        case .emptyField(let field):
            return "Level-1 device model profile field '\(field)' must not be empty."
        case .nonPositiveValue(let field):
            return "Level-1 device model profile field '\(field)' must be greater than zero."
        case .malformedModelCard(let field):
            return "Level-1 device model profile field '\(field)' must contain a .model card."
        }
    }
}

public struct Level1DeviceModelProfile: Codable, Sendable, Hashable {
    public struct TechnologyMetadata: Codable, Sendable, Hashable {
        public let processName: String
        public let cornerID: String
        public let temperatureC: Double?
        public let deviceModelID: String

        public init(
            processName: String,
            cornerID: String,
            temperatureC: Double? = nil,
            deviceModelID: String
        ) {
            self.processName = processName
            self.cornerID = cornerID
            self.temperatureC = temperatureC
            self.deviceModelID = deviceModelID
        }
    }

    public let schemaVersion: Int
    public let profileID: String
    public let technology: TechnologyMetadata
    public let model: Level1DeviceModel

    public init(
        schemaVersion: Int,
        profileID: String,
        technology: TechnologyMetadata,
        model: Level1DeviceModel
    ) throws {
        self.schemaVersion = schemaVersion
        self.profileID = profileID
        self.technology = technology
        self.model = model
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.profileID = try container.decode(String.self, forKey: .profileID)
        self.technology = try container.decode(TechnologyMetadata.self, forKey: .technology)
        self.model = try container.decode(Level1DeviceModel.self, forKey: .model)
        try validate()
    }

    public static func load(from url: URL) throws -> Level1DeviceModelProfile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Level1DeviceModelProfile.self, from: data)
    }

    public static func bundled(resourceName: String) throws -> Level1DeviceModelProfile {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw Level1DeviceModelProfileError.missingBundledResource(resourceName)
        }
        return try load(from: url)
    }

    public func validate() throws {
        guard schemaVersion == 1 else {
            throw Level1DeviceModelProfileValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        try Self.requireNonEmpty(profileID, field: "profileID")
        try Self.requireNonEmpty(technology.processName, field: "technology.processName")
        try Self.requireNonEmpty(technology.cornerID, field: "technology.cornerID")
        try Self.requireNonEmpty(technology.deviceModelID, field: "technology.deviceModelID")
        try Self.requirePositive(model.supplyVoltage, field: "model.supplyVoltage")
        try Self.requireNonEmpty(model.nmosModelName, field: "model.nmosModelName")
        try Self.requireNonEmpty(model.pmosModelName, field: "model.pmosModelName")
        try Self.requireModelCard(model.nmosCard, field: "model.nmosCard")
        try Self.requireModelCard(model.pmosCard, field: "model.pmosCard")
        try Self.requirePositive(model.oxideCapPerArea, field: "model.oxideCapPerArea")
    }

    public func technologyContext(
        resourceName: String? = nil,
        path: String? = nil,
        sha256: String? = nil
    ) throws -> TimingTechnologyContext {
        TimingTechnologyContext(
            processName: technology.processName,
            cornerID: technology.cornerID,
            supplyVoltage: model.supplyVoltage,
            temperatureC: technology.temperatureC,
            deviceModelID: technology.deviceModelID,
            deviceModelHash: try TimingTopologyHasher.hashModel(model),
            modelProfile: TimingModelProfileReference(
                profileID: profileID,
                resourceName: resourceName,
                path: path,
                sha256: sha256
            )
        )
    }

    private static func requireNonEmpty(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Level1DeviceModelProfileValidationError.emptyField(field)
        }
    }

    private static func requirePositive(_ value: Double, field: String) throws {
        guard value > 0 else {
            throw Level1DeviceModelProfileValidationError.nonPositiveValue(field)
        }
    }

    private static func requireModelCard(_ value: String, field: String) throws {
        try requireNonEmpty(value, field: field)
        guard value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix(".model ") else {
            throw Level1DeviceModelProfileValidationError.malformedModelCard(field)
        }
    }
}
