import Foundation
import CircuitStudioCore

/// Materialized content a freshly created project is seeded with, so a new
/// project opens as a working example instead of an empty directory.
public struct ProjectTemplateContent: Sendable {
    /// File name of the sample netlist at the project root (e.g. `top.cir`).
    public let netlistFileName: String

    /// The sample SPICE netlist, runnable as-is by the in-app simulator.
    public let netlist: String

    /// The design cells installed under `cells/`, schematics included.
    public let cells: [DesignCell]

    /// Name of the hierarchy root recorded in the project manifest.
    public let topCellName: String

    /// Name of the initially active cell recorded in the project manifest.
    public let activeCellName: String

    /// Simulation settings matching the analysis embedded in the netlist.
    public let simulationConfig: SimulationConfig

    public init(
        netlistFileName: String,
        netlist: String,
        cells: [DesignCell],
        topCellName: String,
        activeCellName: String,
        simulationConfig: SimulationConfig
    ) {
        self.netlistFileName = netlistFileName
        self.netlist = netlist
        self.cells = cells
        self.topCellName = topCellName
        self.activeCellName = activeCellName
        self.simulationConfig = simulationConfig
    }
}
