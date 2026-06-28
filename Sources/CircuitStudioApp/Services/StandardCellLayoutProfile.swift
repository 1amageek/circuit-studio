import Foundation

public enum StandardCellLayoutProfileError: Error, Sendable, Hashable {
    case missingBundledResource(String)
}

public enum StandardCellLayoutProfileValidationError: Error, Sendable, Hashable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case emptyField(String)
    case nonPositiveValue(String)
    case negativeValue(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported standard-cell layout profile schema version: \(version)."
        case .emptyField(let field):
            return "Standard-cell layout profile field '\(field)' must not be empty."
        case .nonPositiveValue(let field):
            return "Standard-cell layout profile field '\(field)' must be greater than zero."
        case .negativeValue(let field):
            return "Standard-cell layout profile field '\(field)' must not be negative."
        }
    }
}

public struct StandardCellLayoutProfile: Codable, Sendable, Hashable {
    public enum LayerRole: String, Codable, Sendable, Hashable {
        case diffusion
        case nImplant
        case pImplant
        case nWell
        case gateConductor
        case localInterconnect
        case contactCut
        case localInterconnectToMetalContact
        case metal1
        case metal1ToMetal2Via
        case metal2
        case gateContactImplant
        case metal3
    }

    public enum DeviceKind: String, Codable, Sendable, Hashable {
        case nmos
        case pmos
    }

    public struct Layers: Codable, Sendable, Hashable {
        public let diffusion: LayoutTechnologyLayerReference
        public let nImplant: LayoutTechnologyLayerReference
        public let pImplant: LayoutTechnologyLayerReference
        public let nWell: LayoutTechnologyLayerReference
        public let gateConductor: LayoutTechnologyLayerReference
        public let localInterconnect: LayoutTechnologyLayerReference
        public let contactCut: LayoutTechnologyLayerReference
        public let localInterconnectToMetalContact: LayoutTechnologyLayerReference
        public let metal1: LayoutTechnologyLayerReference
        public let metal1ToMetal2Via: LayoutTechnologyLayerReference
        public let metal2: LayoutTechnologyLayerReference
        public let gateContactImplant: LayoutTechnologyLayerReference
        public let metal3: LayoutTechnologyLayerReference

        public init(
            diffusion: LayoutTechnologyLayerReference,
            nImplant: LayoutTechnologyLayerReference,
            pImplant: LayoutTechnologyLayerReference,
            nWell: LayoutTechnologyLayerReference,
            gateConductor: LayoutTechnologyLayerReference,
            localInterconnect: LayoutTechnologyLayerReference,
            contactCut: LayoutTechnologyLayerReference,
            localInterconnectToMetalContact: LayoutTechnologyLayerReference,
            metal1: LayoutTechnologyLayerReference,
            metal1ToMetal2Via: LayoutTechnologyLayerReference,
            metal2: LayoutTechnologyLayerReference,
            gateContactImplant: LayoutTechnologyLayerReference,
            metal3: LayoutTechnologyLayerReference
        ) {
            self.diffusion = diffusion
            self.nImplant = nImplant
            self.pImplant = pImplant
            self.nWell = nWell
            self.gateConductor = gateConductor
            self.localInterconnect = localInterconnect
            self.contactCut = contactCut
            self.localInterconnectToMetalContact = localInterconnectToMetalContact
            self.metal1 = metal1
            self.metal1ToMetal2Via = metal1ToMetal2Via
            self.metal2 = metal2
            self.gateContactImplant = gateContactImplant
            self.metal3 = metal3
        }
    }

    public struct DeviceModels: Codable, Sendable, Hashable {
        public let nmos: String
        public let pmos: String

        public init(nmos: String, pmos: String) {
            self.nmos = nmos
            self.pmos = pmos
        }
    }

    public struct Rect: Codable, Sendable, Hashable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public struct FixedCellShape: Codable, Sendable, Hashable {
        public let layer: LayerRole
        public let rect: Rect

        public init(layer: LayerRole, rect: Rect) {
            self.layer = layer
            self.rect = rect
        }
    }

