import Foundation
import LayoutCore

public enum LayoutRoutingProfileError: Error, Sendable, Hashable {
    case missingBundledResource(String)
}

public enum LayoutRoutingProfileValidationError: Error, Sendable, Hashable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case emptyField(String)
    case nonPositiveValue(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported layout routing profile schema version: \(version)."
        case .emptyField(let field):
            return "Layout routing profile field '\(field)' must not be empty."
        case .nonPositiveValue(let field):
            return "Layout routing profile field '\(field)' must be positive."
        }
    }
}

public struct LayoutRoutingProfile: Codable, Sendable, Hashable {
    public typealias LayerReference = LayoutTechnologyLayerReference

    public enum LayerRole: String, Codable, Sendable, Hashable {
        case pinAccessBottom
        case horizontalRouting
        case verticalRouting
        case pinAccessCut
        case turnCut
        case powerRouting
    }

    public struct Layers: Codable, Sendable, Hashable {
        public let pinAccessBottom: LayerReference
        public let horizontalRouting: LayerReference
        public let verticalRouting: LayerReference
        public let pinAccessCut: LayerReference
        public let turnCut: LayerReference
        public let powerRouting: LayerReference

        public init(
            pinAccessBottom: LayerReference,
            horizontalRouting: LayerReference,
            verticalRouting: LayerReference,
            pinAccessCut: LayerReference,
            turnCut: LayerReference,
            powerRouting: LayerReference
        ) {
            self.pinAccessBottom = pinAccessBottom
            self.horizontalRouting = horizontalRouting
            self.verticalRouting = verticalRouting
            self.pinAccessCut = pinAccessCut
            self.turnCut = turnCut
            self.powerRouting = powerRouting
        }
    }

    public struct Geometry: Codable, Sendable, Hashable {
        public let gridPitch: Double
        public let gridMargin: Double
        public let maxOrderingPasses: Int
        public let mazeWireWidth: Double
        public let pinBottomPadWidth: Double
        public let pinTopPadWidth: Double
        public let pinAccessCutWidth: Double
        public let turnPadWidth: Double
        public let turnCutWidth: Double
        public let interBlockSignalWireWidth: Double
        public let powerRailHeight: Double
        public let powerSpineWidth: Double
        public let powerRowExtension: Double
        public let powerSpineMargin: Double
        public let powerSpineLaneSpacing: Double

        public init(
            gridPitch: Double,
            gridMargin: Double,
            maxOrderingPasses: Int,
            mazeWireWidth: Double,
            pinBottomPadWidth: Double,
            pinTopPadWidth: Double,
            pinAccessCutWidth: Double,
            turnPadWidth: Double,
            turnCutWidth: Double,
            interBlockSignalWireWidth: Double,
            powerRailHeight: Double,
            powerSpineWidth: Double,
            powerRowExtension: Double,
            powerSpineMargin: Double,
            powerSpineLaneSpacing: Double
        ) {
            self.gridPitch = gridPitch
            self.gridMargin = gridMargin
            self.maxOrderingPasses = maxOrderingPasses
            self.mazeWireWidth = mazeWireWidth
            self.pinBottomPadWidth = pinBottomPadWidth
            self.pinTopPadWidth = pinTopPadWidth
            self.pinAccessCutWidth = pinAccessCutWidth
            self.turnPadWidth = turnPadWidth
            self.turnCutWidth = turnCutWidth
            self.interBlockSignalWireWidth = interBlockSignalWireWidth
            self.powerRailHeight = powerRailHeight
            self.powerSpineWidth = powerSpineWidth
            self.powerRowExtension = powerRowExtension
            self.powerSpineMargin = powerSpineMargin
            self.powerSpineLaneSpacing = powerSpineLaneSpacing
        }
    }

    public let schemaVersion: Int
    public let profileID: String
    public let targetTechnologyResourceName: String
    public let layers: Layers
    public let geometry: Geometry

