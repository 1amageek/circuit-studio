import Foundation

/// Synthesizes a balanced clock-buffer tree over a design's flip-flop clock pins and
/// reports the resulting skew — the timing constraint a multi-row design must satisfy
/// before its sequential paths can be trusted. A single clock net driving every flip-flop
/// directly has unbounded skew (one driver, huge load); CTS inserts a tree of buffers so
/// every sink is the same depth from the root, leaving only the (modeled) skew from
/// uneven last-stage fanout. The skew model uses the SPICE-characterized buffer delay
/// (base + load slope), so the number it reports is anchored to the same physics as STA.
public struct ClockTreeSynthesizer: Sendable {

    public enum CTSError: Error, LocalizedError, Equatable {
        case noSinks
        case invalidFanout

        public var errorDescription: String? {
            switch self {
            case .noSinks: return "Clock-tree synthesis needs at least one clock sink."
            case .invalidFanout: return "The maximum buffer fanout must be >= 2."
            }
        }
    }

    /// One buffer in the tree (its fanout and the level it sits at, 1 = nearest the sinks).
    public struct Buffer: Sendable, Hashable {
        public let level: Int
        public let fanout: Int
    }

    public struct ClockTree: Sendable {
        public let levels: Int
        public let buffers: [Buffer]
        public let sinkCount: Int
        public let insertionDelay: Double   // root→sink delay along the slowest (all-ceil) path
        public let minPathDelay: Double     // along the fastest (all-floor) path
        public var bufferCount: Int { buffers.count }
        /// Worst-case skew: the spread between the slowest and fastest root→sink paths.
        public var skew: Double { insertionDelay - minPathDelay }
        public var maxFanoutUsed: Int { buffers.map(\.fanout).max() ?? 0 }
    }

    /// Per-buffer delay model: `base + slope * fanout` (seconds), matching the NLDM trend
    /// (a heavier load is a slower buffer).
    public let bufferBaseDelay: Double
    public let bufferLoadSlope: Double
    public let maxFanout: Int

    public init(bufferBaseDelay: Double = 30e-12, bufferLoadSlope: Double = 8e-12, maxFanout: Int = 4) {
        self.bufferBaseDelay = bufferBaseDelay
        self.bufferLoadSlope = bufferLoadSlope
        self.maxFanout = maxFanout
    }

    /// Build a balanced tree over `sinkCount` clock pins: every sink ends the same number of
    /// buffer stages from the root, and each stage's fanout is spread as evenly as possible.
    public func synthesize(sinkCount: Int) throws -> ClockTree {
        guard sinkCount >= 1 else { throw CTSError.noSinks }
        guard maxFanout >= 2 else { throw CTSError.invalidFanout }

        // Group sizes per level, from the sinks up to a single root. `counts[0]` is the sink
        // count; each subsequent level has ceil(prev / maxFanout) buffers.
        var levelCounts = [sinkCount]
        while levelCounts.last! > 1 {
            let prev = levelCounts.last!
            levelCounts.append((prev + maxFanout - 1) / maxFanout)
        }
        let levels = levelCounts.count - 1   // number of BUFFER stages (sinks are level 0)
        if levels == 0 {
            return ClockTree(levels: 0, buffers: [], sinkCount: sinkCount, insertionDelay: 0, minPathDelay: 0)
        }

        // Per stage, spread the children evenly across the parents: each parent buffer takes
        // either ceil or floor children. The slowest root→sink path runs through a ceil buffer
        // at every stage; the fastest through a floor buffer — their gap is the worst-case skew.
        var minPath = 0.0, maxPath = 0.0
        var buffers: [Buffer] = []
        for stage in 1...levels {
            let children = levelCounts[stage - 1]
            let parents = levelCounts[stage]
            let ceilFanout = (children + parents - 1) / parents
            let floorFanout = max(children / parents, 1)
            let heavy = children % parents == 0 ? parents : children % parents
            for p in 0..<parents {
                buffers.append(Buffer(level: stage, fanout: p < heavy ? ceilFanout : floorFanout))
            }
            maxPath += bufferBaseDelay + bufferLoadSlope * Double(ceilFanout)
            minPath += bufferBaseDelay + bufferLoadSlope * Double(floorFanout)
        }
        return ClockTree(levels: levels, buffers: buffers, sinkCount: sinkCount,
                         insertionDelay: maxPath, minPathDelay: minPath)
    }
}