    public struct FixedCellLabel: Codable, Sendable, Hashable {
        public let text: String
        public let layer: LayerRole
        public let x: Double
        public let y: Double

        public init(text: String, layer: LayerRole, x: Double, y: Double) {
            self.text = text
            self.layer = layer
            self.x = x
            self.y = y
        }
    }

    public struct FixedCellDevice: Codable, Sendable, Hashable {
        public let instanceName: String
        public let kind: DeviceKind
        public let drain: String
        public let gate: String
        public let source: String
        public let bulk: String
        public let width: Double
        public let length: Double

        public init(
            instanceName: String,
            kind: DeviceKind,
            drain: String,
            gate: String,
            source: String,
            bulk: String,
            width: Double,
            length: Double
        ) {
            self.instanceName = instanceName
            self.kind = kind
            self.drain = drain
            self.gate = gate
            self.source = source
            self.bulk = bulk
            self.width = width
            self.length = length
        }
    }

    public struct FixedCellLayout: Codable, Sendable, Hashable {
        public let defaultName: String
        public let ports: [String]
        public let comment: String
        public let shapes: [FixedCellShape]
        public let labels: [FixedCellLabel]
        public let devices: [FixedCellDevice]

        public init(
            defaultName: String,
            ports: [String],
            comment: String,
            shapes: [FixedCellShape],
            labels: [FixedCellLabel],
            devices: [FixedCellDevice]
        ) {
            self.defaultName = defaultName
            self.ports = ports
            self.comment = comment
            self.shapes = shapes
            self.labels = labels
            self.devices = devices
        }
    }

    public struct GeneratedCellLayout: Codable, Sendable, Hashable {
        public let fieldY: Double
        public let outputBusY: Double
        public let gateOriginX: Double
        public let gatePitch: Double
        public let gateLength: Double
        public let gateBottomY: Double
        public let gateHeight: Double
        public let gateLabelOffsetX: Double
        public let gateLabelY: Double
        public let diffusionBaseWidth: Double
        public let diffusionRightContactInset: Double
        public let firstContactX: Double
        public let nmosY: Double
        public let pmosBottomY: Double
        public let deviceWidth: Double
        public let activeContactYInset: Double
        public let implantMargin: Double
        public let contactSize: Double
        public let localInterconnectPadInset: Double
        public let localInterconnectPadSize: Double
        public let gateContactImplantSize: Double
        public let metalRiserWidth: Double
        public let outputViaSize: Double
        public let outputBusWidth: Double
        public let railMinimumHalfWidth: Double
        public let groundRailY: Double
        public let groundRailHeight: Double
        public let groundStubHeight: Double
        public let groundTapDiffusionY: Double
        public let groundTapImplantY: Double
        public let groundLabelY: Double
        public let powerStubY: Double
        public let powerStubHeight: Double
        public let powerRailY: Double
        public let powerRailHeight: Double
        public let powerTapDiffusionY: Double
        public let powerTapImplantY: Double
        public let powerTapContactY: Double
        public let powerLabelY: Double
        public let tapDiffusionSize: Double
        public let tapImplantSize: Double
        public let nWellOriginX: Double
        public let nWellBottomOffset: Double
        public let nWellHorizontalExtension: Double
        public let nWellTopY: Double

