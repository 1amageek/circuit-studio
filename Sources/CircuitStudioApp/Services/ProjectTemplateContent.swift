import Foundation
import CircuitStudioCore

/// Materialized content a freshly created project is seeded with, so a new
/// project opens as a working example instead of an empty directory.
public struct ProjectTemplateContent: Sendable {
    /// File name of the sample netlist at the project root (e.g. `top.cir`).
    public let netlistFileName: String

    /// The sample SPICE netlist, runnable as-is by the in-app simulator.
    public let netlist: String

    /// The drawn schematic matching the netlist, shown in the schematic editor.
    public let schematicPlacement: SchematicPlacement

    /// Simulation settings matching the analysis embedded in the netlist.
    public let simulationConfig: SimulationConfig

    public init(
        netlistFileName: String,
        netlist: String,
        schematicPlacement: SchematicPlacement,
        simulationConfig: SimulationConfig
    ) {
        self.netlistFileName = netlistFileName
        self.netlist = netlist
        self.schematicPlacement = schematicPlacement
        self.simulationConfig = simulationConfig
    }
}
