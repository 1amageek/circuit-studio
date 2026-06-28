import SwiftUI

struct RunReviewWaveformOverlayChart: View {
    let signals: [RunReviewWaveformSignalPreview]

    var body: some View {
        let plottedSignals = signals.filter { !$0.samples.isEmpty }
        if !plottedSignals.isEmpty {
            Canvas { context, size in
                let allSamples = plottedSignals.flatMap(\.samples)
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

                for (index, signal) in plottedSignals.prefix(6).enumerated() {
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
                        lineWidth: 1.5
                    )
                }
            }
            .frame(height: 72)
        }
    }
}
