import Foundation

/// The timing model of a D flip-flop: the clock→Q propagation (NLDM, by output load) and
/// the setup / hold constraints at the D pin relative to the active clock edge. These
/// bound a synchronous path: the launch edge starts at clk→Q, and the capture edge
/// requires data to arrive no later than `period − setup` (setup) and no earlier than
/// `hold` (hold).
public struct SequentialTiming: Sendable, Hashable, Codable {
    public let clkToQRise: TimingLUT       // clk edge -> Q rising delay, by output load
    public let clkToQFall: TimingLUT       // clk edge -> Q falling delay, by output load
    public let qTransitionRise: TimingLUT  // Q rising output slew, by output load
    public let qTransitionFall: TimingLUT  // Q falling output slew, by output load
    public let setupTime: Double           // seconds the data must be stable before the edge
    public let holdTime: Double            // seconds the data must be stable after the edge
    public let dataCapacitance: Double     // load the D pin presents (F)
    public let clockCapacitance: Double    // load the CLK pin presents (F)

    public init(clkToQRise: TimingLUT, clkToQFall: TimingLUT,
                qTransitionRise: TimingLUT, qTransitionFall: TimingLUT,
                setupTime: Double, holdTime: Double,
                dataCapacitance: Double, clockCapacitance: Double) {
        self.clkToQRise = clkToQRise
        self.clkToQFall = clkToQFall
        self.qTransitionRise = qTransitionRise
        self.qTransitionFall = qTransitionFall
        self.setupTime = setupTime
        self.holdTime = holdTime
        self.dataCapacitance = dataCapacitance
        self.clockCapacitance = clockCapacitance
    }

    public func clkToQ(outputEdge: TimingEdge) -> TimingLUT { outputEdge == .rise ? clkToQRise : clkToQFall }
    public func qTransition(outputEdge: TimingEdge) -> TimingLUT { outputEdge == .rise ? qTransitionRise : qTransitionFall }
}
