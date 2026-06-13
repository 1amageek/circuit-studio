import Foundation
import CoreGraphics

/// All built-in device definitions.
/// Adding a new device type requires only adding an entry here.
public enum BuiltInDevices {

    public static var all: [DeviceKind] {
        [
            resistor, capacitor, inductor,
            voltageSource, currentSource,
            vcvs, vccs, ccvs, cccs,
            diode, npn, pnp,
            nmosL1, pmosL1, nmosL2, pmosL2, nmosL3, pmosL3,
            ground,
            portInput, portOutput, portInout, portPower, portGround,
        ]
    }

    // MARK: - MOSFET Shared

    private static let nmosPortDefinitions: [PortDefinition] = [
        PortDefinition(id: "drain", displayName: "Drain", position: CGPoint(x: 10, y: -30)),
        PortDefinition(id: "gate", displayName: "Gate", position: CGPoint(x: -20, y: 0)),
        PortDefinition(id: "source", displayName: "Source", position: CGPoint(x: 10, y: 30)),
        PortDefinition(id: "bulk", displayName: "Bulk", position: CGPoint(x: -10, y: 30)),
    ]

    private static let pmosPortDefinitions: [PortDefinition] = [
        PortDefinition(id: "drain", displayName: "Drain", position: CGPoint(x: 10, y: 30)),
        PortDefinition(id: "gate", displayName: "Gate", position: CGPoint(x: -20, y: 0)),
        PortDefinition(id: "source", displayName: "Source", position: CGPoint(x: 10, y: -30)),
        PortDefinition(id: "bulk", displayName: "Bulk", position: CGPoint(x: -10, y: -30)),
    ]

