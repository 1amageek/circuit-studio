import Foundation

public struct CMOSGateLibrary: Sendable, Hashable {
    public struct DeviceSizing: Sendable, Hashable, Codable {
        public let width: Double
        public let length: Double

        public init(width: Double, length: Double) {
            precondition(width > 0, "Device width must be positive.")
            precondition(length > 0, "Device length must be positive.")
            self.width = width
            self.length = length
        }
    }

    public let deviceSizing: DeviceSizing

    public init(deviceSizing: DeviceSizing) {
        self.deviceSizing = deviceSizing
    }

    public init(profile: StandardCellLayoutProfile) {
        self.init(deviceSizing: .init(
            width: profile.generatedCellLayout.deviceWidth,
            length: profile.generatedCellLayout.gateLength
        ))
    }

    public static let bundledDefault: CMOSGateLibrary = {
        do {
            return try CMOSGateLibrary(profile: StandardCellLayoutProfileCatalog.loadDefaultProfile())
        } catch {
            preconditionFailure("Bundled standard-cell layout profile is missing or invalid: \(error)")
        }
    }()

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
