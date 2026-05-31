import Foundation

/// One gate hop along a timing path: which cell, which input pin switched, the resulting
/// output edge, and the stage delay / output slew / load the analyzer computed. The
/// ordered stages of the critical path are exactly what `STAvsSPICEValidator` re-simulates
/// in SPICE and what the Explain stage shows a human.
public struct TimingStage: Sendable, Hashable, Codable {
    public let instance: String
    public let cell: String
    public let inputPin: String       // cell-local pin (e.g. "A")
    public let inputNet: String
    public let outputNet: String
    public let inputEdge: TimingEdge
    public let outputEdge: TimingEdge
    public let stageDelay: Double      // seconds
    public let outputSlew: Double      // seconds
    public let load: Double            // farads driven by this stage

    public init(instance: String, cell: String, inputPin: String, inputNet: String,
                outputNet: String, inputEdge: TimingEdge, outputEdge: TimingEdge,
                stageDelay: Double, outputSlew: Double, load: Double) {
        self.instance = instance; self.cell = cell; self.inputPin = inputPin
        self.inputNet = inputNet; self.outputNet = outputNet
        self.inputEdge = inputEdge; self.outputEdge = outputEdge
        self.stageDelay = stageDelay; self.outputSlew = outputSlew; self.load = load
    }
}

/// A launch→capture data path: from a flip-flop Q (or primary input) to a flip-flop D (or
/// primary output), with the per-stage breakdown. `delay` includes the launch clk→Q.
public struct TimingPath: Sendable, Hashable, Codable {
    public let startpoint: String      // launch net (Q of a flip-flop, or a primary input)
    public let endpoint: String        // capture net (D of a flip-flop, or a primary output)
    public let launchDelay: Double     // clk->Q at the startpoint (0 for a primary input)
    public let launchSlew: Double      // input slew at the startpoint for the path's first edge
    public let startEdge: TimingEdge   // the launching edge at the startpoint
    public let stages: [TimingStage]
    public let arrival: Double          // data arrival at the endpoint (launch + sum of stages)

    public init(startpoint: String, endpoint: String, launchDelay: Double, launchSlew: Double,
                startEdge: TimingEdge, stages: [TimingStage], arrival: Double) {
        self.startpoint = startpoint; self.endpoint = endpoint
        self.launchDelay = launchDelay; self.launchSlew = launchSlew; self.startEdge = startEdge
        self.stages = stages; self.arrival = arrival
    }

    /// The combinational delay along the path (excluding the launch clk→Q) — the sum of the
    /// per-stage gate delays, which the SPICE validator re-simulates.
    public var combinationalDelay: Double { stages.reduce(0) { $0 + $1.stageDelay } }
}

/// The setup (and hold) result at one capture endpoint.
public struct EndpointSlack: Sendable, Hashable, Codable {
    public let endpoint: String
    public let dataArrival: Double     // latest data arrival (setup) — includes clk->Q
    public let required: Double        // period - setup
    public let setupSlack: Double      // required - dataArrival
    public let earliestArrival: Double // earliest data arrival (hold)
    public let holdSlack: Double       // earliestArrival - hold

    public init(endpoint: String, dataArrival: Double, required: Double, setupSlack: Double,
                earliestArrival: Double, holdSlack: Double) {
        self.endpoint = endpoint; self.dataArrival = dataArrival; self.required = required
        self.setupSlack = setupSlack; self.earliestArrival = earliestArrival; self.holdSlack = holdSlack
    }
}

/// The static-timing result for a design at a clock period: worst slacks, the achievable
/// clock frequency, the critical path, and every endpoint. `met` is the single timing
/// verdict `MultiConstraintSignoff` folds together with functional + physical signoff.
public struct TimingReport: Sendable, Hashable, Codable {
    public let clockPeriod: Double
    public let worstSetupSlack: Double
    public let worstHoldSlack: Double
    public let minPeriod: Double       // smallest period with non-negative setup slack
    public let criticalPath: TimingPath
    public let endpoints: [EndpointSlack]

    public init(clockPeriod: Double, worstSetupSlack: Double, worstHoldSlack: Double,
                minPeriod: Double, criticalPath: TimingPath, endpoints: [EndpointSlack]) {
        self.clockPeriod = clockPeriod; self.worstSetupSlack = worstSetupSlack
        self.worstHoldSlack = worstHoldSlack; self.minPeriod = minPeriod
        self.criticalPath = criticalPath; self.endpoints = endpoints
    }

    public var setupMet: Bool { worstSetupSlack >= 0 }
    public var holdMet: Bool { worstHoldSlack >= 0 }
    public var met: Bool { setupMet && holdMet }
    public var fmaxHz: Double { minPeriod > 0 ? 1.0 / minPeriod : .infinity }
}