        public init(
            fieldY: Double,
            outputBusY: Double,
            gateOriginX: Double,
            gatePitch: Double,
            gateLength: Double,
            gateBottomY: Double,
            gateHeight: Double,
            gateLabelOffsetX: Double,
            gateLabelY: Double,
            diffusionBaseWidth: Double,
            diffusionRightContactInset: Double,
            firstContactX: Double,
            nmosY: Double,
            pmosBottomY: Double,
            deviceWidth: Double,
            activeContactYInset: Double,
            implantMargin: Double,
            contactSize: Double,
            localInterconnectPadInset: Double,
            localInterconnectPadSize: Double,
            gateContactImplantSize: Double,
            metalRiserWidth: Double,
            outputViaSize: Double,
            outputBusWidth: Double,
            railMinimumHalfWidth: Double,
            groundRailY: Double,
            groundRailHeight: Double,
            groundStubHeight: Double,
            groundTapDiffusionY: Double,
            groundTapImplantY: Double,
            groundLabelY: Double,
            powerStubY: Double,
            powerStubHeight: Double,
            powerRailY: Double,
            powerRailHeight: Double,
            powerTapDiffusionY: Double,
            powerTapImplantY: Double,
            powerTapContactY: Double,
            powerLabelY: Double,
            tapDiffusionSize: Double,
            tapImplantSize: Double,
            nWellOriginX: Double,
            nWellBottomOffset: Double,
            nWellHorizontalExtension: Double,
            nWellTopY: Double
        ) {
            self.fieldY = fieldY
            self.outputBusY = outputBusY
            self.gateOriginX = gateOriginX
            self.gatePitch = gatePitch
            self.gateLength = gateLength
            self.gateBottomY = gateBottomY
            self.gateHeight = gateHeight
            self.gateLabelOffsetX = gateLabelOffsetX
            self.gateLabelY = gateLabelY
            self.diffusionBaseWidth = diffusionBaseWidth
            self.diffusionRightContactInset = diffusionRightContactInset
            self.firstContactX = firstContactX
            self.nmosY = nmosY
            self.pmosBottomY = pmosBottomY
            self.deviceWidth = deviceWidth
            self.activeContactYInset = activeContactYInset
            self.implantMargin = implantMargin
            self.contactSize = contactSize
            self.localInterconnectPadInset = localInterconnectPadInset
            self.localInterconnectPadSize = localInterconnectPadSize
            self.gateContactImplantSize = gateContactImplantSize
            self.metalRiserWidth = metalRiserWidth
            self.outputViaSize = outputViaSize
            self.outputBusWidth = outputBusWidth
            self.railMinimumHalfWidth = railMinimumHalfWidth
            self.groundRailY = groundRailY
            self.groundRailHeight = groundRailHeight
            self.groundStubHeight = groundStubHeight
            self.groundTapDiffusionY = groundTapDiffusionY
            self.groundTapImplantY = groundTapImplantY
            self.groundLabelY = groundLabelY
            self.powerStubY = powerStubY
            self.powerStubHeight = powerStubHeight
            self.powerRailY = powerRailY
            self.powerRailHeight = powerRailHeight
            self.powerTapDiffusionY = powerTapDiffusionY
            self.powerTapImplantY = powerTapImplantY
            self.powerTapContactY = powerTapContactY
            self.powerLabelY = powerLabelY
            self.tapDiffusionSize = tapDiffusionSize
            self.tapImplantSize = tapImplantSize
            self.nWellOriginX = nWellOriginX
            self.nWellBottomOffset = nWellBottomOffset
            self.nWellHorizontalExtension = nWellHorizontalExtension
            self.nWellTopY = nWellTopY
        }
    }

    public struct CircuitRouting: Codable, Sendable, Hashable {
        public let cellGap: Double
        public let firstSignalTrackY: Double
        public let signalTrackAccessPadWidth: Double
        public let signalTrackRuleMargin: Double
        public let antennaTieBaseY: Double
        public let signalTrackSpacingLayer: LayerRole
        public let constantGroundStrapTopY: Double
        public let constantPowerStrapTopY: Double
        public let barycenterIterations: Int

        public init(
            cellGap: Double,
            firstSignalTrackY: Double,
            signalTrackAccessPadWidth: Double,
            signalTrackRuleMargin: Double,
            antennaTieBaseY: Double,
            signalTrackSpacingLayer: LayerRole,
            constantGroundStrapTopY: Double,
            constantPowerStrapTopY: Double,
            barycenterIterations: Int
        ) {
            self.cellGap = cellGap
            self.firstSignalTrackY = firstSignalTrackY
            self.signalTrackAccessPadWidth = signalTrackAccessPadWidth
            self.signalTrackRuleMargin = signalTrackRuleMargin
            self.antennaTieBaseY = antennaTieBaseY
            self.signalTrackSpacingLayer = signalTrackSpacingLayer
            self.constantGroundStrapTopY = constantGroundStrapTopY
            self.constantPowerStrapTopY = constantPowerStrapTopY
            self.barycenterIterations = barycenterIterations
        }
    }

