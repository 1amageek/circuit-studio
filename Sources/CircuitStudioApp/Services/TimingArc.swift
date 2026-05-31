import Foundation

/// How an input edge maps to the output edge of a combinational cell. The synthesized
/// primitives (INV, NAND, NOR) are all inverting, so a rising input produces a falling
/// output and vice versa — but the model is explicit so non-inverting cells can be added.
public enum TimingSense: String, Sendable, Hashable, Codable {
    case negativeUnate   // input rise -> output fall, input fall -> output rise
    case positiveUnate   // input rise -> output rise, input fall -> output fall

    /// The output edge produced by the given input edge under this sense.
    public func outputEdge(for input: TimingEdge) -> TimingEdge {
        switch self {
        case .positiveUnate: return input
        case .negativeUnate: return input.inverted
        }
    }
}

/// A signal transition direction.
public enum TimingEdge: String, Sendable, Hashable, Codable {
    case rise
    case fall
    public var inverted: TimingEdge { self == .rise ? .fall : .rise }
}

/// A combinational timing arc from one input pin to the cell output: NLDM delay and output
/// transition (slew) tables for each resulting output edge, the standard Liberty arc.
public struct TimingArc: Sendable, Hashable, Codable {
    public let inputPin: String          // cell-local input net (e.g. "A", "B")
    public let sense: TimingSense
    public let delayRise: TimingLUT      // cell delay when the output rises
    public let delayFall: TimingLUT      // cell delay when the output falls
    public let transitionRise: TimingLUT // output slew when the output rises
    public let transitionFall: TimingLUT // output slew when the output falls

    public init(inputPin: String, sense: TimingSense,
                delayRise: TimingLUT, delayFall: TimingLUT,
                transitionRise: TimingLUT, transitionFall: TimingLUT) {
        self.inputPin = inputPin
        self.sense = sense
        self.delayRise = delayRise
        self.delayFall = delayFall
        self.transitionRise = transitionRise
        self.transitionFall = transitionFall
    }

    public func delay(outputEdge: TimingEdge) -> TimingLUT { outputEdge == .rise ? delayRise : delayFall }
    public func transition(outputEdge: TimingEdge) -> TimingLUT { outputEdge == .rise ? transitionRise : transitionFall }
}
