import Foundation

public struct LayoutTechnologyLayerReference: Codable, Sendable, Hashable {
    public let name: String
    public let purpose: String

    public init(name: String, purpose: String) {
        self.name = name
        self.purpose = purpose
    }
}

public enum LayoutTechnologyTranslationProfileError: Error, Sendable, Hashable {
    case missingBundledResource(String)
}

public enum LayoutTechnologyTranslationProfileValidationError: Error, Sendable, Hashable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case emptyField(String)
    case negativeValue(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported layout technology translation profile schema version: \(version)."
        case .emptyField(let field):
            return "Layout technology translation profile field '\(field)' must not be empty."
        case .negativeValue(let field):
            return "Layout technology translation profile field '\(field)' must not be negative."
        }
    }
}

public struct LayoutTechnologyTranslationProfile: Codable, Sendable, Hashable {
    public typealias LayerReference = LayoutTechnologyLayerReference

    public struct SourceLayers: Codable, Sendable, Hashable {
        public let active: String
        public let contact: String
        public let poly: String
        public let nImplant: String
        public let pImplant: String
        public let nWell: String

        public init(
            active: String,
            contact: String,
            poly: String,
            nImplant: String,
            pImplant: String,
            nWell: String
        ) {
            self.active = active
            self.contact = contact
            self.poly = poly
            self.nImplant = nImplant
            self.pImplant = pImplant
            self.nWell = nWell
        }
    }

    public struct TargetLayers: Codable, Sendable, Hashable {
        public let diffusion: LayerReference
        public let tap: LayerReference
        public let localInterconnect: LayerReference
        public let gateCutMask: LayerReference
        public let gateConductor: LayerReference
        public let contactCut: LayerReference
        public let metalContactCut: LayerReference

        public init(
            diffusion: LayerReference,
            tap: LayerReference,
            localInterconnect: LayerReference,
            gateCutMask: LayerReference,
            gateConductor: LayerReference,
            contactCut: LayerReference,
            metalContactCut: LayerReference
        ) {
            self.diffusion = diffusion
            self.tap = tap
            self.localInterconnect = localInterconnect
            self.gateCutMask = gateCutMask
            self.gateConductor = gateConductor
            self.contactCut = contactCut
            self.metalContactCut = metalContactCut
        }
    }

    public struct ContactRestackPolicy: Codable, Sendable, Hashable {
        public let activeContactViaDefinitionID: String
        public let metalContactViaDefinitionID: String
        public let gateCutMaskEnclosure: Double
        public let gatePadEnclosure: Double
        public let tapContactHorizontalEnclosure: Double
        public let tapImplantEnclosure: Double

        public init(
            activeContactViaDefinitionID: String,
            metalContactViaDefinitionID: String,
            gateCutMaskEnclosure: Double,
            gatePadEnclosure: Double,
            tapContactHorizontalEnclosure: Double,
            tapImplantEnclosure: Double
        ) {
            self.activeContactViaDefinitionID = activeContactViaDefinitionID
            self.metalContactViaDefinitionID = metalContactViaDefinitionID
            self.gateCutMaskEnclosure = gateCutMaskEnclosure
            self.gatePadEnclosure = gatePadEnclosure
            self.tapContactHorizontalEnclosure = tapContactHorizontalEnclosure
            self.tapImplantEnclosure = tapImplantEnclosure
        }
    }

    public let schemaVersion: Int
    public let profileID: String
    public let targetTechnologyResourceName: String
    public let sourceLayers: SourceLayers
    public let targetLayers: TargetLayers
    public let layerMap: [String: LayerReference]
    public let viaDefinitionMap: [String: String]
    public let contactRestackPolicy: ContactRestackPolicy

    public init(
        schemaVersion: Int,
        profileID: String,
        targetTechnologyResourceName: String,
        sourceLayers: SourceLayers,
        targetLayers: TargetLayers,
        layerMap: [String: LayerReference],
        viaDefinitionMap: [String: String],
        contactRestackPolicy: ContactRestackPolicy
    ) {
        self.schemaVersion = schemaVersion
        self.profileID = profileID
        self.targetTechnologyResourceName = targetTechnologyResourceName
        self.sourceLayers = sourceLayers
        self.targetLayers = targetLayers
        self.layerMap = layerMap
        self.viaDefinitionMap = viaDefinitionMap
        self.contactRestackPolicy = contactRestackPolicy
    }

