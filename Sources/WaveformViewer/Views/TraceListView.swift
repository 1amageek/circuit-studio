import SwiftUI

/// Sidebar list of waveform traces with toggle visibility.
public struct TraceListView: View {
    @Bindable var viewModel: WaveformViewModel

    public init(viewModel: WaveformViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        List {
            Section("Signals") {
                ForEach(viewModel.document.traces) { trace in
                    HStack {
                        Image(systemName: trace.isVisible ? "eye" : "eye.slash")
                            .foregroundStyle(trace.isVisible ? trace.color : .secondary)
                            .frame(width: 20)

                        Text(trace.displayName)
                            .foregroundStyle(trace.isVisible ? .primary : .secondary)

                        Spacer()

                        if let value = viewModel.cursorValue(for: trace) {
                            Text(formatValue(value))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.toggleTrace(trace.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func formatValue(_ value: Double) -> String {
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

#Preview("Trace List") {
    SimulationPreviewView(spiceSource: SPICENetlists.rcPulseTransient)
        .frame(width: 250, height: 300)
}

#Preview("Empty Traces") {
    TraceListView(viewModel: WaveformPreview.emptyViewModel())
        .frame(width: 250, height: 300)
}
