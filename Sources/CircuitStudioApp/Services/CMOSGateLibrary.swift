import Foundation

public struct CMOSGateLibrary: Sendable, Hashable {
    public struct DeviceSizing: Sendable, Hashable, Codable {
        public enum ValidationError: Error, LocalizedError, Equatable, Sendable {
            case nonPositiveWidth(Double)
            case nonPositiveLength(Double)

            public var errorDescription: String? {
                switch self {
                case .nonPositiveWidth(let width):
                    return "Device width must be positive: \(width)."
                case .nonPositiveLength(let length):
                    return "Device length must be positive: \(length)."
                }
            }
        }

        public let width: Double
        public let length: Double

        public init(width: Double, length: Double) throws {
            guard width > 0 else {
                throw ValidationError.nonPositiveWidth(width)
            }
            guard length > 0 else {
                throw ValidationError.nonPositiveLength(length)
            }
            self.width = width
            self.length = length
        }

        private enum CodingKeys: String, CodingKey {
            case width
            case length
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let width = try container.decode(Double.self, forKey: .width)
            let length = try container.decode(Double.self, forKey: .length)
            try self.init(width: width, length: length)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(width, forKey: .width)
            try container.encode(length, forKey: .length)
        }
    }

    public let deviceSizing: DeviceSizing

    public init(deviceSizing: DeviceSizing) {
        self.deviceSizing = deviceSizing
    }

    public init(profile: StandardCellLayoutProfile) throws {
        self.init(deviceSizing: try .init(
            width: profile.generatedCellLayout.deviceWidth,
            length: profile.generatedCellLayout.gateLength
        ))
    }

    public static func loadBundledDefault() throws -> CMOSGateLibrary {
        try CMOSGateLibrary(profile: StandardCellLayoutProfileCatalog.loadDefaultProfile())
    }

    public func inverter(
        name: String = "inverter",
        input: String = "A",
        output: String = "Y"
    ) -> CMOSGateNetlist {
        CMOSGateNetlist.inverter(name: name, input: input, output: output, deviceSizing: deviceSizing)
    }

    public func nand(
        name: String,
        inputs: [String],
        output: String = "Y"
    ) -> CMOSGateNetlist {
        CMOSGateNetlist.nand(name: name, inputs: inputs, output: output, deviceSizing: deviceSizing)
    }

    public func nor(
        name: String,
        inputs: [String],
        output: String = "Y"
    ) -> CMOSGateNetlist {
        CMOSGateNetlist.nor(name: name, inputs: inputs, output: output, deviceSizing: deviceSizing)
    }
}
