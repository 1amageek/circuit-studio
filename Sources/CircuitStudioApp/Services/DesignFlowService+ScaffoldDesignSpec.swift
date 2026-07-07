import Foundation
import CircuitStudioCore

extension DesignFlowService {

    /// Default design name used when `--design-name` is absent.
    static let scaffoldDesignSpecDefaultName = "new_design"

    /// Writes a minimal valid `DesignFlowDesignSpec` JSON skeleton to
    /// `outputDesignSpecPath`. The spec is constructed as a Swift value
    /// (never a hand-maintained string), encoded, decoded back through
    /// `DesignFlowDesignSpec`, and `build()` succeeds on the decoded value
    /// before anything reaches disk — so the scaffold cannot drift from
    /// the schema, and `--generate-netlist --design-spec <path>` consumes
    /// it unchanged.
    func scaffoldDesignSpec(_ command: DesignFlowCommand) throws -> DesignFlowCommandResult {
        guard let outputDesignSpecPath = command.outputDesignSpecPath else {
            throw DesignFlowCommandError.missingOutputDesignSpecPath
        }
        let designName = command.designName ?? Self.scaffoldDesignSpecDefaultName
        let spec = Self.makeScaffoldDesignSpec(designName: designName)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(spec)

        // Round-trip gate: the exact bytes written to disk must decode
        // through the real spec type and build successfully.
        let decoded = try JSONDecoder().decode(DesignFlowDesignSpec.self, from: data)
        _ = try decoded.build()

        let outputURL = URL(filePath: outputDesignSpecPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)

        return DesignFlowCommandResult(
            kind: command.kind,
            designName: designName,
            designSpecPath: outputURL.path(percentEncoded: false),
            message: "scaffolded"
        )
    }

    /// The minimal example circuit: one DC voltage source driving a
    /// diode-connected NMOS, with a ground reference, one transient
    /// analysis, a matching post-layout analysis, empty comparison
    /// limits, and a tiny valid PEX IR (one grounded capacitor).
    static func makeScaffoldDesignSpec(designName: String) -> DesignFlowDesignSpec {
        let tran = DesignFlowDesignSpec.Analysis(
            kind: .tran,
            stopTime: 1e-6,
            stepTime: 1e-9,
            maxStep: 2e-9
        )
        return DesignFlowDesignSpec(
            name: designName,
            title: "Scaffolded minimal design: DC source driving a diode-connected NMOS",
            components: [
                DesignFlowDesignSpec.Component(
                    name: "V1",
                    deviceKindID: "vsource",
                    parameters: ["dc": 1.8]
                ),
                DesignFlowDesignSpec.Component(
                    name: "M1",
                    deviceKindID: "nmos_l1",
                    parameters: ["w": 1e-6, "l": 1e-6],
                    modelPresetID: "generic_nmos"
                ),
                DesignFlowDesignSpec.Component(
                    name: "GND1",
                    deviceKindID: "ground"
                ),
            ],
            nets: [
                DesignFlowDesignSpec.Net(name: "vdd", terminals: [
                    DesignFlowDesignSpec.Terminal(component: "V1", port: "pos"),
                    DesignFlowDesignSpec.Terminal(component: "M1", port: "drain"),
                    DesignFlowDesignSpec.Terminal(component: "M1", port: "gate"),
                ]),
                DesignFlowDesignSpec.Net(name: "0", terminals: [
                    DesignFlowDesignSpec.Terminal(component: "GND1", port: "gnd"),
                    DesignFlowDesignSpec.Terminal(component: "V1", port: "neg"),
                    DesignFlowDesignSpec.Terminal(component: "M1", port: "source"),
                    DesignFlowDesignSpec.Terminal(component: "M1", port: "bulk"),
                ]),
            ],
            analyses: [tran],
            postLayoutAnalysis: tran,
            postLayoutComparisonLimits: PostLayoutComparisonLimits(),
            parasiticIR: DesignFlowDesignSpec.ParasiticIR(
                version: "1.0",
                cornerID: "tt_25c_1v0",
                elements: [
                    DesignFlowDesignSpec.ParasiticIR.Element(
                        id: "c_vdd_sub",
                        kind: .capacitor,
                        nodeA: "vdd",
                        nodeB: nil,
                        value: 1e-15
                    ),
                ]
            )
        )
    }
}