    public struct InverterLayout: Codable, Sendable, Hashable {
        public let defaultDeviceWidth: Double
        public let minimumDeviceWidth: Double
        public let gateLength: Double
        public let pmosRowGap: Double
        public let wellTapGap: Double
        public let activeLength: Double
        public let activeContactSize: Double
        public let sourceContactX: Double
        public let drainContactX: Double
        public let activeContactYInset: Double
        public let nImplantOriginX: Double
        public let nImplantOriginY: Double
        public let pImplantOriginX: Double
        public let implantHorizontalMargin: Double
        public let implantVerticalMargin: Double
        public let nWellOriginX: Double
        public let nWellBottomMargin: Double
        public let nWellWidth: Double
        public let nWellTopMargin: Double
        public let gateX: Double
        public let gateBottomY: Double
        public let gateTopMargin: Double
        public let outputLocalInterconnect: Rect
        public let outputTopYOffset: Double
        public let substrateTapDiffusion: Rect
        public let substrateTapImplant: Rect
        public let substrateTapContact: Rect
        public let substrateTapRail: Rect
        public let substrateTapRailTopY: Double
        public let wellTapDiffusionX: Double
        public let wellTapDiffusionSize: Double
        public let wellTapImplantX: Double
        public let wellTapImplantBottomOffset: Double
        public let wellTapImplantSize: Double
        public let wellTapContactX: Double
        public let wellTapContactYOffset: Double
        public let wellTapRailX: Double
        public let wellTapRailBottomYOffset: Double
        public let wellTapRailWidth: Double
        public let wellTapRailTopYOffset: Double
        public let inputLabelX: Double
        public let inputLabelYOffset: Double
        public let outputLabelX: Double
        public let outputLabelY: Double
        public let powerLabelX: Double
        public let powerLabelYOffset: Double
        public let groundLabelX: Double
        public let groundLabelY: Double

