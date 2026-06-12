import Foundation
import CircuitStudioCore
import SchematicEditor

/// Builds the sample content seeded into a newly created project.
///
/// Mirrors the guided first-run experience of IDE project templates: a new
/// project opens with a complete, working circuit — schematic drawn, netlist
/// loaded, simulation configured — so the user can press Run immediately and
/// then modify a known-good starting point.
@MainActor
public enum NewProjectTemplate {

    /// The transient analysis the sample netlist and simulation config share.
    private static let transientSpec = TranSpec(stopTime: 100e-9, stepTime: 0.1e-9)

    /// The CMOS inverter — the canonical "hello world" of IC design.
    ///
    /// The schematic carries explicit per-instance model parameters, so the
    /// generated netlist simulates without any external PDK or model library.
    public static func cmosInverter() -> ProjectTemplateContent {
        let document = SchematicPreview.cmosInverterViewModel().document
        let testbench = Testbench(
            name: "Transient",
            analysisCommands: [.tran(transientSpec)]
        )
        let generated = NetlistGenerator().generate(
            from: document,
            title: "CMOS Inverter",
            testbench: testbench
        )
        let netlist = guideHeader + generated
        return ProjectTemplateContent(
            netlistFileName: "top.cir",
            netlist: netlist,
            schematicPlacement: SchematicPlacement(
                sourceNetlist: netlist,
                document: document
            ),
            simulationConfig: SimulationConfig(selectedAnalysis: .tran(transientSpec))
        )
    }

    /// Orientation comments prepended to the sample netlist. SPICE treats
    /// `*`-prefixed lines as comments, so the file stays runnable as-is.
    private static let guideHeader = """
    * Welcome to Circuit Studio!
    * This sample project is a CMOS inverter driven by a pulse input:
    *   - The Schematic tab shows this circuit drawn and editable.
    *   - Press Run to simulate; the in/out waveforms appear in the viewer.
    *   - The .tran line near the end selects the transient analysis.
    * Edit values below or rewire the schematic, then run again.

    """
}
