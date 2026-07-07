import Foundation

/// A transistor-level netlist for a static CMOS complementary gate: topology plus explicit
/// device sizing. Technology-specific defaults come from `CMOSGateLibrary`, not this type.
///
/// Restricted to the static-CMOS series/parallel class (inverter, NANDk, NORk): the NMOS
/// pull-down and PMOS pull-up are duals, one a series chain and the other a parallel set
/// (the inverter is the degenerate single-device case).
public struct CMOSGateNetlist: Sendable, Hashable, Codable, Identifiable {

    public var id: String { name }

    public enum DeviceKind: String, Sendable, Hashable, Codable { case nmos, pmos }

    public struct Device: Sendable, Hashable, Codable {
        public let name: String
        public let kind: DeviceKind
        public let gate: String
        public let source: String
        public let drain: String
        public let width: Double
        public let length: Double

        public init(name: String, kind: DeviceKind, gate: String, source: String, drain: String,
                    width: Double, length: Double) {
            self.name = name
            self.kind = kind
            self.gate = gate
            self.source = source
            self.drain = drain
            self.width = width
            self.length = length
        }

        public init(
            name: String,
            kind: DeviceKind,
            gate: String,
            source: String,
            drain: String,
            sizing: CMOSGateLibrary.DeviceSizing
        ) {
            self.init(
                name: name,
                kind: kind,
                gate: gate,
                source: source,
                drain: drain,
                width: sizing.width,
                length: sizing.length
            )
        }
    }

    public let name: String
    public let devices: [Device]
    public let vpwr: String
    public let vgnd: String
    public let output: String

    public init(name: String, devices: [Device], vpwr: String = "VPWR", vgnd: String = "VGND", output: String) {
        self.name = name
        self.devices = devices
        self.vpwr = vpwr
        self.vgnd = vgnd
        self.output = output
    }

    public var nmos: [Device] { devices.filter { $0.kind == .nmos } }
    public var pmos: [Device] { devices.filter { $0.kind == .pmos } }

    /// The same gate at a different drive strength: every transistor width is scaled by
    /// `widthFactor` (length unchanged), giving lower output resistance (less delay per
    /// load) at the cost of more input capacitance. `name` becomes the library key for the
    /// sized variant (e.g. "inv_x2"). Used by the timing-driven sizing loop.
    public func scaled(widthFactor: Double, name: String) -> CMOSGateNetlist {
        let sized = devices.map {
            Device(name: $0.name, kind: $0.kind, gate: $0.gate, source: $0.source,
                   drain: $0.drain, width: $0.width * widthFactor, length: $0.length)
        }
        return CMOSGateNetlist(name: name, devices: sized, vpwr: vpwr, vgnd: vgnd, output: output)
    }

    // MARK: - Standard library cells

    /// A CMOS inverter: Y = NOT(A).
    public static func inverter(
        name: String = "inverter",
        input: String = "A",
        output: String = "Y"
    ) throws -> CMOSGateNetlist {
        try CMOSGateLibrary.loadBundledDefault().inverter(name: name, input: input, output: output)
    }

    public static func inverter(
        name: String = "inverter",
        input: String = "A",
        output: String = "Y",
        deviceSizing: CMOSGateLibrary.DeviceSizing
    ) -> CMOSGateNetlist {
        CMOSGateNetlist(name: name, devices: [
            Device(name: "MP0", kind: .pmos, gate: input, source: "VPWR", drain: output, sizing: deviceSizing),
            Device(name: "MN0", kind: .nmos, gate: input, source: "VGND", drain: output, sizing: deviceSizing),
        ], output: output)
    }

    /// A CMOS NAND with `inputs.count` inputs: series NMOS pull-down, parallel PMOS
    /// pull-up. Y = NOT(A and B and ...).
    public static func nand(
        name: String,
        inputs: [String],
        output: String = "Y"
    ) throws -> CMOSGateNetlist {
        try CMOSGateLibrary.loadBundledDefault().nand(name: name, inputs: inputs, output: output)
    }

    public static func nand(
        name: String,
        inputs: [String],
        output: String = "Y",
        deviceSizing: CMOSGateLibrary.DeviceSizing
    ) -> CMOSGateNetlist {
        var devices: [Device] = []
        // Parallel PMOS: each input's PMOS ties VPWR -> output.
        for (i, g) in inputs.enumerated() {
            devices.append(Device(name: "MP\(i)", kind: .pmos, gate: g, source: "VPWR", drain: output, sizing: deviceSizing))
        }
        // Series NMOS chain: output - g0 - n1 - g1 - n2 - ... - VGND.
        for (i, g) in inputs.enumerated() {
            let s = i == 0 ? output : "n\(i)"
            let d = i == inputs.count - 1 ? "VGND" : "n\(i + 1)"
            devices.append(Device(name: "MN\(i)", kind: .nmos, gate: g, source: s, drain: d, sizing: deviceSizing))
        }
        return CMOSGateNetlist(name: name, devices: devices, output: output)
    }

    /// A CMOS NOR with `inputs.count` inputs: parallel NMOS pull-down, series PMOS
    /// pull-up. Y = NOT(A or B or ...).
    public static func nor(
        name: String,
        inputs: [String],
        output: String = "Y"
    ) throws -> CMOSGateNetlist {
        try CMOSGateLibrary.loadBundledDefault().nor(name: name, inputs: inputs, output: output)
    }

    public static func nor(
        name: String,
        inputs: [String],
        output: String = "Y",
        deviceSizing: CMOSGateLibrary.DeviceSizing
    ) -> CMOSGateNetlist {
        var devices: [Device] = []
        // Parallel NMOS: each input's NMOS ties output -> VGND.
        for (i, g) in inputs.enumerated() {
            devices.append(Device(name: "MN\(i)", kind: .nmos, gate: g, source: "VGND", drain: output, sizing: deviceSizing))
        }
        // Series PMOS chain: VPWR - g0 - p1 - g1 - p2 - ... - output.
        for (i, g) in inputs.enumerated() {
            let s = i == 0 ? "VPWR" : "p\(i)"
            let d = i == inputs.count - 1 ? output : "p\(i + 1)"
            devices.append(Device(name: "MP\(i)", kind: .pmos, gate: g, source: s, drain: d, sizing: deviceSizing))
        }
        return CMOSGateNetlist(name: name, devices: devices, output: output)
    }
}
