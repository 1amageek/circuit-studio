import SwiftUI
import AppKit
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
    public var isLogFrequency: Bool = false

    public private(set) var waveformData: WaveformData?
    private let waveformService: WaveformService

    /// True when loaded data is a single operating point (no sweep).
    public var isSinglePoint: Bool {
        waveformData?.pointCount == 1
    }

    public init(waveformService: WaveformService = WaveformService()) {
        self.waveformService = waveformService
    }

    /// Load waveform data and auto-create traces for all variables.
    public func load(waveform: WaveformData) {
        self.waveformData = waveform
        self.isComplex = waveform.isComplex
        self.isLogFrequency = waveform.sweepVariable.type == .frequency
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

    /// Update waveform data progressively, preserving existing trace visibility.
    ///
    /// Unlike `load()`, this method keeps the user's trace visibility choices
    /// and only updates the underlying data and sweep range.
    public func updateStreaming(waveform: WaveformData) {
        let previousVisibility: [String: Bool]
        if !document.traces.isEmpty {
            previousVisibility = Dictionary(
                document.traces.map { ($0.variableName, $0.isVisible) },
                uniquingKeysWith: { first, _ in first }
            )
        } else {
            previousVisibility = [:]
        }

        self.waveformData = waveform
        self.isComplex = waveform.isComplex
        self.isLogFrequency = waveform.sweepVariable.type == .frequency
        self.sweepLabel = waveform.sweepVariable.name

        let colors: [Color] = [.blue, .red, .green, .orange, .purple, .cyan, .yellow, .pink, .mint, .indigo]

        // Rebuild traces, preserving visibility from previous state
        if document.traces.isEmpty || document.traces.count != waveform.variables.count {
            var traces: [WaveformTrace] = []
            for (index, variable) in waveform.variables.enumerated() {
                let isVisible = previousVisibility[variable.name] ?? true
                let trace = WaveformTrace(
                    variableName: variable.name,
                    displayName: variable.name,
                    color: colors[index % colors.count],
                    isVisible: isVisible
                )
                traces.append(trace)
            }
            document.traces = traces
        }

        // Always expand the visible range to include all data
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

    /// Last export error, surfaced to the UI.
    public var exportError: String?

    /// Export the current waveform data to a file chosen by the user.
    public func exportWaveform() {
        guard let waveform = waveformData else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "csv")!,
            .init(filenameExtension: "raw")!,
        ]
        panel.nameFieldStringValue = "simulation.csv"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        exportError = nil
        Task {
            do {
                try await waveformService.export(waveform: waveform, to: url)
            } catch {
                exportError = error.localizedDescription
            }
        }
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

    // MARK: - Terminal Integration

    /// Show only the variables corresponding to PORT components.
    ///
    /// When `resolved` is non-empty, only those variables are shown as traces.
    /// When empty, the existing traces are left unchanged (all variables shown).
    public func applyTerminalComponents(_ resolved: [ResolvedTerminal]) {
        guard let waveform = waveformData else { return }
        guard !resolved.isEmpty else { return }

        let colors: [Color] = [.blue, .red, .green, .orange, .purple, .cyan, .yellow, .pink]
        var traces: [WaveformTrace] = []
        for (index, terminal) in resolved.enumerated() {
            guard waveform.variableIndex(named: terminal.variableName) != nil else { continue }
            traces.append(WaveformTrace(
                variableName: terminal.variableName,
                displayName: terminal.label,
                color: colors[index % colors.count],
                isVisible: true
            ))
        }

        document.traces = traces
        updateChartSeries()
    }

    // MARK: - Private

    private func updateChartSeries() {
        guard let waveform = waveformData else {
            chartSeries = []
            return
        }

        // Apply decimation for large datasets
        let maxDisplayPoints = 2000
        let displayWaveform: WaveformData
        if waveform.pointCount > maxDisplayPoints, !waveform.isComplex {
            displayWaveform = waveformService.fetch(
                waveform: waveform,
                variables: [],
                range: document.visibleRange,
                maxPoints: maxDisplayPoints
            )
        } else {
            displayWaveform = waveform
        }

        let visibleTraces = document.traces.filter(\.isVisible)
        var series: [ChartSeries] = []
        let rangeAlreadyApplied = waveform.pointCount > maxDisplayPoints && !waveform.isComplex

        for trace in visibleTraces {
            guard let varIdx = displayWaveform.variableIndex(named: trace.variableName) else {
                continue
            }

            var points: [ChartPoint] = []
            for pointIdx in 0..<displayWaveform.pointCount {
                let sweep = displayWaveform.sweepValues[pointIdx]

                // Skip range filter if decimation already applied it
                if !rangeAlreadyApplied, let range = document.visibleRange {
                    guard range.contains(sweep) else { continue }
                }

                let value: Double
                if isComplex {
                    value = displayWaveform.magnitudeDB(variable: varIdx, point: pointIdx) ?? 0
                } else {
                    value = displayWaveform.realValue(variable: varIdx, point: pointIdx) ?? 0
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
