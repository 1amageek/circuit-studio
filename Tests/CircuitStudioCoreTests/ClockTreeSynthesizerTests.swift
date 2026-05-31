import Foundation
import Testing
@testable import CircuitStudioApp

/// BC2 — clock-tree synthesis. Tool-independent checks that the balanced buffer tree caps
/// per-buffer fanout, scales its depth logarithmically with the sink count, and keeps the
/// worst-case skew within a bound — the CTS constraint a multi-row design must satisfy.
@Suite("Clock-tree synthesis")
struct ClockTreeSynthesizerTests {

    @Test("A balanced tree caps fanout and bounds skew well under its insertion delay")
    func balancedTreeBoundsSkew() throws {
        let cts = ClockTreeSynthesizer(bufferBaseDelay: 30e-12, bufferLoadSlope: 8e-12, maxFanout: 4)
        for sinks in [4, 7, 8, 16, 30, 64, 240] {
            let tree = try cts.synthesize(sinkCount: sinks)
            #expect(tree.maxFanoutUsed <= 4, "fanout cap exceeded for \(sinks) sinks")
            #expect(tree.skew >= 0)
            // Worst-case skew stays within one fanout-unit of slope per level.
            #expect(tree.skew <= Double(tree.levels) * 8e-12 + 1e-15, "skew \(tree.skew) for \(sinks) sinks")
            // The tree is useful: skew is a small fraction of the clock insertion delay.
            #expect(tree.skew < tree.insertionDelay, "skew must be below insertion delay")
        }
    }

    @Test("Depth grows logarithmically with the number of sinks")
    func depthIsLogarithmic() throws {
        let cts = ClockTreeSynthesizer(maxFanout: 4)
        #expect(try cts.synthesize(sinkCount: 1).levels == 0)    // a single sink needs no buffer
        #expect(try cts.synthesize(sinkCount: 4).levels == 1)    // 4 -> 1
        #expect(try cts.synthesize(sinkCount: 16).levels == 2)   // 16 -> 4 -> 1
        #expect(try cts.synthesize(sinkCount: 64).levels == 3)   // 64 -> 16 -> 4 -> 1
        #expect(try cts.synthesize(sinkCount: 65).levels == 4)   // just past a power -> one more
    }

    @Test("A perfectly balanced power-of-fanout tree has zero skew")
    func powerOfFanoutZeroSkew() throws {
        let cts = ClockTreeSynthesizer(maxFanout: 4)
        for sinks in [4, 16, 64] {
            let tree = try cts.synthesize(sinkCount: sinks)
            #expect(abs(tree.skew) < 1e-15, "\(sinks) sinks should be skew-free, got \(tree.skew)")
        }
    }

    @Test("CTS rejects an empty sink set and an invalid fanout (never silently)")
    func rejectsInvalidInput() {
        #expect(throws: ClockTreeSynthesizer.CTSError.noSinks) {
            _ = try ClockTreeSynthesizer().synthesize(sinkCount: 0)
        }
        #expect(throws: ClockTreeSynthesizer.CTSError.invalidFanout) {
            _ = try ClockTreeSynthesizer(maxFanout: 1).synthesize(sinkCount: 8)
        }
    }
}