    public init(
        schemaVersion: Int = 1,
        profileID: String,
        targetTechnologyResourceName: String,
        layers: Layers,
        geometry: Geometry
    ) throws {
        self.schemaVersion = schemaVersion
        self.profileID = profileID
        self.targetTechnologyResourceName = targetTechnologyResourceName
        self.layers = layers
        self.geometry = geometry
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.profileID = try container.decode(String.self, forKey: .profileID)
        self.targetTechnologyResourceName = try container.decode(String.self, forKey: .targetTechnologyResourceName)
        self.layers = try container.decode(Layers.self, forKey: .layers)
        self.geometry = try container.decode(Geometry.self, forKey: .geometry)
        try validate()
    }

    public static func load(from url: URL) throws -> LayoutRoutingProfile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LayoutRoutingProfile.self, from: data)
    }

    public static func bundled(resourceName: String) throws -> LayoutRoutingProfile {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw LayoutRoutingProfileError.missingBundledResource(resourceName)
        }
        return try load(from: url)
    }

    public func layerReference(for role: LayerRole) -> LayerReference {
        switch role {
        case .pinAccessBottom:
            return layers.pinAccessBottom
        case .horizontalRouting:
            return layers.horizontalRouting
        case .verticalRouting:
            return layers.verticalRouting
        case .pinAccessCut:
            return layers.pinAccessCut
        case .turnCut:
            return layers.turnCut
        case .powerRouting:
            return layers.powerRouting
        }
    }

    public func layerID(for role: LayerRole) -> LayoutLayerID {
        let reference = layerReference(for: role)
        return LayoutLayerID(name: reference.name, purpose: reference.purpose)
    }

    public func validate() throws {
        guard schemaVersion == 1 else {
            throw LayoutRoutingProfileValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        try Self.requireNonEmpty(profileID, field: "profileID")
        try Self.requireNonEmpty(targetTechnologyResourceName, field: "targetTechnologyResourceName")
        try Self.validate(layers.pinAccessBottom, field: "layers.pinAccessBottom")
        try Self.validate(layers.horizontalRouting, field: "layers.horizontalRouting")
        try Self.validate(layers.verticalRouting, field: "layers.verticalRouting")
        try Self.validate(layers.pinAccessCut, field: "layers.pinAccessCut")
        try Self.validate(layers.turnCut, field: "layers.turnCut")
        try Self.validate(layers.powerRouting, field: "layers.powerRouting")
        try Self.requirePositive(geometry.gridPitch, field: "geometry.gridPitch")
        try Self.requirePositive(geometry.mazeWireWidth, field: "geometry.mazeWireWidth")
        try Self.requirePositive(geometry.pinBottomPadWidth, field: "geometry.pinBottomPadWidth")
        try Self.requirePositive(geometry.pinTopPadWidth, field: "geometry.pinTopPadWidth")
        try Self.requirePositive(geometry.pinAccessCutWidth, field: "geometry.pinAccessCutWidth")
        try Self.requirePositive(geometry.turnPadWidth, field: "geometry.turnPadWidth")
        try Self.requirePositive(geometry.turnCutWidth, field: "geometry.turnCutWidth")
        try Self.requirePositive(geometry.interBlockSignalWireWidth, field: "geometry.interBlockSignalWireWidth")
        try Self.requirePositive(geometry.powerRailHeight, field: "geometry.powerRailHeight")
        try Self.requirePositive(geometry.powerSpineWidth, field: "geometry.powerSpineWidth")
        try Self.requirePositive(geometry.powerRowExtension, field: "geometry.powerRowExtension")
        try Self.requirePositive(geometry.powerSpineMargin, field: "geometry.powerSpineMargin")
        try Self.requirePositive(geometry.powerSpineLaneSpacing, field: "geometry.powerSpineLaneSpacing")
        guard geometry.maxOrderingPasses > 0 else {
            throw LayoutRoutingProfileValidationError.nonPositiveValue("geometry.maxOrderingPasses")
        }
    }

    private static func validate(_ reference: LayerReference, field: String) throws {
        try requireNonEmpty(reference.name, field: "\(field).name")
        try requireNonEmpty(reference.purpose, field: "\(field).purpose")
    }

    private static func requireNonEmpty(_ value: String, field: String) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LayoutRoutingProfileValidationError.emptyField(field)
        }
    }

    private static func requirePositive(_ value: Double, field: String) throws {
        if !value.isFinite || value <= 0 {
            throw LayoutRoutingProfileValidationError.nonPositiveValue(field)
        }
    }
}