        public init(
            defaultDeviceWidth: Double,
            minimumDeviceWidth: Double,
            gateLength: Double,
            pmosRowGap: Double,
            wellTapGap: Double,
            activeLength: Double,
            activeContactSize: Double,
            sourceContactX: Double,
            drainContactX: Double,
            activeContactYInset: Double,
            nImplantOriginX: Double,
            nImplantOriginY: Double,
            pImplantOriginX: Double,
            implantHorizontalMargin: Double,
            implantVerticalMargin: Double,
            nWellOriginX: Double,
            nWellBottomMargin: Double,
            nWellWidth: Double,
            nWellTopMargin: Double,
            gateX: Double,
            gateBottomY: Double,
            gateTopMargin: Double,
            outputLocalInterconnect: Rect,
            outputTopYOffset: Double,
            substrateTapDiffusion: Rect,
            substrateTapImplant: Rect,
            substrateTapContact: Rect,
            substrateTapRail: Rect,
            substrateTapRailTopY: Double,
            wellTapDiffusionX: Double,
            wellTapDiffusionSize: Double,
            wellTapImplantX: Double,
            wellTapImplantBottomOffset: Double,
            wellTapImplantSize: Double,
            wellTapContactX: Double,
            wellTapContactYOffset: Double,
            wellTapRailX: Double,
            wellTapRailBottomYOffset: Double,
            wellTapRailWidth: Double,
            wellTapRailTopYOffset: Double,
            inputLabelX: Double,
            inputLabelYOffset: Double,
            outputLabelX: Double,
            outputLabelY: Double,
            powerLabelX: Double,
            powerLabelYOffset: Double,
            groundLabelX: Double,
            groundLabelY: Double
        ) {
            self.defaultDeviceWidth = defaultDeviceWidth
            self.minimumDeviceWidth = minimumDeviceWidth
            self.gateLength = gateLength
            self.pmosRowGap = pmosRowGap
            self.wellTapGap = wellTapGap
            self.activeLength = activeLength
            self.activeContactSize = activeContactSize
            self.sourceContactX = sourceContactX
            self.drainContactX = drainContactX
            self.activeContactYInset = activeContactYInset
            self.nImplantOriginX = nImplantOriginX
            self.nImplantOriginY = nImplantOriginY
            self.pImplantOriginX = pImplantOriginX
            self.implantHorizontalMargin = implantHorizontalMargin
            self.implantVerticalMargin = implantVerticalMargin
            self.nWellOriginX = nWellOriginX
            self.nWellBottomMargin = nWellBottomMargin
            self.nWellWidth = nWellWidth
            self.nWellTopMargin = nWellTopMargin
            self.gateX = gateX
            self.gateBottomY = gateBottomY
            self.gateTopMargin = gateTopMargin
            self.outputLocalInterconnect = outputLocalInterconnect
            self.outputTopYOffset = outputTopYOffset
            self.substrateTapDiffusion = substrateTapDiffusion
            self.substrateTapImplant = substrateTapImplant
            self.substrateTapContact = substrateTapContact
            self.substrateTapRail = substrateTapRail
            self.substrateTapRailTopY = substrateTapRailTopY
            self.wellTapDiffusionX = wellTapDiffusionX
            self.wellTapDiffusionSize = wellTapDiffusionSize
            self.wellTapImplantX = wellTapImplantX
            self.wellTapImplantBottomOffset = wellTapImplantBottomOffset
            self.wellTapImplantSize = wellTapImplantSize
            self.wellTapContactX = wellTapContactX
            self.wellTapContactYOffset = wellTapContactYOffset
            self.wellTapRailX = wellTapRailX
            self.wellTapRailBottomYOffset = wellTapRailBottomYOffset
            self.wellTapRailWidth = wellTapRailWidth
            self.wellTapRailTopYOffset = wellTapRailTopYOffset
            self.inputLabelX = inputLabelX
            self.inputLabelYOffset = inputLabelYOffset
            self.outputLabelX = outputLabelX
            self.outputLabelY = outputLabelY
            self.powerLabelX = powerLabelX
            self.powerLabelYOffset = powerLabelYOffset
            self.groundLabelX = groundLabelX
            self.groundLabelY = groundLabelY
        }
    }

    public let schemaVersion: Int
    public let profileID: String
    public let targetTechnologyResourceName: String
    public let manufacturingGridMicrons: Double
    public let layers: Layers
    public let deviceModels: DeviceModels
    public let inverter: InverterLayout
    public let generatedCellLayout: GeneratedCellLayout
    public let circuitRouting: CircuitRouting
    public let fixedCells: [String: FixedCellLayout]

    public init(
        schemaVersion: Int,
        profileID: String,
        targetTechnologyResourceName: String,
        manufacturingGridMicrons: Double,
        layers: Layers,
        deviceModels: DeviceModels,
        inverter: InverterLayout,
        generatedCellLayout: GeneratedCellLayout,
        circuitRouting: CircuitRouting,
        fixedCells: [String: FixedCellLayout] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.profileID = profileID
        self.targetTechnologyResourceName = targetTechnologyResourceName
        self.manufacturingGridMicrons = manufacturingGridMicrons
        self.layers = layers
        self.deviceModels = deviceModels
        self.inverter = inverter
        self.generatedCellLayout = generatedCellLayout
        self.circuitRouting = circuitRouting
        self.fixedCells = fixedCells
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case profileID
        case targetTechnologyResourceName
        case manufacturingGridMicrons
        case layers
        case deviceModels
        case inverter
        case generatedCellLayout
        case circuitRouting
        case fixedCells
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.profileID = try container.decode(String.self, forKey: .profileID)
        self.targetTechnologyResourceName = try container.decode(String.self, forKey: .targetTechnologyResourceName)
        self.manufacturingGridMicrons = try container.decode(Double.self, forKey: .manufacturingGridMicrons)
        self.layers = try container.decode(Layers.self, forKey: .layers)
        self.deviceModels = try container.decode(DeviceModels.self, forKey: .deviceModels)
        self.inverter = try container.decode(InverterLayout.self, forKey: .inverter)
        self.generatedCellLayout = try container.decode(GeneratedCellLayout.self, forKey: .generatedCellLayout)
        self.circuitRouting = try container.decode(CircuitRouting.self, forKey: .circuitRouting)
        self.fixedCells = try container.decodeIfPresent(
            [String: FixedCellLayout].self,
            forKey: .fixedCells
        ) ?? [:]
    }

