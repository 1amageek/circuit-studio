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

#Preview("OP — Voltage Divider") {
    SimulationPreviewView(spiceSource: SPICENetlists.voltageDividerOP)
        .frame(width: 900, height: 500)
}

#Preview("Tran — RC PULSE Step") {
    SimulationPreviewView(spiceSource: SPICENetlists.rcPulseTransient)
        .frame(width: 900, height: 500)
}

#Preview("AC — RC Lowpass") {
    SimulationPreviewView(spiceSource: SPICENetlists.rcLowpassAC)
        .frame(width: 900, height: 500)
}

#Preview("OP — Diode Bias") {
    SimulationPreviewView(spiceSource: SPICENetlists.diodeOP)
        .frame(width: 900, height: 500)
}

#Preview("OP — VCVS Gain") {
    SimulationPreviewView(spiceSource: SPICENetlists.vcvsOP)
        .frame(width: 900, height: 500)
}
