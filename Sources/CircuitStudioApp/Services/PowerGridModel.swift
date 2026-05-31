import Foundation

/// A resistive model of a design's power distribution: the VPWR and VGND rails as ladders of
/// resistor segments, with each standard cell drawing its average current between the rails at
/// its tap point. Fed from one end at VDD / ground, the rail's series resistance makes far
/// cells see less than the full supply — the IR drop a real chip must keep within budget. The
/// `IRDropAnalyzer` solves this network in SPICE; this type is just the extracted physics.
public struct PowerGridModel: Sendable, Hashable, Codable {

    /// One cell's connection to the rails: where it taps (x along the rail) and the average
    /// current it draws from VPWR to VGND.
    public struct Tap: Sendable, Hashable, Codable {
        public let label: String
        public let position: Double   // x along the rail (metres)
        public let current: Double    // average current drawn (amperes)

        public init(label: String, position: Double, current: Double) {
            self.label = label; self.position = position; self.current = current
        }
    }

    public let supplyVoltage: Double          // VDD (volts)
    public let railSheetResistance: Double    // rail layer sheet resistance (ohms/square)
    public let railWidth: Double              // rail width (metres)
    public let feedPosition: Double           // x where VPWR=VDD and VGND=0 are applied (metres)
    public let taps: [Tap]

    public init(supplyVoltage: Double, railSheetResistance: Double, railWidth: Double,
                feedPosition: Double, taps: [Tap]) {
        self.supplyVoltage = supplyVoltage
        self.railSheetResistance = railSheetResistance
        self.railWidth = railWidth
        self.feedPosition = feedPosition
        self.taps = taps
    }

    /// Total current drawn by all cells (the current the feed must supply).
    public var totalCurrent: Double { taps.reduce(0) { $0 + $1.current } }

    /// Resistance of a rail run of length `length` (metres) at this width: R = Rsheet · L/W.
    public func resistance(length: Double) -> Double {
        guard railWidth > 0 else { return .infinity }
        return railSheetResistance * (length / railWidth)
    }
}
