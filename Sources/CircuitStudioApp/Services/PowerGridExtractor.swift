import Foundation

/// Builds a `PowerGridModel` from a gate-level netlist's intended floorplan: cells are placed
/// along a row at a fixed pitch, each tapping the rail at its position and drawing an average
/// current scaled by its transistor count (a switching-activity estimate). The rail is modeled
/// on its power-distribution layer (met1 by default — real standard-cell rows strap power on
/// metal, not just the resistive li1), fed from one end. This is the physical input the
/// `IRDropAnalyzer` and `ElectromigrationChecker` consume.
public struct PowerGridExtractor: Sendable {

    public let supplyVoltage: Double
    public let railSheetResistance: Double   // ohms/square (met1 ≈ 0.125, li1 ≈ 12.8)
    public let railWidth: Double             // metres
    public let cellPitch: Double             // placed cell pitch (metres)
    public let currentPerTransistor: Double  // average current per FET (amperes)

    public init(supplyVoltage: Double = 1.8,
                railSheetResistance: Double = 0.125,   // met1 power rail
                railWidth: Double = 0.6e-6,            // a power rail, wider than a signal track
                cellPitch: Double = 1.5e-6,
                currentPerTransistor: Double = 0.5e-6) {
        self.supplyVoltage = supplyVoltage
        self.railSheetResistance = railSheetResistance
        self.railWidth = railWidth
        self.cellPitch = cellPitch
        self.currentPerTransistor = currentPerTransistor
    }

    public func extract(_ netlist: GateLevelNetlist) -> PowerGridModel {
        var taps: [PowerGridModel.Tap] = []
        for (index, inst) in netlist.instances.enumerated() {
            let position = Double(index + 1) * cellPitch
            let current = currentPerTransistor * Double(inst.cell.devices.count)
            taps.append(PowerGridModel.Tap(label: inst.name, position: position, current: current))
        }
        return PowerGridModel(
            supplyVoltage: supplyVoltage,
            railSheetResistance: railSheetResistance,
            railWidth: railWidth,
            feedPosition: 0,
            taps: taps)
    }
}
