import Charts
import SwiftUI

struct RunReviewWaveformEvidenceChart: View {
    let preview: RunReviewWaveformPreview
    let selectedSignalNames: Set<String>

    private var signals: [RunReviewWaveformSignalPreview] {
        preview.signals.filter { selectedSignalNames.contains($0.name) && !$0.samples.isEmpty }
    }

    var body: some View {
        if signals.isEmpty {
            ContentUnavailableView(
                "No signals selected",
                systemImage: "waveform.path"
            )
        } else {
            Chart {
                ForEach(signals, id: \.name) { signal in
                    ForEach(Array(signal.samples.enumerated()), id: \.offset) { _, sample in
                        LineMark(
                            x: .value(preview.sweepColumn, sample.sweepValue),
                            y: .value("Value", sample.signalValue),
                            series: .value("Signal", signal.name)
                        )
                        .foregroundStyle(by: .value("Signal", signal.name))
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                        .interpolationMethod(.linear)
                    }
                }
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
            .chartXAxisLabel(preview.sweepColumn)
            .chartYAxisLabel("Value")
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color(nsColor: .controlBackgroundColor))
                    .border(.secondary.opacity(0.2), width: 1)
            }
            .padding(.horizontal, 4)
        }
    }
}
