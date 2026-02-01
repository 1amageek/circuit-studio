import SwiftUI
import AppKit
import Charts

/// Main waveform chart view using Swift Charts with cursor, zoom, and pan support.
public struct WaveformChartView: View {
    @Bindable var viewModel: WaveformViewModel
    @State private var chartProxy: ChartProxy?
    @State private var dragSelectionStart: Double?
    @State private var dragSelectionEnd: Double?

    public init(viewModel: WaveformViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            if viewModel.chartSeries.isEmpty {
                ContentUnavailableView(
                    "No Waveform Data",
                    systemImage: "waveform.path",
                    description: Text("Run a simulation to see waveforms")
                )
            } else if viewModel.isSinglePoint {
                operatingPointView
            } else {
                chartView
                zoomControlBar
            }
        }
    }

    @ViewBuilder
    private var chartView: some View {
        Chart {
            ForEach(viewModel.chartSeries) { series in
                ForEach(series.points) { point in
                    LineMark(
                        x: .value(viewModel.sweepLabel, point.sweep),
                        y: .value(series.name, point.value)
                    )
                    .foregroundStyle(series.color)
                    .foregroundStyle(by: .value("Signal", series.name))
                }
            }

            if let cursor = viewModel.document.cursorPosition {
                RuleMark(x: .value("Cursor", cursor))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text(formatSweep(cursor))
                            .font(.caption2.monospacedDigit())
                            .padding(2)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 3))
                    }
            }

            if let start = dragSelectionStart, let end = dragSelectionEnd {
                let lower = min(start, end)
                let upper = max(start, end)
                RectangleMark(
                    xStart: .value("Selection Start", lower),
                    xEnd: .value("Selection End", upper)
                )
                .foregroundStyle(.blue.opacity(0.15))

                RuleMark(x: .value("Selection Start", lower))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.blue.opacity(0.5))

                RuleMark(x: .value("Selection End", upper))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.blue.opacity(0.5))
            }
        }
        .chartXAxisLabel(xAxisLabel)
        .chartYAxisLabel(viewModel.isComplex ? "Magnitude (dB)" : "Value")
        .chartXScale(domain: xDomain, type: viewModel.isLogFrequency ? .log : .linear)
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(formatAxisValue(v))
                            .font(.caption2.monospacedDigit())
                    }
                }
            }
        }
        .chartLegend(position: .top)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .background {
                        ScrollPanView { deltaX in
                            guard let frame = proxy.plotFrame else { return }
                            let plotWidth = geometry[frame].width
                            guard plotWidth > 0 else { return }
                            viewModel.pan(byFraction: Double(deltaX) / Double(plotWidth))
                        }
                    }
                    .onTapGesture { location in
                        handleTap(at: location, proxy: proxy, geometry: geometry)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                handleDragSelection(value: value, proxy: proxy, geometry: geometry)
                            }
                            .onEnded { value in
                                handleDragSelectionEnd(proxy: proxy, geometry: geometry)
                            }
                    )
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                handleZoom(magnification: value.magnification)
                            }
                    )
                    .onKeyPress("+") {
                        viewModel.zoomIn()
                        return .handled
                    }
                    .onKeyPress("-") {
                        viewModel.zoomOut()
                        return .handled
                    }
            }
        }
        .padding()
    }

    // MARK: - Gesture Handlers

    private func handleTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let frame = proxy.plotFrame else { return }
        let plotFrame = geometry[frame]
        let relativeX = location.x - plotFrame.origin.x
        guard relativeX >= 0, relativeX <= plotFrame.width else {
            viewModel.setCursor(at: nil)
            return
        }
        if let sweepValue: Double = proxy.value(atX: relativeX) {
            viewModel.setCursor(at: sweepValue)
        }
    }

    private func handleDragSelection(value: DragGesture.Value, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let frame = proxy.plotFrame else { return }
        let plotFrame = geometry[frame]

        // Set start on first change
        if dragSelectionStart == nil {
            let startX = value.startLocation.x - plotFrame.origin.x
            let clampedStartX = max(0, min(startX, plotFrame.width))
            if let startSweep: Double = proxy.value(atX: clampedStartX) {
                dragSelectionStart = startSweep
            }
        }

        // Update end
        let endX = value.location.x - plotFrame.origin.x
        let clampedEndX = max(0, min(endX, plotFrame.width))
        if let endSweep: Double = proxy.value(atX: clampedEndX) {
            dragSelectionEnd = endSweep
        }
    }

    private func handleDragSelectionEnd(proxy: ChartProxy, geometry: GeometryProxy) {
        defer {
            dragSelectionStart = nil
            dragSelectionEnd = nil
        }

        guard let start = dragSelectionStart, let end = dragSelectionEnd else { return }
        let lower = min(start, end)
        let upper = max(start, end)

        // Only zoom if selection has meaningful width
        guard upper > lower else { return }
        viewModel.setVisibleRange(lower...upper)
    }

    private func handleZoom(magnification: CGFloat) {
        guard let range = viewModel.document.visibleRange else { return }
        let span = range.upperBound - range.lowerBound
        let center = viewModel.document.cursorPosition ?? (range.lowerBound + span / 2)
        let factor = 1.0 / magnification
        let newSpan = span * factor
        let lower = center - newSpan / 2
        let upper = center + newSpan / 2
        viewModel.setVisibleRange(lower...upper)
    }

    // MARK: - Zoom Control Bar

    private var zoomControlBar: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.resetZoom()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderless)
            .help("Reset zoom to show all data")

            Button {
                viewModel.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Zoom out")

            Slider(
                value: Binding(
                    get: { viewModel.zoomLevel },
                    set: { viewModel.setZoomLevel($0) }
                ),
                in: 0...10,
                step: 0.1
            )
            .frame(minWidth: 80, maxWidth: 200)
            .help("Zoom level")

            Button {
                viewModel.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Zoom in")
        }
        .controlSize(.small)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    // MARK: - Operating Point Result Table

    private var operatingPointView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Label("Operating Point", systemImage: "function")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider()

                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.chartSeries) { series in
                        if let point = series.points.first {
                            HStack {
                                Circle()
                                    .fill(series.color)
                                    .frame(width: 8, height: 8)

                                Text(series.name)
                                    .font(.body.monospaced())

                                Spacer()

                                Text(formatValue(point.value))
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)

                            Divider()
                                .padding(.leading, 32)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Domain

    private var xDomain: ClosedRange<Double> {
        if let range = viewModel.document.visibleRange,
           range.lowerBound < range.upperBound {
            return range
        }
        guard let first = viewModel.chartSeries.first,
              let firstPt = first.points.first,
              let lastPt = first.points.last,
              firstPt.sweep < lastPt.sweep else {
            return 0...1
        }
        return firstPt.sweep...lastPt.sweep
    }

    // MARK: - X Axis Scaling

    /// Engineering prefix and divisor for the current visible X range.
    private var xAxisScale: (prefix: String, divisor: Double) {
        let domain = xDomain
        let maxAbs = max(abs(domain.lowerBound), abs(domain.upperBound))
        if maxAbs == 0 { return ("", 1) }
        if maxAbs >= 1e6 { return ("M", 1e6) }
        if maxAbs >= 1e3 { return ("k", 1e3) }
        if maxAbs >= 1 { return ("", 1) }
        if maxAbs >= 1e-3 { return ("m", 1e-3) }
        if maxAbs >= 1e-6 { return ("\u{00B5}", 1e-6) }
        if maxAbs >= 1e-9 { return ("n", 1e-9) }
        return ("p", 1e-12)
    }

    /// X axis label with engineering unit (e.g. "time (ns)", "frequency (MHz)").
    private var xAxisLabel: String {
        let scale = xAxisScale
        let unit = viewModel.isLogFrequency ? "Hz" : "s"
        if scale.prefix.isEmpty {
            return "\(viewModel.sweepLabel) (\(unit))"
        }
        return "\(viewModel.sweepLabel) (\(scale.prefix)\(unit))"
    }

    /// Format a raw sweep value for axis tick labels using the current scale.
    private func formatAxisValue(_ value: Double) -> String {
        let scaled = value / xAxisScale.divisor
        if scaled == 0 { return "0" }
        let absScaled = abs(scaled)
        if absScaled >= 100 { return String(format: "%.0f", scaled) }
        if absScaled >= 10 { return String(format: "%.1f", scaled) }
        if absScaled >= 1 { return String(format: "%.2f", scaled) }
        return String(format: "%.3f", scaled)
    }

    // MARK: - Formatting

    private func formatSweep(_ value: Double) -> String {
        formatEngineering(value)
    }

    private func formatValue(_ value: Double) -> String {
        formatEngineering(value)
    }

    private func formatEngineering(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue == 0 { return "0" }
        if absValue >= 1e6 { return String(format: "%.3gM", value / 1e6) }
        if absValue >= 1e3 { return String(format: "%.3gk", value / 1e3) }
        if absValue >= 1 { return String(format: "%.4g", value) }
        if absValue >= 1e-3 { return String(format: "%.3gm", value * 1e3) }
        if absValue >= 1e-6 { return String(format: "%.3g\u{00B5}", value * 1e6) }
        if absValue >= 1e-9 { return String(format: "%.3gn", value * 1e9) }
        return String(format: "%.3gp", value * 1e12)
    }
}

// MARK: - Scroll Pan (NSViewRepresentable)

/// Captures scroll wheel events and converts horizontal delta to pan callbacks.
private struct ScrollPanView: NSViewRepresentable {
    let onPan: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollCaptureNSView {
        ScrollCaptureNSView(onPan: onPan)
    }

    func updateNSView(_ nsView: ScrollCaptureNSView, context: Context) {
        nsView.onPan = onPan
    }
}

private final class ScrollCaptureNSView: NSView {
    var onPan: (CGFloat) -> Void

    init(onPan: @escaping (CGFloat) -> Void) {
        self.onPan = onPan
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaX
        guard abs(delta) > 0.1 else { return }
        DispatchQueue.main.async { [onPan] in
            onPan(delta)
        }
    }
}

#Preview("Tran — RC PULSE Step") {
    SimulationPreviewView(spiceSource: SPICENetlists.rcPulseTransient)
        .frame(width: 600, height: 350)
}

#Preview("AC — RC Lowpass") {
    SimulationPreviewView(spiceSource: SPICENetlists.rcLowpassAC)
        .frame(width: 600, height: 350)
}

#Preview("OP — Voltage Divider") {
    SimulationPreviewView(spiceSource: SPICENetlists.voltageDividerOP)
        .frame(width: 600, height: 350)
}

#Preview("Empty Chart") {
    WaveformChartView(viewModel: WaveformPreview.emptyViewModel())
        .frame(width: 600, height: 350)
}
