import SwiftUI
import Charts

/// Main waveform chart view using Swift Charts with cursor, zoom, and pan support.
public struct WaveformChartView: View {
    @Bindable var viewModel: WaveformViewModel
    @State private var chartProxy: ChartProxy?

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
        }
        .chartXAxisLabel(viewModel.sweepLabel)
        .chartYAxisLabel(viewModel.isComplex ? "Magnitude (dB)" : "Value")
        .chartXScale(domain: xDomain, type: viewModel.isLogFrequency ? .log : .linear)
        .chartLegend(position: .top)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        handleTap(at: location, proxy: proxy, geometry: geometry)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                handleDrag(value: value, proxy: proxy, geometry: geometry)
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

    private func handleDrag(value: DragGesture.Value, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let frame = proxy.plotFrame else { return }
        let plotFrame = geometry[frame]
        let relativeX = value.location.x - plotFrame.origin.x
        guard relativeX >= 0, relativeX <= plotFrame.width else { return }
        if let sweepValue: Double = proxy.value(atX: relativeX) {
            viewModel.setCursor(at: sweepValue)
        }
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
        if absValue >= 1e-6 { return String(format: "%.3gu", value * 1e6) }
        if absValue >= 1e-9 { return String(format: "%.3gn", value * 1e9) }
        return String(format: "%.3gp", value * 1e12)
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
