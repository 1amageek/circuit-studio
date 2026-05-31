import Foundation

/// A level-1 (Shichman–Hodges) MOSFET model pair the timing characterizer drives in
/// CoreSpice — the same model envelope the CoreSpice⇔ngspice trust gate validates, so the
/// timing numbers rest on physics CoreSpice is known to compute correctly. Level-1 basic
/// I–V carries no intrinsic gate capacitance, so the characterizer models load EXPLICITLY:
/// `inputCapacitance` is derived here from oxide capacitance × gate area and applied as a
/// lumped cap both when characterizing (the swept output load) and when validating against
/// SPICE (a load on each path net), keeping the abstraction self-consistent.
public struct Level1DeviceModel: Sendable, Hashable, Codable {

    public let supplyVoltage: Double      // VDD (volts)
    public let nmosModelName: String
    public let pmosModelName: String
    public let nmosCard: String           // ".model NM NMOS level=1 ..."
    public let pmosCard: String
    public let oxideCapPerArea: Double     // Cox (F/m^2), for the lumped input-cap model

    public init(supplyVoltage: Double, nmosModelName: String, pmosModelName: String,
                nmosCard: String, pmosCard: String, oxideCapPerArea: Double) {
        self.supplyVoltage = supplyVoltage
        self.nmosModelName = nmosModelName
        self.pmosModelName = pmosModelName
        self.nmosCard = nmosCard
        self.pmosCard = pmosCard
        self.oxideCapPerArea = oxideCapPerArea
    }

    /// Sky130-like level-1 parameters (the trust-gate inverter deck's models): 1.8 V rails,
    /// asymmetric NMOS/PMOS drive, and an oxide capacitance giving ~0.5 fF per minimum FET.
    public static func sky130Like() -> Level1DeviceModel {
        Level1DeviceModel(
            supplyVoltage: 1.8,
            nmosModelName: "NM", pmosModelName: "PM",
            nmosCard: ".model NM NMOS level=1 vto=0.45 kp=120u lambda=0.1 gamma=0.4 phi=0.65",
            pmosCard: ".model PM PMOS level=1 vto=-0.45 kp=40u lambda=0.1 gamma=0.4 phi=0.65",
            oxideCapPerArea: 8.5e-3
        )
    }

    /// Both `.model` cards, one per line.
    public var modelCards: String { "\(nmosCard)\n\(pmosCard)" }

    /// The lumped input capacitance a cell pin presents: Cox × Σ(W·L) over the devices that
    /// pin gates (W, L are in microns in `Device`, converted to metres here).
    public func inputCapacitance(of cell: CMOSGateNetlist, pin: String) -> Double {
        let micron = 1e-6
        var area = 0.0
        for device in cell.devices where device.gate == pin {
            let w = device.width * micron
            let l = device.length * micron
            area += w * l
        }
        return oxideCapPerArea * area
    }
}
