import Foundation

public struct RunReviewWaveformPreview: Sendable, Hashable {
    public let sweepColumn: String
    public let sampleCount: Int
    public let signalCount: Int
    public let sweepStart: Double?
    public let sweepEnd: Double?
    public let signals: [RunReviewWaveformSignalPreview]

    public init(
        sweepColumn: String,
        sampleCount: Int,
        signalCount: Int,
        sweepStart: Double?,
        sweepEnd: Double?,
        signals: [RunReviewWaveformSignalPreview]
    ) {
        self.sweepColumn = sweepColumn
        self.sampleCount = sampleCount
        self.signalCount = signalCount
        self.sweepStart = sweepStart
        self.sweepEnd = sweepEnd
        self.signals = signals
    }
}

public struct RunReviewWaveformSignalPreview: Sendable, Hashable {
    public let name: String
    public let numericSampleCount: Int
    public let firstValue: Double?
    public let lastValue: Double?
    public let minValue: Double?
    public let maxValue: Double?
    public let samples: [RunReviewWaveformSamplePreview]

    public init(
        name: String,
        numericSampleCount: Int,
        firstValue: Double?,
        lastValue: Double?,
        minValue: Double?,
        maxValue: Double?,
        samples: [RunReviewWaveformSamplePreview] = []
    ) {
        self.name = name
        self.numericSampleCount = numericSampleCount
        self.firstValue = firstValue
        self.lastValue = lastValue
        self.minValue = minValue
        self.maxValue = maxValue
        self.samples = samples
    }
}

public struct RunReviewWaveformSamplePreview: Sendable, Hashable {
    public let sweepValue: Double
    public let signalValue: Double

    public init(sweepValue: Double, signalValue: Double) {
        self.sweepValue = sweepValue
        self.signalValue = signalValue
    }
}
