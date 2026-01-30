import Foundation
import CoreSpiceWaveform

/// Display state for the waveform viewer.
public struct WaveformDocument: Sendable {
    public var traces: [WaveformTrace]
    public var visibleRange: ClosedRange<Double>?
    public var cursorPosition: Double?
    public var deltaCursorPosition: Double?

    public init(
        traces: [WaveformTrace] = [],
        visibleRange: ClosedRange<Double>? = nil,
        cursorPosition: Double? = nil,
        deltaCursorPosition: Double? = nil
    ) {
        self.traces = traces
        self.visibleRange = visibleRange
        self.cursorPosition = cursorPosition
        self.deltaCursorPosition = deltaCursorPosition
    }
}