    public static func load(from url: URL) throws -> StandardCellLayoutProfile {
        let data = try Data(contentsOf: url)
        let profile = try JSONDecoder().decode(StandardCellLayoutProfile.self, from: data)
        try profile.validate()
        return profile
    }

    public static func bundled(resourceName: String) throws -> StandardCellLayoutProfile {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw StandardCellLayoutProfileError.missingBundledResource(resourceName)
        }
        return try load(from: url)
    }

    public func validate() throws {
        guard schemaVersion == 1 else {
            throw StandardCellLayoutProfileValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        try Self.requireNonEmpty(profileID, field: "profileID")
        try Self.requireNonEmpty(targetTechnologyResourceName, field: "targetTechnologyResourceName")
        try Self.requirePositive(manufacturingGridMicrons, field: "manufacturingGridMicrons")
        try Self.validate(layers.diffusion, field: "layers.diffusion")
        try Self.validate(layers.nImplant, field: "layers.nImplant")
        try Self.validate(layers.pImplant, field: "layers.pImplant")
        try Self.validate(layers.nWell, field: "layers.nWell")
        try Self.validate(layers.gateConductor, field: "layers.gateConductor")
        try Self.validate(layers.localInterconnect, field: "layers.localInterconnect")
        try Self.validate(layers.contactCut, field: "layers.contactCut")
        try Self.validate(layers.localInterconnectToMetalContact, field: "layers.localInterconnectToMetalContact")
        try Self.validate(layers.metal1, field: "layers.metal1")
        try Self.validate(layers.metal1ToMetal2Via, field: "layers.metal1ToMetal2Via")
        try Self.validate(layers.metal2, field: "layers.metal2")
        try Self.validate(layers.gateContactImplant, field: "layers.gateContactImplant")
        try Self.validate(layers.metal3, field: "layers.metal3")
        try Self.requireNonEmpty(deviceModels.nmos, field: "deviceModels.nmos")
        try Self.requireNonEmpty(deviceModels.pmos, field: "deviceModels.pmos")

        try Self.requirePositive(inverter.defaultDeviceWidth, field: "inverter.defaultDeviceWidth")
        try Self.requirePositive(inverter.minimumDeviceWidth, field: "inverter.minimumDeviceWidth")
        try Self.requirePositive(inverter.gateLength, field: "inverter.gateLength")
        try Self.requireNonNegative(inverter.pmosRowGap, field: "inverter.pmosRowGap")
        try Self.requireNonNegative(inverter.wellTapGap, field: "inverter.wellTapGap")
        try Self.requirePositive(inverter.activeLength, field: "inverter.activeLength")
        try Self.requirePositive(inverter.activeContactSize, field: "inverter.activeContactSize")
        try Self.validate(inverter.outputLocalInterconnect, field: "inverter.outputLocalInterconnect")
        try Self.validate(inverter.substrateTapDiffusion, field: "inverter.substrateTapDiffusion")
        try Self.validate(inverter.substrateTapImplant, field: "inverter.substrateTapImplant")
        try Self.validate(inverter.substrateTapContact, field: "inverter.substrateTapContact")
        try Self.validate(inverter.substrateTapRail, field: "inverter.substrateTapRail")
        try Self.requirePositive(inverter.wellTapDiffusionSize, field: "inverter.wellTapDiffusionSize")
        try Self.requirePositive(inverter.wellTapImplantSize, field: "inverter.wellTapImplantSize")
        try Self.requirePositive(inverter.wellTapRailWidth, field: "inverter.wellTapRailWidth")

        try Self.validate(generatedCellLayout, field: "generatedCellLayout")
        try Self.validate(circuitRouting, field: "circuitRouting")

        for (cellID, cell) in fixedCells {
            try Self.requireNonEmpty(cellID, field: "fixedCells.key")
            try Self.validate(cell, field: "fixedCells.\(cellID)")
        }
    }

    public func layerReference(for role: LayerRole) -> LayoutTechnologyLayerReference {
        switch role {
        case .diffusion:
            return layers.diffusion
        case .nImplant:
            return layers.nImplant
        case .pImplant:
            return layers.pImplant
        case .nWell:
            return layers.nWell
        case .gateConductor:
            return layers.gateConductor
        case .localInterconnect:
            return layers.localInterconnect
        case .contactCut:
            return layers.contactCut
        case .localInterconnectToMetalContact:
            return layers.localInterconnectToMetalContact
        case .metal1:
            return layers.metal1
        case .metal1ToMetal2Via:
            return layers.metal1ToMetal2Via
        case .metal2:
            return layers.metal2
        case .gateContactImplant:
            return layers.gateContactImplant
        case .metal3:
            return layers.metal3
        }
    }

    private static func validate(_ reference: LayoutTechnologyLayerReference, field: String) throws {
        try requireNonEmpty(reference.name, field: "\(field).name")
        try requireNonEmpty(reference.purpose, field: "\(field).purpose")
    }

    private static func validate(_ rect: Rect, field: String) throws {
        try requirePositive(rect.width, field: "\(field).width")
        try requireNonNegative(rect.height, field: "\(field).height")
    }

    private static func validateFixedShape(_ rect: Rect, field: String) throws {
        try requirePositive(rect.width, field: "\(field).width")
        try requirePositive(rect.height, field: "\(field).height")
    }

    private static func validate(_ layout: GeneratedCellLayout, field: String) throws {
        try requireNonNegative(layout.fieldY, field: "\(field).fieldY")
        try requirePositive(layout.outputBusY, field: "\(field).outputBusY")
        try requireNonNegative(layout.gateOriginX, field: "\(field).gateOriginX")
        try requirePositive(layout.gatePitch, field: "\(field).gatePitch")
        try requirePositive(layout.gateLength, field: "\(field).gateLength")
        try requirePositive(layout.gateHeight, field: "\(field).gateHeight")
        try requirePositive(layout.diffusionBaseWidth, field: "\(field).diffusionBaseWidth")
        try requirePositive(layout.diffusionRightContactInset, field: "\(field).diffusionRightContactInset")
        try requireNonNegative(layout.firstContactX, field: "\(field).firstContactX")
        try requireNonNegative(layout.nmosY, field: "\(field).nmosY")
        try requirePositive(layout.pmosBottomY, field: "\(field).pmosBottomY")
        try requirePositive(layout.deviceWidth, field: "\(field).deviceWidth")
        try requireNonNegative(layout.activeContactYInset, field: "\(field).activeContactYInset")
        try requireNonNegative(layout.implantMargin, field: "\(field).implantMargin")
        try requirePositive(layout.contactSize, field: "\(field).contactSize")
        try requireNonNegative(layout.localInterconnectPadInset, field: "\(field).localInterconnectPadInset")
        try requirePositive(layout.localInterconnectPadSize, field: "\(field).localInterconnectPadSize")
        try requirePositive(layout.gateContactImplantSize, field: "\(field).gateContactImplantSize")
        try requirePositive(layout.metalRiserWidth, field: "\(field).metalRiserWidth")
        try requirePositive(layout.outputViaSize, field: "\(field).outputViaSize")
        try requirePositive(layout.outputBusWidth, field: "\(field).outputBusWidth")
        try requirePositive(layout.railMinimumHalfWidth, field: "\(field).railMinimumHalfWidth")
        try requirePositive(layout.groundRailHeight, field: "\(field).groundRailHeight")
        try requirePositive(layout.groundStubHeight, field: "\(field).groundStubHeight")
        try requirePositive(layout.powerStubHeight, field: "\(field).powerStubHeight")
        try requirePositive(layout.powerRailY, field: "\(field).powerRailY")
        try requirePositive(layout.powerRailHeight, field: "\(field).powerRailHeight")
        try requirePositive(layout.tapDiffusionSize, field: "\(field).tapDiffusionSize")
        try requirePositive(layout.tapImplantSize, field: "\(field).tapImplantSize")
        try requireNonNegative(layout.nWellBottomOffset, field: "\(field).nWellBottomOffset")
        try requirePositive(layout.nWellHorizontalExtension, field: "\(field).nWellHorizontalExtension")
        try requirePositive(layout.nWellTopY, field: "\(field).nWellTopY")
    }

    private static func validate(_ routing: CircuitRouting, field: String) throws {
        try requirePositive(routing.cellGap, field: "\(field).cellGap")
        try requirePositive(routing.firstSignalTrackY, field: "\(field).firstSignalTrackY")
        try requirePositive(routing.signalTrackAccessPadWidth, field: "\(field).signalTrackAccessPadWidth")
        try requireNonNegative(routing.signalTrackRuleMargin, field: "\(field).signalTrackRuleMargin")
        try requirePositive(routing.constantPowerStrapTopY, field: "\(field).constantPowerStrapTopY")
        guard routing.barycenterIterations >= 0 else {
            throw StandardCellLayoutProfileValidationError.negativeValue("\(field).barycenterIterations")
        }
    }

    private static func validate(_ cell: FixedCellLayout, field: String) throws {
        try requireNonEmpty(cell.defaultName, field: "\(field).defaultName")
        guard !cell.ports.isEmpty else {
            throw StandardCellLayoutProfileValidationError.emptyField("\(field).ports")
        }
        try requireNonEmpty(cell.comment, field: "\(field).comment")
        guard !cell.shapes.isEmpty else {
            throw StandardCellLayoutProfileValidationError.emptyField("\(field).shapes")
        }
        guard !cell.devices.isEmpty else {
            throw StandardCellLayoutProfileValidationError.emptyField("\(field).devices")
        }
        for (index, port) in cell.ports.enumerated() {
            try requireNonEmpty(port, field: "\(field).ports[\(index)]")
        }
        for (index, shape) in cell.shapes.enumerated() {
            try validateFixedShape(shape.rect, field: "\(field).shapes[\(index)].rect")
        }
        for (index, label) in cell.labels.enumerated() {
            try requireNonEmpty(label.text, field: "\(field).labels[\(index)].text")
        }
        for (index, device) in cell.devices.enumerated() {
            try requireNonEmpty(device.instanceName, field: "\(field).devices[\(index)].instanceName")
            try requireNonEmpty(device.drain, field: "\(field).devices[\(index)].drain")
            try requireNonEmpty(device.gate, field: "\(field).devices[\(index)].gate")
            try requireNonEmpty(device.source, field: "\(field).devices[\(index)].source")
            try requireNonEmpty(device.bulk, field: "\(field).devices[\(index)].bulk")
            try requirePositive(device.width, field: "\(field).devices[\(index)].width")
            try requirePositive(device.length, field: "\(field).devices[\(index)].length")
        }
    }

    private static func requireNonEmpty(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StandardCellLayoutProfileValidationError.emptyField(field)
        }
    }

    private static func requirePositive(_ value: Double, field: String) throws {
        guard value > 0 else {
            throw StandardCellLayoutProfileValidationError.nonPositiveValue(field)
        }
    }

    private static func requireNonNegative(_ value: Double, field: String) throws {
        guard value >= 0 else {
            throw StandardCellLayoutProfileValidationError.negativeValue(field)
        }
    }
}
