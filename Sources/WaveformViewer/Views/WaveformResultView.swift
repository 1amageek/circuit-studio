import SwiftUI

/// Composite view showing the full waveform result: chart area + trace list sidebar.
public struct WaveformResultView: View {
    @Bindable var viewModel: WaveformViewModel

    public init(viewModel: WaveformViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if viewModel.waveformData != nil {
            HSplitView {
                WaveformChartView(viewModel: viewModel)
                    .frame(minWidth: 400)
                TraceListView(viewModel: viewModel)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
            }
        } else {
            WaveformChartView(viewModel: viewModel)
        }
    }
}

// MARK: - Previews

#Preview("Transient") {
    WaveformResultView(viewModel: WaveformPreview.transientViewModel())
        .frame(width: 900, height: 500)
}

#Preview("AC") {
    WaveformResultView(viewModel: WaveformPreview.acViewModel())
        .frame(width: 900, height: 500)
}

#Preview("Operating Point") {
    WaveformResultView(viewModel: WaveformPreview.opViewModel())
        .frame(width: 900, height: 500)
}
