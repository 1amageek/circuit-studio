import Foundation

/// The timing model of one combinational standard cell: its input pin capacitances (the
/// load it presents to whatever drives it) and a timing arc from each input pin to the
/// output. Keyed by the `CMOSGateNetlist` cell name (e.g. "inv", "nand2", "nor2").
public struct CellTiming: Sendable, Hashable, Codable {
    public let cellName: String
    public let inputCapacitance: [String: Double]   // cell-local input pin -> capacitance (F)
    public let arcs: [TimingArc]

    public init(cellName: String, inputCapacitance: [String: Double], arcs: [TimingArc]) {
        self.cellName = cellName
        self.inputCapacitance = inputCapacitance
        self.arcs = arcs
    }

    public func arc(fromInput pin: String) -> TimingArc? { arcs.first { $0.inputPin == pin } }
}
