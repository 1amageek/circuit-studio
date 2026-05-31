import Foundation

/// Checks a `PowerGridModel`'s rail segments against an electromigration current-density
/// limit. Current flows from the feed toward the cells, so each segment carries the summed
/// current of every cell beyond it — the segment nearest the feed carries the whole design's
/// current and is the EM hot spot. Density = segment current / rail width (A per metre of
/// width). Exceeding the limit means the metal will void over time — a reliability failure the
/// chip ships with, invisible to DRC/LVS.
public struct ElectromigrationChecker: Sendable {

    public struct SegmentCurrent: Sendable, Hashable, Codable {
        public let label: String
        public let current: Double               // amperes carried by this segment
        public let widthMeters: Double
        public let densityAmperesPerMeter: Double
    }

    public struct Result: Sendable, Hashable, Codable {
        public let segments: [SegmentCurrent]
        public let limitAmperesPerMeter: Double
        public var worstDensity: Double { segments.map(\.densityAmperesPerMeter).max() ?? 0 }
        public var worstSegment: String? { segments.max(by: { $0.densityAmperesPerMeter < $1.densityAmperesPerMeter })?.label }
        public var passed: Bool { worstDensity <= limitAmperesPerMeter }
    }

    public init() {}

    public func check(_ model: PowerGridModel, limitAmperesPerMeter: Double) -> Result {
        let sorted = model.taps.sorted { $0.position < $1.position }
        // Cumulative current carried by each segment: from the feed segment (all cells) outward.
        var segments: [SegmentCurrent] = []
        for index in sorted.indices {
            // The segment leading INTO tap `index` carries the current of taps index..end.
            let current = sorted[index...].reduce(0) { $0 + $1.current }
            let density = model.railWidth > 0 ? current / model.railWidth : .infinity
            let label = index == 0 ? "feed→\(sorted[0].label)" : "\(sorted[index - 1].label)→\(sorted[index].label)"
            segments.append(SegmentCurrent(label: label, current: current,
                                           widthMeters: model.railWidth, densityAmperesPerMeter: density))
        }
        return Result(segments: segments, limitAmperesPerMeter: limitAmperesPerMeter)
    }
}
