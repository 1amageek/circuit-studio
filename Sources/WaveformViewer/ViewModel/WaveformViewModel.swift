import SwiftUI
import CoreSpiceWaveform
import CircuitStudioCore

/// Point data for chart rendering.
public struct ChartPoint: Identifiable {
    public let id: Int
    public let sweep: Double
    public let value: Double
}

/// Series data for a single trace in the chart.
public struct ChartSeries: Identifiable {
    public let id: UUID
    public let name: String
    public let color: Color
    public let points: [ChartPoint]
    public let isComplex: Bool
}

/// ViewModel managing waveform display data.
@Observable
@MainActor
public final class WaveformViewModel {
    public var document: WaveformDocument = WaveformDocument()
    public var chartSeries: [ChartSeries] = []
    public var sweepLabel: String = ""
    public var isComplex: Bool = false

    private var waveformData: WaveformData?
    private let waveformService: WaveformService

    public init(waveformService: WaveformService = WaveformService()) {
        self.waveformService = waveformService
    }

    /// Load waveform data and auto-create traces for all variables.
    public func load(waveform: WaveformData) {
        self.waveformData = waveform
        self.isComplex = waveform.isComplex
        self.sweepLabel = waveform.sweepVariable.name

        let colors: [Color] = [.blue, .red, .green, .orange, .purple, .cyan, .yellow, .pink, .mint, .indigo]

        var traces: [WaveformTrace] = []
        for (index, variable) in waveform.variables.enumerated() {
            let trace = WaveformTrace(
                variableName: variable.name,
                displayName: variable.name,
                color: colors[index % colors.count],
                isVisible: true
            )
            traces.append(trace)
        }

        document.traces = traces
        if let first = waveform.sweepValues.first, let last = waveform.sweepValues.last {
            document.visibleRange = first...last
        }

        updateChartSeries()
    }

    /// Toggle visibility of a trace.
    public func toggleTrace(_ traceID: UUID) {
        if let index = document.traces.firstIndex(where: { $0.id == traceID }) {
            document.traces[index].isVisible.toggle()
            updateChartSeries()
        }
    }

    /// Set the visible sweep range (for zoom/pan).
    public func setVisibleRange(_ range: ClosedRange<Double>) {
        document.visibleRange = range
        updateChartSeries()
    }

    /// Reset zoom to show all data.
    public func resetZoom() {
        guard let waveform = waveformData else { return }
        if let first = waveform.sweepValues.first, let last = waveform.sweepValues.last {
            document.visibleRange = first...last
        }
        updateChartSeries()
    }

    /// Zoom in by 2x centered on cursor or midpoint.
    public func zoomIn() {
        guard let range = document.visibleRange else { return }
        let span = range.upperBound - range.lowerBound
        let center = document.cursorPosition ?? (range.lowerBound + span / 2)
        let newSpan = span / 2
        setVisibleRange((center - newSpan / 2)...(center + newSpan / 2))
    }

    /// Zoom out by 2x centered on cursor or midpoint.
    public func zoomOut() {
        guard let range = document.visibleRange else { return }
        let span = range.upperBound - range.lowerBound
        let center = document.cursorPosition ?? (range.lowerBound + span / 2)
        let newSpan = span * 2
        setVisibleRange((center - newSpan / 2)...(center + newSpan / 2))
    }

    /// Set cursor position.
    public func setCursor(at position: Double?) {
        document.cursorPosition = position
    }

    /// Get the value of a trace at the cursor position.
    public func cursorValue(for trace: WaveformTrace) -> Double? {
        guard let waveform = waveformData,
              let position = document.cursorPosition,
              let varIdx = waveform.variableIndex(named: trace.variableName) else {
            return nil
        }

        // Find nearest sweep point
        let sweepValues = waveform.sweepValues
        guard let nearestIdx = sweepValues.indices.min(by: {
            abs(sweepValues[$0] - position) < abs(sweepValues[$1] - position)
        }) else {
            return nil
        }

        if isComplex {
            return waveform.magnitude(variable: varIdx, point: nearestIdx)
        } else {
            return waveform.realValue(variable: varIdx, point: nearestIdx)
        }
    }

    // MARK: - Private

    private func updateChartSeries() {
        guard let waveform = waveformData else {
            chartSeries = []
            return
        }

        let visibleTraces = document.traces.filter(\.isVisible)
        var series: [ChartSeries] = []

        for trace in visibleTraces {
            guard let varIdx = waveform.variableIndex(named: trace.variableName) else {
                continue
            }

            var points: [ChartPoint] = []
            for pointIdx in 0..<waveform.pointCount {
                let sweep = waveform.sweepValues[pointIdx]

                // Apply range filter
                if let range = document.visibleRange {
                    guard range.contains(sweep) else { continue }
                }

                let value: Double
                if isComplex {
                    value = waveform.magnitudeDB(variable: varIdx, point: pointIdx) ?? 0
                } else {
                    value = waveform.realValue(variable: varIdx, point: pointIdx) ?? 0
                }

                points.append(ChartPoint(id: pointIdx, sweep: sweep, value: value))
            }

            series.append(ChartSeries(
                id: trace.id,
                name: trace.displayName,
                color: trace.color,
                points: points,
                isComplex: isComplex
            ))
        }

        chartSeries = series
    }
}
