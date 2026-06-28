import Foundation

public struct LVSVerificationReport: Sendable, Hashable {
    public struct Terminal: Sendable, Hashable {
        public let componentName: String
        public let pinName: String

        public init(componentName: String, pinName: String) {
            self.componentName = componentName
            self.pinName = pinName
        }
    }

    public struct PhysicalShort: Sendable, Hashable {
        public let netNames: [String]
        public let terminals: [Terminal]

        public init(netNames: [String], terminals: [Terminal]) {
            self.netNames = netNames
            self.terminals = terminals
        }
    }

    public struct PhysicalOpen: Sendable, Hashable {
        public let netName: String
        public let terminals: [Terminal]
        public let physicalNetCount: Int

        public init(netName: String, terminals: [Terminal], physicalNetCount: Int) {
            self.netName = netName
            self.terminals = terminals
            self.physicalNetCount = physicalNetCount
        }
    }

    public struct TerminalMismatch: Sendable, Hashable {
        public let terminal: Terminal
        public let expectedNetName: String
        public let actualNetNames: [String]

        public init(terminal: Terminal, expectedNetName: String, actualNetNames: [String]) {
            self.terminal = terminal
            self.expectedNetName = expectedNetName
            self.actualNetNames = actualNetNames
        }
    }

    public struct DeviceParameterMismatch: Sendable, Hashable {
        public let componentName: String
        public let parameterName: String
        public let expectedValue: Double
        public let actualValue: Double
        public let tolerance: Double

        public init(
            componentName: String,
            parameterName: String,
            expectedValue: Double,
            actualValue: Double,
            tolerance: Double
        ) {
            self.componentName = componentName
            self.parameterName = parameterName
            self.expectedValue = expectedValue
            self.actualValue = actualValue
            self.tolerance = tolerance
        }
    }

    public let schematicHashMatches: Bool
    public let missingLayoutInstances: [String]
    public let extraLayoutInstances: [String]
    public let missingLayoutNets: [String]
    public let extraLayoutNets: [String]
    public let danglingMappedInstanceIDs: [UUID]
    public let danglingMappedNetIDs: [UUID]
    public let physicalShorts: [PhysicalShort]
    public let physicalOpens: [PhysicalOpen]
    public let unconnectedLayoutPins: [Terminal]
    public let terminalMismatches: [TerminalMismatch]
    public let missingExternalLayoutPorts: [String]
    public let invalidLayoutTerminals: [Terminal]
    public let duplicateLayoutTerminals: [Terminal]
    public let deviceParameterMismatches: [DeviceParameterMismatch]
    public let duplicateLayoutDevices: [String]
    public let layoutTopologyErrors: [String]
    public let connectivityExtractionSkipped: Bool
    public let skippedComponents: [String]

    public init(
        schematicHashMatches: Bool,
        missingLayoutInstances: [String],
        extraLayoutInstances: [String] = [],
        missingLayoutNets: [String],
        extraLayoutNets: [String],
        danglingMappedInstanceIDs: [UUID] = [],
        danglingMappedNetIDs: [UUID] = [],
        physicalShorts: [PhysicalShort] = [],
        physicalOpens: [PhysicalOpen] = [],
        unconnectedLayoutPins: [Terminal] = [],
        terminalMismatches: [TerminalMismatch] = [],
        missingExternalLayoutPorts: [String] = [],
        invalidLayoutTerminals: [Terminal] = [],
        duplicateLayoutTerminals: [Terminal] = [],
        deviceParameterMismatches: [DeviceParameterMismatch] = [],
        duplicateLayoutDevices: [String] = [],
        layoutTopologyErrors: [String] = [],
        connectivityExtractionSkipped: Bool = false,
        skippedComponents: [String]
    ) {
        self.schematicHashMatches = schematicHashMatches
        self.missingLayoutInstances = missingLayoutInstances
        self.extraLayoutInstances = extraLayoutInstances
        self.missingLayoutNets = missingLayoutNets
        self.extraLayoutNets = extraLayoutNets
        self.danglingMappedInstanceIDs = danglingMappedInstanceIDs
        self.danglingMappedNetIDs = danglingMappedNetIDs
        self.physicalShorts = physicalShorts
        self.physicalOpens = physicalOpens
        self.unconnectedLayoutPins = unconnectedLayoutPins
        self.terminalMismatches = terminalMismatches
        self.missingExternalLayoutPorts = missingExternalLayoutPorts
        self.invalidLayoutTerminals = invalidLayoutTerminals
        self.duplicateLayoutTerminals = duplicateLayoutTerminals
        self.deviceParameterMismatches = deviceParameterMismatches
        self.duplicateLayoutDevices = duplicateLayoutDevices
        self.layoutTopologyErrors = layoutTopologyErrors
        self.connectivityExtractionSkipped = connectivityExtractionSkipped
        self.skippedComponents = skippedComponents
    }

    public var passed: Bool {
        schematicHashMatches
            && missingLayoutInstances.isEmpty
            && extraLayoutInstances.isEmpty
            && missingLayoutNets.isEmpty
            && extraLayoutNets.isEmpty
            && danglingMappedInstanceIDs.isEmpty
            && danglingMappedNetIDs.isEmpty
            && physicalShorts.isEmpty
            && physicalOpens.isEmpty
            && unconnectedLayoutPins.isEmpty
            && terminalMismatches.isEmpty
            && missingExternalLayoutPorts.isEmpty
            && invalidLayoutTerminals.isEmpty
            && duplicateLayoutTerminals.isEmpty
            && deviceParameterMismatches.isEmpty
            && duplicateLayoutDevices.isEmpty
            && layoutTopologyErrors.isEmpty
            && !connectivityExtractionSkipped
    }
}
