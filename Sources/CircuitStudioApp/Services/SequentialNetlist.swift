import Foundation

/// A sequential circuit: combinational standard-cell instances plus edge-triggered D
/// flip-flops, wired by net name. This is the INTENT for a clocked design (a datapath +
/// control), one level above the purely combinational `GateLevelNetlist`. The logic
/// simulator clocks it; the synthesizer (later) places & routes it.
public struct SequentialNetlist: Sendable, Hashable {

    /// A positive-edge-triggered D flip-flop: `q` takes `d` on each rising `clk` edge.
    public struct DFF: Sendable, Hashable {
        public let name: String
        public let d: String
        public let clk: String
        public let q: String
        public init(name: String, d: String, clk: String, q: String) {
            self.name = name; self.d = d; self.clk = clk; self.q = q
        }
    }

    public let name: String
    public let combinational: [GateLevelNetlist.Instance]
    public let dffs: [DFF]
    public let inputs: [String]
    public let outputs: [String]
    public let clock: String
    public let vpwr: String
    public let vgnd: String

    public init(name: String, combinational: [GateLevelNetlist.Instance], dffs: [DFF],
                inputs: [String], outputs: [String], clock: String = "clk",
                vpwr: String = "VPWR", vgnd: String = "VGND") {
        self.name = name
        self.combinational = combinational
        self.dffs = dffs
        self.inputs = inputs
        self.outputs = outputs
        self.clock = clock
        self.vpwr = vpwr
        self.vgnd = vgnd
    }
}