    public static func load(from url: URL) throws -> LayoutTechnologyTranslationProfile {
        let data = try Data(contentsOf: url)
        let profile = try JSONDecoder().decode(LayoutTechnologyTranslationProfile.self, from: data)
        try profile.validate()
        return profile
    }

    public static func bundled(resourceName: String) throws -> LayoutTechnologyTranslationProfile {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw LayoutTechnologyTranslationProfileError.missingBundledResource(resourceName)
        }
        return try load(from: url)
    }

    public func validate() throws {
        guard schemaVersion == 1 else {
            throw LayoutTechnologyTranslationProfileValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        try Self.requireNonEmpty(profileID, field: "profileID")
        try Self.requireNonEmpty(targetTechnologyResourceName, field: "targetTechnologyResourceName")

        try Self.requireNonEmpty(sourceLayers.active, field: "sourceLayers.active")
        try Self.requireNonEmpty(sourceLayers.contact, field: "sourceLayers.contact")
        try Self.requireNonEmpty(sourceLayers.poly, field: "sourceLayers.poly")
        try Self.requireNonEmpty(sourceLayers.nImplant, field: "sourceLayers.nImplant")
        try Self.requireNonEmpty(sourceLayers.pImplant, field: "sourceLayers.pImplant")
        try Self.requireNonEmpty(sourceLayers.nWell, field: "sourceLayers.nWell")

        try Self.validate(targetLayers.diffusion, field: "targetLayers.diffusion")
        try Self.validate(targetLayers.tap, field: "targetLayers.tap")
        try Self.validate(targetLayers.localInterconnect, field: "targetLayers.localInterconnect")
        try Self.validate(targetLayers.gateCutMask, field: "targetLayers.gateCutMask")
        try Self.validate(targetLayers.gateConductor, field: "targetLayers.gateConductor")
        try Self.validate(targetLayers.contactCut, field: "targetLayers.contactCut")
        try Self.validate(targetLayers.metalContactCut, field: "targetLayers.metalContactCut")

        for (sourceLayer, targetLayer) in layerMap {
            try Self.requireNonEmpty(sourceLayer, field: "layerMap.key")
            try Self.validate(targetLayer, field: "layerMap.\(sourceLayer)")
        }
        for (sourceVia, targetVia) in viaDefinitionMap {
            try Self.requireNonEmpty(sourceVia, field: "viaDefinitionMap.key")
            try Self.requireNonEmpty(targetVia, field: "viaDefinitionMap.\(sourceVia)")
        }

        try Self.requireNonEmpty(
            contactRestackPolicy.activeContactViaDefinitionID,
            field: "contactRestackPolicy.activeContactViaDefinitionID"
        )
        try Self.requireNonEmpty(
            contactRestackPolicy.metalContactViaDefinitionID,
            field: "contactRestackPolicy.metalContactViaDefinitionID"
        )
        try Self.requireNonNegative(
            contactRestackPolicy.gateCutMaskEnclosure,
            field: "contactRestackPolicy.gateCutMaskEnclosure"
        )
        try Self.requireNonNegative(
            contactRestackPolicy.gatePadEnclosure,
            field: "contactRestackPolicy.gatePadEnclosure"
        )
        try Self.requireNonNegative(
            contactRestackPolicy.tapContactHorizontalEnclosure,
            field: "contactRestackPolicy.tapContactHorizontalEnclosure"
        )
        try Self.requireNonNegative(
            contactRestackPolicy.tapImplantEnclosure,
            field: "contactRestackPolicy.tapImplantEnclosure"
        )
    }

    private static func validate(_ reference: LayerReference, field: String) throws {
        try requireNonEmpty(reference.name, field: "\(field).name")
        try requireNonEmpty(reference.purpose, field: "\(field).purpose")
    }

    private static func requireNonEmpty(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LayoutTechnologyTranslationProfileValidationError.emptyField(field)
        }
    }

    private static func requireNonNegative(_ value: Double, field: String) throws {
        guard value >= 0 else {
            throw LayoutTechnologyTranslationProfileValidationError.negativeValue(field)
        }
    }
}