    private static let nmosSymbolDefinition = SymbolDefinition(
        shape: .custom([
            // Gate lead
            .line(from: CGPoint(x: -20, y: 0), to: CGPoint(x: -8, y: 0)),
            // Gate plate (insulator)
            .line(from: CGPoint(x: -8, y: -14), to: CGPoint(x: -8, y: 14)),
            // Channel — 3 broken segments (IEC 60617 enhancement mode)
            .line(from: CGPoint(x: -4, y: -14), to: CGPoint(x: -4, y: -6)),
            .line(from: CGPoint(x: -4, y: -2), to: CGPoint(x: -4, y: 2)),
            .line(from: CGPoint(x: -4, y: 6), to: CGPoint(x: -4, y: 14)),
            // Drain
            .line(from: CGPoint(x: -4, y: -10), to: CGPoint(x: 10, y: -10)),
            .line(from: CGPoint(x: 10, y: -10), to: CGPoint(x: 10, y: -30)),
            // Source
            .line(from: CGPoint(x: -4, y: 10), to: CGPoint(x: 10, y: 10)),
            .line(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 30)),
            // Arrow on source (NMOS: filled triangle pointing into channel)
            .polygon([CGPoint(x: 4, y: 5), CGPoint(x: -4, y: 10), CGPoint(x: 4, y: 15)]),
            // Bulk lead (routed from bottom of channel, avoiding gate)
            .line(from: CGPoint(x: -4, y: 14), to: CGPoint(x: -10, y: 14)),
            .line(from: CGPoint(x: -10, y: 14), to: CGPoint(x: -10, y: 30)),
        ]),
        size: CGSize(width: 30, height: 60),
        iconName: "memorychip"
    )

    private static let pmosSymbolDefinition = SymbolDefinition(
        shape: .custom([
            // Gate lead (IEC 60617: no bubble for P-channel)
            .line(from: CGPoint(x: -20, y: 0), to: CGPoint(x: -8, y: 0)),
            // Gate plate (insulator)
            .line(from: CGPoint(x: -8, y: -14), to: CGPoint(x: -8, y: 14)),
            // Channel — 3 broken segments (IEC 60617 enhancement mode)
            .line(from: CGPoint(x: -4, y: -14), to: CGPoint(x: -4, y: -6)),
            .line(from: CGPoint(x: -4, y: -2), to: CGPoint(x: -4, y: 2)),
            .line(from: CGPoint(x: -4, y: 6), to: CGPoint(x: -4, y: 14)),
            // Source (top for PMOS)
            .line(from: CGPoint(x: -4, y: -10), to: CGPoint(x: 10, y: -10)),
            .line(from: CGPoint(x: 10, y: -10), to: CGPoint(x: 10, y: -30)),
            // Drain (bottom for PMOS)
            .line(from: CGPoint(x: -4, y: 10), to: CGPoint(x: 10, y: 10)),
            .line(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 30)),
            // Arrow on source (PMOS: filled triangle pointing away from channel)
            .polygon([CGPoint(x: -4, y: -15), CGPoint(x: 4, y: -10), CGPoint(x: -4, y: -5)]),
            // Bulk lead (routed from top of channel, avoiding gate)
            .line(from: CGPoint(x: -4, y: -14), to: CGPoint(x: -10, y: -14)),
            .line(from: CGPoint(x: -10, y: -14), to: CGPoint(x: -10, y: -30)),
        ]),
        size: CGSize(width: 30, height: 60),
        iconName: "memorychip"
    )

    private static let mosfetInstanceParameters: [ParameterSchema] = [
        ParameterSchema(id: "w", displayName: "Width", unit: "m", defaultValue: 10e-6, range: 1e-9...1, isRequired: true),
        ParameterSchema(id: "l", displayName: "Length", unit: "m", defaultValue: 1e-6, range: 1e-9...1, isRequired: true),
    ]

    private static let mosfetBaseModelParameters: [ParameterSchema] = [
        ParameterSchema(id: "vto", displayName: "Threshold Voltage", unit: "V", defaultValue: 0.0, isModelParameter: true),
        ParameterSchema(id: "kp", displayName: "Transconductance", unit: "A/V\u{00B2}", defaultValue: 2e-5, isModelParameter: true),
        ParameterSchema(id: "gamma", displayName: "Body Effect", unit: "V^0.5", defaultValue: 0.0, isModelParameter: true),
        ParameterSchema(id: "phi", displayName: "Surface Potential", unit: "V", defaultValue: 0.6, isModelParameter: true),
        ParameterSchema(id: "lambda", displayName: "Channel-Length Modulation", unit: "1/V", defaultValue: 0.0, isModelParameter: true),
    ]

    private static let mosfetLevel2Parameters: [ParameterSchema] = [
        ParameterSchema(id: "theta", displayName: "Mobility Degradation", unit: "1/V", defaultValue: 0.0, isModelParameter: true),
        ParameterSchema(id: "eta", displayName: "DIBL Coefficient", unit: "V/V", defaultValue: 0.0, isModelParameter: true),
    ]

    private static let mosfetLevel3Parameters: [ParameterSchema] = [
        ParameterSchema(id: "kappa", displayName: "Velocity Saturation", unit: "1/V", defaultValue: 0.0, isModelParameter: true),
        ParameterSchema(id: "vmax", displayName: "Saturation Velocity", unit: "m/s", defaultValue: 0.0, isModelParameter: true),
    ]

    private static let mosfetCapacitanceParameters: [ParameterSchema] = [
        ParameterSchema(id: "tox", displayName: "Gate Oxide Thickness", unit: "m", defaultValue: 100e-9, isModelParameter: true),
        ParameterSchema(id: "cgso", displayName: "Gate-Source Overlap", unit: "F/m", defaultValue: 0.0, isModelParameter: true),
        ParameterSchema(id: "cgdo", displayName: "Gate-Drain Overlap", unit: "F/m", defaultValue: 0.0, isModelParameter: true),
        ParameterSchema(id: "cgbo", displayName: "Gate-Bulk Overlap", unit: "F/m", defaultValue: 0.0, isModelParameter: true),
        ParameterSchema(id: "cj", displayName: "Junction Capacitance", unit: "F/m\u{00B2}", defaultValue: 0.0, isModelParameter: true),
        ParameterSchema(id: "cjsw", displayName: "Sidewall Capacitance", unit: "F/m", defaultValue: 0.0, isModelParameter: true),
        ParameterSchema(id: "mj", displayName: "Junction Grading", unit: "", defaultValue: 0.5, isModelParameter: true),
        ParameterSchema(id: "mjsw", displayName: "Sidewall Grading", unit: "", defaultValue: 0.33, isModelParameter: true),
        ParameterSchema(id: "pb", displayName: "Junction Potential", unit: "V", defaultValue: 0.8, isModelParameter: true),
        ParameterSchema(id: "ad", displayName: "Drain Area", unit: "m\u{00B2}", defaultValue: 0.0, isModelParameter: true),
        ParameterSchema(id: "as", displayName: "Source Area", unit: "m\u{00B2}", defaultValue: 0.0, isModelParameter: true),
        ParameterSchema(id: "pd", displayName: "Drain Perimeter", unit: "m", defaultValue: 0.0, isModelParameter: true),
        ParameterSchema(id: "ps", displayName: "Source Perimeter", unit: "m", defaultValue: 0.0, isModelParameter: true),
    ]

    private static func mosfetParameters(level: Int) -> [ParameterSchema] {
        var params = mosfetInstanceParameters + mosfetBaseModelParameters
        if level >= 2 {
            params += mosfetLevel2Parameters
        }
        if level >= 3 {
            params += mosfetLevel3Parameters
        }
        params += mosfetCapacitanceParameters
        return params
    }

    // MARK: - Passive

    public static let resistor = DeviceKind(
        id: "resistor",
        displayName: "Resistor",
        category: .passive,
        spicePrefix: "R",
        portDefinitions: [
            PortDefinition(id: "pos", displayName: "Positive", position: CGPoint(x: 0, y: -30)),
            PortDefinition(id: "neg", displayName: "Negative", position: CGPoint(x: 0, y: 30)),
        ],
        parameterSchema: [
            ParameterSchema(id: "r", displayName: "Resistance", unit: "\u{2126}", defaultValue: 1000, range: 0.001...1e12, isRequired: true),
        ],
        symbol: SymbolDefinition(
            shape: .custom([
                .line(from: CGPoint(x: 0, y: -30), to: CGPoint(x: 0, y: -20)),
                .rect(origin: CGPoint(x: -6, y: -20), size: CGSize(width: 12, height: 40)),
                .line(from: CGPoint(x: 0, y: 20), to: CGPoint(x: 0, y: 30)),
            ]),
            size: CGSize(width: 12, height: 60),
            iconName: "rectangle"
        )
    )

    public static let capacitor = DeviceKind(
        id: "capacitor",
        displayName: "Capacitor",
        category: .passive,
        spicePrefix: "C",
        portDefinitions: [
            PortDefinition(id: "pos", displayName: "Positive", position: CGPoint(x: 0, y: -30)),
            PortDefinition(id: "neg", displayName: "Negative", position: CGPoint(x: 0, y: 30)),
        ],
        parameterSchema: [
            ParameterSchema(id: "c", displayName: "Capacitance", unit: "F", defaultValue: 1e-9, range: 1e-15...1e3, isRequired: true),
        ],
        symbol: SymbolDefinition(
            shape: .custom([
                .line(from: CGPoint(x: 0, y: -30), to: CGPoint(x: 0, y: -5)),
                .line(from: CGPoint(x: -10, y: -5), to: CGPoint(x: 10, y: -5)),
                .line(from: CGPoint(x: -10, y: 5), to: CGPoint(x: 10, y: 5)),
                .line(from: CGPoint(x: 0, y: 5), to: CGPoint(x: 0, y: 30)),
            ]),
            size: CGSize(width: 20, height: 60),
            iconName: "equal"
        )
    )

    public static let inductor = DeviceKind(
        id: "inductor",
        displayName: "Inductor",
        category: .passive,
        spicePrefix: "L",
        portDefinitions: [
            PortDefinition(id: "pos", displayName: "Positive", position: CGPoint(x: 0, y: -30)),
            PortDefinition(id: "neg", displayName: "Negative", position: CGPoint(x: 0, y: 30)),
        ],
        parameterSchema: [
            ParameterSchema(id: "l", displayName: "Inductance", unit: "H", defaultValue: 1e-6, range: 1e-15...1e6, isRequired: true),
        ],
        symbol: SymbolDefinition(
            shape: .custom([
                .line(from: CGPoint(x: 0, y: -30), to: CGPoint(x: 0, y: -20)),
                .arc(center: CGPoint(x: 0, y: -15), radius: 5, startAngle: -.pi / 2, endAngle: .pi / 2),
                .arc(center: CGPoint(x: 0, y: -5), radius: 5, startAngle: -.pi / 2, endAngle: .pi / 2),
                .arc(center: CGPoint(x: 0, y: 5), radius: 5, startAngle: -.pi / 2, endAngle: .pi / 2),
                .arc(center: CGPoint(x: 0, y: 15), radius: 5, startAngle: -.pi / 2, endAngle: .pi / 2),
                .line(from: CGPoint(x: 0, y: 20), to: CGPoint(x: 0, y: 30)),
            ]),
            size: CGSize(width: 10, height: 60),
            iconName: "wave.3.right"
        )
    )

    // MARK: - Sources

    public static let voltageSource = DeviceKind(
        id: "vsource",
        displayName: "Voltage Source",
        category: .source,
        spicePrefix: "V",
        portDefinitions: [
            PortDefinition(id: "pos", displayName: "Positive", position: CGPoint(x: 0, y: -30)),
            PortDefinition(id: "neg", displayName: "Negative", position: CGPoint(x: 0, y: 30)),
        ],
        parameterSchema: [
            ParameterSchema(id: "dc", displayName: "DC Voltage", unit: "V", defaultValue: 5.0),
            ParameterSchema(id: "ac", displayName: "AC Magnitude", unit: "V", defaultValue: nil),
            // PULSE parameters
            ParameterSchema(id: "pulse_v1", displayName: "PULSE Initial", unit: "V", defaultValue: nil),
            ParameterSchema(id: "pulse_v2", displayName: "PULSE Pulsed", unit: "V", defaultValue: nil),
            ParameterSchema(id: "pulse_td", displayName: "PULSE Delay", unit: "s", defaultValue: nil),
            ParameterSchema(id: "pulse_tr", displayName: "PULSE Rise", unit: "s", defaultValue: nil),
            ParameterSchema(id: "pulse_tf", displayName: "PULSE Fall", unit: "s", defaultValue: nil),
            ParameterSchema(id: "pulse_pw", displayName: "PULSE Width", unit: "s", defaultValue: nil),
            ParameterSchema(id: "pulse_per", displayName: "PULSE Period", unit: "s", defaultValue: nil),
            // SIN parameters
            ParameterSchema(id: "sin_vo", displayName: "SIN Offset", unit: "V", defaultValue: nil),
            ParameterSchema(id: "sin_va", displayName: "SIN Amplitude", unit: "V", defaultValue: nil),
            ParameterSchema(id: "sin_freq", displayName: "SIN Frequency", unit: "Hz", defaultValue: nil),
            ParameterSchema(id: "sin_td", displayName: "SIN Delay", unit: "s", defaultValue: nil),
            ParameterSchema(id: "sin_theta", displayName: "SIN Damping", unit: "1/s", defaultValue: nil),
        ],
        symbol: SymbolDefinition(
            shape: .custom([
                .line(from: CGPoint(x: 0, y: -30), to: CGPoint(x: 0, y: -15)),
                .circle(center: .zero, radius: 15),
                .text("+", at: CGPoint(x: 0, y: -8), fontSize: 10),
                .text("-", at: CGPoint(x: 0, y: 8), fontSize: 10),
                .line(from: CGPoint(x: 0, y: 15), to: CGPoint(x: 0, y: 30)),
            ]),
            size: CGSize(width: 30, height: 60),
            iconName: "bolt.circle"
        )
    )

    public static let currentSource = DeviceKind(
        id: "isource",
        displayName: "Current Source",
        category: .source,
        spicePrefix: "I",
        portDefinitions: [
            PortDefinition(id: "pos", displayName: "Positive", position: CGPoint(x: 0, y: -30)),
            PortDefinition(id: "neg", displayName: "Negative", position: CGPoint(x: 0, y: 30)),
        ],
        parameterSchema: [
            ParameterSchema(id: "dc", displayName: "DC Current", unit: "A", defaultValue: 0.001),
            ParameterSchema(id: "ac", displayName: "AC Magnitude", unit: "A", defaultValue: nil),
            // PULSE parameters
            ParameterSchema(id: "pulse_v1", displayName: "PULSE Initial", unit: "A", defaultValue: nil),
            ParameterSchema(id: "pulse_v2", displayName: "PULSE Pulsed", unit: "A", defaultValue: nil),
            ParameterSchema(id: "pulse_td", displayName: "PULSE Delay", unit: "s", defaultValue: nil),
            ParameterSchema(id: "pulse_tr", displayName: "PULSE Rise", unit: "s", defaultValue: nil),
            ParameterSchema(id: "pulse_tf", displayName: "PULSE Fall", unit: "s", defaultValue: nil),
            ParameterSchema(id: "pulse_pw", displayName: "PULSE Width", unit: "s", defaultValue: nil),
            ParameterSchema(id: "pulse_per", displayName: "PULSE Period", unit: "s", defaultValue: nil),
            // SIN parameters
            ParameterSchema(id: "sin_vo", displayName: "SIN Offset", unit: "A", defaultValue: nil),
            ParameterSchema(id: "sin_va", displayName: "SIN Amplitude", unit: "A", defaultValue: nil),
            ParameterSchema(id: "sin_freq", displayName: "SIN Frequency", unit: "Hz", defaultValue: nil),
            ParameterSchema(id: "sin_td", displayName: "SIN Delay", unit: "s", defaultValue: nil),
            ParameterSchema(id: "sin_theta", displayName: "SIN Damping", unit: "1/s", defaultValue: nil),
        ],
        symbol: SymbolDefinition(
            shape: .custom([
                .line(from: CGPoint(x: 0, y: -30), to: CGPoint(x: 0, y: -15)),
                .circle(center: .zero, radius: 15),
                .line(from: CGPoint(x: 0, y: -8), to: CGPoint(x: 0, y: 8)),
                .line(from: CGPoint(x: -4, y: 4), to: CGPoint(x: 0, y: 8)),
                .line(from: CGPoint(x: 4, y: 4), to: CGPoint(x: 0, y: 8)),
                .line(from: CGPoint(x: 0, y: 15), to: CGPoint(x: 0, y: 30)),
            ]),
            size: CGSize(width: 30, height: 60),
            iconName: "arrow.up.circle"
        )
    )

    // MARK: - Controlled Sources

    public static let vcvs = DeviceKind(
        id: "vcvs",
        displayName: "VCVS",
        category: .controlled,
        spicePrefix: "E",
        portDefinitions: [
            PortDefinition(id: "pos_out", displayName: "Out+", position: CGPoint(x: -20, y: -30)),
            PortDefinition(id: "neg_out", displayName: "Out-", position: CGPoint(x: -20, y: 30)),
            PortDefinition(id: "pos_ctrl", displayName: "Ctrl+", position: CGPoint(x: 20, y: -30)),
            PortDefinition(id: "neg_ctrl", displayName: "Ctrl-", position: CGPoint(x: 20, y: 30)),
        ],
        parameterSchema: [
            ParameterSchema(id: "e", displayName: "Voltage Gain", unit: "V/V", defaultValue: 1.0, isRequired: true),
        ],
        symbol: SymbolDefinition(
            shape: .custom([
                // Diamond shape for controlled source
                .line(from: CGPoint(x: 0, y: -20), to: CGPoint(x: 15, y: 0)),
                .line(from: CGPoint(x: 15, y: 0), to: CGPoint(x: 0, y: 20)),
                .line(from: CGPoint(x: 0, y: 20), to: CGPoint(x: -15, y: 0)),
                .line(from: CGPoint(x: -15, y: 0), to: CGPoint(x: 0, y: -20)),
                // Output leads
                .line(from: CGPoint(x: -20, y: -30), to: CGPoint(x: -20, y: -15)),
                .line(from: CGPoint(x: -20, y: -15), to: CGPoint(x: -7.5, y: -10)),
                .line(from: CGPoint(x: -20, y: 30), to: CGPoint(x: -20, y: 15)),
                .line(from: CGPoint(x: -20, y: 15), to: CGPoint(x: -7.5, y: 10)),
                // Control leads
                .line(from: CGPoint(x: 20, y: -30), to: CGPoint(x: 20, y: -15)),
                .line(from: CGPoint(x: 20, y: -15), to: CGPoint(x: 7.5, y: -10)),
                .line(from: CGPoint(x: 20, y: 30), to: CGPoint(x: 20, y: 15)),
                .line(from: CGPoint(x: 20, y: 15), to: CGPoint(x: 7.5, y: 10)),
                .text("+", at: CGPoint(x: -5, y: -5), fontSize: 8),
                .text("-", at: CGPoint(x: -5, y: 5), fontSize: 8),
            ]),
            size: CGSize(width: 40, height: 60),
            iconName: "diamond"
        )
    )

    public static let vccs = DeviceKind(
        id: "vccs",
        displayName: "VCCS",
        category: .controlled,
        spicePrefix: "G",
        portDefinitions: [
            PortDefinition(id: "pos_out", displayName: "Out+", position: CGPoint(x: -20, y: -30)),
            PortDefinition(id: "neg_out", displayName: "Out-", position: CGPoint(x: -20, y: 30)),
            PortDefinition(id: "pos_ctrl", displayName: "Ctrl+", position: CGPoint(x: 20, y: -30)),
            PortDefinition(id: "neg_ctrl", displayName: "Ctrl-", position: CGPoint(x: 20, y: 30)),
        ],
        parameterSchema: [
            ParameterSchema(id: "g", displayName: "Transconductance", unit: "S", defaultValue: 0.001, isRequired: true),
        ],
        symbol: SymbolDefinition(
            shape: .custom([
                .line(from: CGPoint(x: 0, y: -20), to: CGPoint(x: 15, y: 0)),
                .line(from: CGPoint(x: 15, y: 0), to: CGPoint(x: 0, y: 20)),
                .line(from: CGPoint(x: 0, y: 20), to: CGPoint(x: -15, y: 0)),
                .line(from: CGPoint(x: -15, y: 0), to: CGPoint(x: 0, y: -20)),
                .line(from: CGPoint(x: -20, y: -30), to: CGPoint(x: -20, y: -15)),
                .line(from: CGPoint(x: -20, y: -15), to: CGPoint(x: -7.5, y: -10)),
                .line(from: CGPoint(x: -20, y: 30), to: CGPoint(x: -20, y: 15)),
                .line(from: CGPoint(x: -20, y: 15), to: CGPoint(x: -7.5, y: 10)),
                .line(from: CGPoint(x: 20, y: -30), to: CGPoint(x: 20, y: -15)),
                .line(from: CGPoint(x: 20, y: -15), to: CGPoint(x: 7.5, y: -10)),
                .line(from: CGPoint(x: 20, y: 30), to: CGPoint(x: 20, y: 15)),
                .line(from: CGPoint(x: 20, y: 15), to: CGPoint(x: 7.5, y: 10)),
                // Arrow for current
                .line(from: CGPoint(x: -3, y: -5), to: CGPoint(x: -3, y: 5)),
                .line(from: CGPoint(x: -6, y: 2), to: CGPoint(x: -3, y: 5)),
                .line(from: CGPoint(x: 0, y: 2), to: CGPoint(x: -3, y: 5)),
            ]),
            size: CGSize(width: 40, height: 60),
            iconName: "diamond"
        )
    )

    public static let ccvs = DeviceKind(
        id: "ccvs",
        displayName: "CCVS",
        category: .controlled,
        spicePrefix: "H",
        portDefinitions: [
            PortDefinition(id: "pos_out", displayName: "Out+", position: CGPoint(x: -20, y: -30)),
            PortDefinition(id: "neg_out", displayName: "Out-", position: CGPoint(x: -20, y: 30)),
            PortDefinition(id: "pos_sense", displayName: "Sense+", position: CGPoint(x: 20, y: -30)),
            PortDefinition(id: "neg_sense", displayName: "Sense-", position: CGPoint(x: 20, y: 30)),
        ],
        parameterSchema: [
            ParameterSchema(id: "h", displayName: "Transresistance", unit: "\u{2126}", defaultValue: 1000, isRequired: true),
        ],
        symbol: SymbolDefinition(
            shape: .custom([
                .line(from: CGPoint(x: 0, y: -20), to: CGPoint(x: 15, y: 0)),
                .line(from: CGPoint(x: 15, y: 0), to: CGPoint(x: 0, y: 20)),
                .line(from: CGPoint(x: 0, y: 20), to: CGPoint(x: -15, y: 0)),
                .line(from: CGPoint(x: -15, y: 0), to: CGPoint(x: 0, y: -20)),
                .line(from: CGPoint(x: -20, y: -30), to: CGPoint(x: -20, y: -15)),
                .line(from: CGPoint(x: -20, y: -15), to: CGPoint(x: -7.5, y: -10)),
                .line(from: CGPoint(x: -20, y: 30), to: CGPoint(x: -20, y: 15)),
                .line(from: CGPoint(x: -20, y: 15), to: CGPoint(x: -7.5, y: 10)),
                .line(from: CGPoint(x: 20, y: -30), to: CGPoint(x: 20, y: -15)),
                .line(from: CGPoint(x: 20, y: -15), to: CGPoint(x: 7.5, y: -10)),
                .line(from: CGPoint(x: 20, y: 30), to: CGPoint(x: 20, y: 15)),
                .line(from: CGPoint(x: 20, y: 15), to: CGPoint(x: 7.5, y: 10)),
                .text("+", at: CGPoint(x: -5, y: -5), fontSize: 8),
                .text("-", at: CGPoint(x: -5, y: 5), fontSize: 8),
            ]),
            size: CGSize(width: 40, height: 60),
            iconName: "diamond"
        )
    )

    public static let cccs = DeviceKind(
        id: "cccs",
        displayName: "CCCS",
        category: .controlled,
        spicePrefix: "F",
        portDefinitions: [
            PortDefinition(id: "pos_out", displayName: "Out+", position: CGPoint(x: -20, y: -30)),
            PortDefinition(id: "neg_out", displayName: "Out-", position: CGPoint(x: -20, y: 30)),
            PortDefinition(id: "pos_sense", displayName: "Sense+", position: CGPoint(x: 20, y: -30)),
            PortDefinition(id: "neg_sense", displayName: "Sense-", position: CGPoint(x: 20, y: 30)),
        ],
        parameterSchema: [
            ParameterSchema(id: "f", displayName: "Current Gain", unit: "A/A", defaultValue: 1.0, isRequired: true),
        ],
        symbol: SymbolDefinition(
            shape: .custom([
                .line(from: CGPoint(x: 0, y: -20), to: CGPoint(x: 15, y: 0)),
                .line(from: CGPoint(x: 15, y: 0), to: CGPoint(x: 0, y: 20)),
                .line(from: CGPoint(x: 0, y: 20), to: CGPoint(x: -15, y: 0)),
                .line(from: CGPoint(x: -15, y: 0), to: CGPoint(x: 0, y: -20)),
                .line(from: CGPoint(x: -20, y: -30), to: CGPoint(x: -20, y: -15)),
                .line(from: CGPoint(x: -20, y: -15), to: CGPoint(x: -7.5, y: -10)),
                .line(from: CGPoint(x: -20, y: 30), to: CGPoint(x: -20, y: 15)),
                .line(from: CGPoint(x: -20, y: 15), to: CGPoint(x: -7.5, y: 10)),
                .line(from: CGPoint(x: 20, y: -30), to: CGPoint(x: 20, y: -15)),
                .line(from: CGPoint(x: 20, y: -15), to: CGPoint(x: 7.5, y: -10)),
                .line(from: CGPoint(x: 20, y: 30), to: CGPoint(x: 20, y: 15)),
                .line(from: CGPoint(x: 20, y: 15), to: CGPoint(x: 7.5, y: 10)),
                .line(from: CGPoint(x: -3, y: -5), to: CGPoint(x: -3, y: 5)),
                .line(from: CGPoint(x: -6, y: 2), to: CGPoint(x: -3, y: 5)),
                .line(from: CGPoint(x: 0, y: 2), to: CGPoint(x: -3, y: 5)),
            ]),
            size: CGSize(width: 40, height: 60),
            iconName: "diamond"
        )
    )

    // MARK: - Semiconductor

    public static let diode = DeviceKind(
        id: "diode",
        displayName: "Diode",
        category: .semiconductor,
        spicePrefix: "D",
        modelType: "D",
        portDefinitions: [
            PortDefinition(id: "anode", displayName: "Anode", position: CGPoint(x: 0, y: -30)),
            PortDefinition(id: "cathode", displayName: "Cathode", position: CGPoint(x: 0, y: 30)),
        ],
        parameterSchema: [
            ParameterSchema(id: "is", displayName: "Saturation Current", unit: "A", defaultValue: 1e-14, isModelParameter: true),
            ParameterSchema(id: "n", displayName: "Emission Coefficient", unit: "", defaultValue: 1.0, isModelParameter: true),
        ],
        symbol: SymbolDefinition(
            shape: .custom([
                .line(from: CGPoint(x: 0, y: -30), to: CGPoint(x: 0, y: -8)),
                // Triangle (IEC 60617: filled)
                .polygon([CGPoint(x: -8, y: -8), CGPoint(x: 8, y: -8), CGPoint(x: 0, y: 8)]),
                // Bar
                .line(from: CGPoint(x: -8, y: 8), to: CGPoint(x: 8, y: 8)),
                .line(from: CGPoint(x: 0, y: 8), to: CGPoint(x: 0, y: 30)),
            ]),
            size: CGSize(width: 16, height: 60),
            iconName: "arrowtriangle.down"
        )
    )

    public static let npn = DeviceKind(
        id: "npn",
        displayName: "NPN BJT",
        category: .semiconductor,
        spicePrefix: "Q",
        modelType: "NPN",
        portDefinitions: [
            PortDefinition(id: "collector", displayName: "Collector", position: CGPoint(x: 10, y: -30)),
            PortDefinition(id: "base", displayName: "Base", position: CGPoint(x: -20, y: 0)),
            PortDefinition(id: "emitter", displayName: "Emitter", position: CGPoint(x: 10, y: 30)),
        ],
        parameterSchema: [
            ParameterSchema(id: "bf", displayName: "Forward Beta", unit: "", defaultValue: 100, isModelParameter: true),
            ParameterSchema(id: "is", displayName: "Saturation Current", unit: "A", defaultValue: 1e-14, isModelParameter: true),
        ],
        symbol: SymbolDefinition(
            shape: .custom([
                // Base lead
                .line(from: CGPoint(x: -20, y: 0), to: CGPoint(x: -5, y: 0)),
                // Base line (vertical)
                .line(from: CGPoint(x: -5, y: -12), to: CGPoint(x: -5, y: 12)),
                // Collector
                .line(from: CGPoint(x: -5, y: -8), to: CGPoint(x: 10, y: -20)),
                .line(from: CGPoint(x: 10, y: -20), to: CGPoint(x: 10, y: -30)),
                // Emitter
                .line(from: CGPoint(x: -5, y: 8), to: CGPoint(x: 10, y: 20)),
                .line(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 10, y: 30)),
                // Arrow on emitter (IEC 60617: filled triangle pointing outward)
                .polygon([CGPoint(x: 4, y: 14), CGPoint(x: 10, y: 20), CGPoint(x: 10, y: 14)]),
            ]),
            size: CGSize(width: 30, height: 60),
            iconName: "arrow.triangle.branch"
        )
    )

    public static let pnp = DeviceKind(
        id: "pnp",
        displayName: "PNP BJT",
        category: .semiconductor,
        spicePrefix: "Q",
        modelType: "PNP",
        portDefinitions: [
            PortDefinition(id: "collector", displayName: "Collector", position: CGPoint(x: 10, y: 30)),
            PortDefinition(id: "base", displayName: "Base", position: CGPoint(x: -20, y: 0)),
            PortDefinition(id: "emitter", displayName: "Emitter", position: CGPoint(x: 10, y: -30)),
        ],
        parameterSchema: [
            ParameterSchema(id: "bf", displayName: "Forward Beta", unit: "", defaultValue: 100, isModelParameter: true),
            ParameterSchema(id: "is", displayName: "Saturation Current", unit: "A", defaultValue: 1e-14, isModelParameter: true),
        ],
        symbol: SymbolDefinition(
            shape: .custom([
                // Base lead
                .line(from: CGPoint(x: -20, y: 0), to: CGPoint(x: -5, y: 0)),
                // Base line (vertical)
                .line(from: CGPoint(x: -5, y: -12), to: CGPoint(x: -5, y: 12)),
                // Emitter
                .line(from: CGPoint(x: -5, y: -8), to: CGPoint(x: 10, y: -20)),
                .line(from: CGPoint(x: 10, y: -20), to: CGPoint(x: 10, y: -30)),
                // Arrow on emitter (IEC 60617: filled triangle pointing inward)
                .polygon([CGPoint(x: -1, y: -10), CGPoint(x: -5, y: -8), CGPoint(x: -3, y: -14)]),
                // Collector
                .line(from: CGPoint(x: -5, y: 8), to: CGPoint(x: 10, y: 20)),
                .line(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 10, y: 30)),
            ]),
            size: CGSize(width: 30, height: 60),
            iconName: "arrow.triangle.branch"
        )
    )

    public static let nmosL1 = DeviceKind(
        id: "nmos_l1",
        displayName: "NMOS L1",
        category: .semiconductor,
        spicePrefix: "M",
        modelType: "NMOS",
        portDefinitions: nmosPortDefinitions,
        parameterSchema: mosfetParameters(level: 1),
        symbol: nmosSymbolDefinition
    )

    public static let pmosL1 = DeviceKind(
        id: "pmos_l1",
        displayName: "PMOS L1",
        category: .semiconductor,
        spicePrefix: "M",
        modelType: "PMOS",
        portDefinitions: pmosPortDefinitions,
        parameterSchema: mosfetParameters(level: 1),
        symbol: pmosSymbolDefinition
    )

    public static let nmosL2 = DeviceKind(
        id: "nmos_l2",
        displayName: "NMOS L2",
        category: .semiconductor,
        spicePrefix: "M",
        modelType: "NMOS",
        portDefinitions: nmosPortDefinitions,
        parameterSchema: mosfetParameters(level: 2),
        symbol: nmosSymbolDefinition
    )

    public static let pmosL2 = DeviceKind(
        id: "pmos_l2",
        displayName: "PMOS L2",
        category: .semiconductor,
        spicePrefix: "M",
        modelType: "PMOS",
        portDefinitions: pmosPortDefinitions,
        parameterSchema: mosfetParameters(level: 2),
        symbol: pmosSymbolDefinition
    )

    public static let nmosL3 = DeviceKind(
        id: "nmos_l3",
        displayName: "NMOS L3",
        category: .semiconductor,
        spicePrefix: "M",
        modelType: "NMOS",
        portDefinitions: nmosPortDefinitions,
        parameterSchema: mosfetParameters(level: 3),
        symbol: nmosSymbolDefinition
    )

    public static let pmosL3 = DeviceKind(
        id: "pmos_l3",
        displayName: "PMOS L3",
        category: .semiconductor,
        spicePrefix: "M",
        modelType: "PMOS",
        portDefinitions: pmosPortDefinitions,
        parameterSchema: mosfetParameters(level: 3),
        symbol: pmosSymbolDefinition
    )

    // MARK: - Special

    public static let ground = DeviceKind(
        id: "ground",
        displayName: "Ground",
        category: .special,
        spicePrefix: "GND",
        portDefinitions: [
            PortDefinition(id: "gnd", displayName: "Ground", position: CGPoint(x: 0, y: -10)),
        ],
        parameterSchema: [],
        symbol: SymbolDefinition(
            shape: .custom([
                .line(from: CGPoint(x: 0, y: -10), to: CGPoint(x: 0, y: 0)),
                .line(from: CGPoint(x: -10, y: 0), to: CGPoint(x: 10, y: 0)),
                .line(from: CGPoint(x: -6, y: 5), to: CGPoint(x: 6, y: 5)),
                .line(from: CGPoint(x: -2, y: 10), to: CGPoint(x: 2, y: 10)),
            ]),
            size: CGSize(width: 20, height: 20),
            iconName: "minus"
        )
    )

    // MARK: - Ports
    //
    // Directional cell-boundary markers. A port component's instance name
    // (e.g. "IN", "OUT", "VDD") names the net it touches, becomes a node on
    // the cell's `.subckt` line, and doubles as a probe target. Ports emit
    // no SPICE element themselves.

    /// Single-pin definition shared by every port kind. The pin id is
    /// uniform so interface derivation can address it without a catalog.
    private static func portPin() -> [PortDefinition] {
        [PortDefinition(id: "pin", displayName: "Pin", position: CGPoint(x: -10, y: 0))]
    }

    public static let portInput = DeviceKind(
        id: PortDirection.input.deviceKindID,
        displayName: "Input Port",
        category: .port,
        spicePrefix: "IN",
        portDefinitions: portPin(),
        parameterSchema: [],
        symbol: SymbolDefinition(
            shape: .custom([
                // Lead from pin (left) into the flag
                .line(from: CGPoint(x: -10, y: 0), to: CGPoint(x: -2, y: 0)),
                // Right-pointing flag: signal flows into the circuit
                .polygon([
                    CGPoint(x: -2, y: -6), CGPoint(x: 8, y: -6),
                    CGPoint(x: 14, y: 0), CGPoint(x: 8, y: 6),
                    CGPoint(x: -2, y: 6),
                ]),
            ]),
            size: CGSize(width: 24, height: 12),
            iconName: "arrow.right.square"
        )
    )

    public static let portOutput = DeviceKind(
        id: PortDirection.output.deviceKindID,
        displayName: "Output Port",
        category: .port,
        spicePrefix: "OUT",
        portDefinitions: portPin(),
        parameterSchema: [],
        symbol: SymbolDefinition(
            shape: .custom([
                .line(from: CGPoint(x: -10, y: 0), to: CGPoint(x: -2, y: 0)),
                // Flag with a pointed tail: signal flows out of the circuit
                .polygon([
                    CGPoint(x: 4, y: -6), CGPoint(x: 14, y: -6),
                    CGPoint(x: 14, y: 6), CGPoint(x: 4, y: 6),
                    CGPoint(x: -2, y: 0),
                ]),
            ]),
            size: CGSize(width: 24, height: 12),
            iconName: "arrow.right.square.fill"
        )
    )

    public static let portInout = DeviceKind(
        id: PortDirection.bidirectional.deviceKindID,
        displayName: "Bidirectional Port",
        category: .port,
        spicePrefix: "IO",
        portDefinitions: portPin(),
        parameterSchema: [],
        symbol: SymbolDefinition(
            shape: .custom([
                .line(from: CGPoint(x: -10, y: 0), to: CGPoint(x: -2, y: 0)),
                // Double-pointed flag: signal flows both ways
                .polygon([
                    CGPoint(x: -2, y: 0), CGPoint(x: 4, y: -6),
                    CGPoint(x: 10, y: -6), CGPoint(x: 16, y: 0),
                    CGPoint(x: 10, y: 6), CGPoint(x: 4, y: 6),
                ]),
            ]),
            size: CGSize(width: 26, height: 12),
            iconName: "arrow.left.arrow.right.square"
        )
    )

    public static let portPower = DeviceKind(
        id: PortDirection.power.deviceKindID,
        displayName: "Power Port",
        category: .port,
        spicePrefix: "VDD",
        portDefinitions: [
            PortDefinition(id: "pin", displayName: "Pin", position: CGPoint(x: 0, y: 10)),
        ],
        parameterSchema: [],
        symbol: SymbolDefinition(
            shape: .custom([
                // Lead from pin (bottom) up to the rail bar
                .line(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 0, y: 0)),
                .line(from: CGPoint(x: -8, y: 0), to: CGPoint(x: 8, y: 0)),
                // Upward arrow head above the bar
                .line(from: CGPoint(x: -4, y: -4), to: CGPoint(x: 0, y: -8)),
                .line(from: CGPoint(x: 4, y: -4), to: CGPoint(x: 0, y: -8)),
            ]),
            size: CGSize(width: 16, height: 18),
            iconName: "bolt.square"
        )
    )

    public static let portGround = DeviceKind(
        id: PortDirection.ground.deviceKindID,
        displayName: "Ground Port",
        category: .port,
        spicePrefix: "VSS",
        portDefinitions: [
            PortDefinition(id: "pin", displayName: "Pin", position: CGPoint(x: 0, y: -10)),
        ],
        parameterSchema: [],
        symbol: SymbolDefinition(
            shape: .custom([
                // Lead from pin (top) down to the rail bar — unlike the
                // global ground symbol, this names a cell port, not node 0.
                .line(from: CGPoint(x: 0, y: -10), to: CGPoint(x: 0, y: 0)),
                .line(from: CGPoint(x: -8, y: 0), to: CGPoint(x: 8, y: 0)),
                .line(from: CGPoint(x: -4, y: 4), to: CGPoint(x: 4, y: 4)),
            ]),
            size: CGSize(width: 16, height: 16),
            iconName: "bolt.square.fill"
        )
    )
}
