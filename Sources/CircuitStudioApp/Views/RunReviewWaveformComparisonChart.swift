import SwiftUI

struct RunReviewWaveformComparisonChart: View {
    let sources: [RunReviewWaveformComparisonSource]
    let signalName: String

    var body: some View {
        let plottedSources = sources.compactMap { source -> RunReviewWaveformComparisonSource? in
            guard source.preview.signals.contains(where: { $0.name == signalName && !$0.samples.isEmpty }) else {
                return nil
            }
            return source
        }
        if plottedSources.count >= 2 {
            Canvas { context, size in
                let signals = plottedSources.compactMap { source in
                    source.preview.signals.first { $0.name == signalName }
                }
                let allSamples = signals.flatMap(\.samples)
                guard let minX = allSamples.map(\.sweepValue).min(),
                      let maxX = allSamples.map(\.sweepValue).max(),
                      let minY = allSamples.map(\.signalValue).min(),
                      let maxY = allSamples.map(\.signalValue).max()
                else {
                    return
                }
                let xRange = max(maxX - minX, .leastNonzeroMagnitude)
                let yRange = max(maxY - minY, .leastNonzeroMagnitude)
                var frame = Path()
                frame.addRect(CGRect(origin: .zero, size: size))
                context.stroke(frame, with: .color(.secondary.opacity(0.25)), lineWidth: 1)

                for (index, signal) in signals.enumerated() {
                    var path = Path()
                    for (sampleIndex, sample) in signal.samples.enumerated() {
                        let x = (sample.sweepValue - minX) / xRange
                        let y = (sample.signalValue - minY) / yRange
                        let point = CGPoint(
                            x: CGFloat(x) * size.width,
                            y: size.height - CGFloat(y) * size.height
                        )
                        if sampleIndex == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                    context.stroke(
                        path,
                        with: .color(RunReviewWaveformPresentation.chartColor(index)),
                        lineWidth: 1.7
                    )
                }
            }
            .frame(height: 88)
            HStack(spacing: 8) {
                ForEach(Array(plottedSources.enumerated()), id: \.element.artifact.path) { index, source in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(RunReviewWaveformPresentation.chartColor(index))
                            .frame(width: 6, height: 6)
                        Text(source.label)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
