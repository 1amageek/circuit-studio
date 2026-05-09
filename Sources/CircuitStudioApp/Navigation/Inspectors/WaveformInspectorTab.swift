import SwiftUI
import WaveformViewer

/// Inspector tab summarising the active waveform: sweep range, point count, signal counts.
struct WaveformInspectorTab: View {
    @Bindable var viewModel: WaveformViewModel

    var body: some View {
        Form {
            if viewModel.waveformData == nil {
                Section("Waveform") {
                    Text("Run a simulation to see waveform metadata.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } else {
                dataSection
                if viewModel.isComplex {
                    modeSection
                }
                if let error = viewModel.exportError {
                    errorSection(error)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var dataSection: some View {
        Section("Data") {
            LabeledContent("Sweep", value: viewModel.sweepLabel)
            LabeledContent("Points", value: "\(viewModel.waveformData?.pointCount ?? 0)")
            LabeledContent("Signals", value: "\(viewModel.document.traces.count)")
            LabeledContent("Visible", value: "\(viewModel.document.traces.filter(\.isVisible).count)")
        }
    }

    private var modeSection: some View {
        Section("Mode") {
            LabeledContent("Type", value: "Complex (AC)")
        }
    }

    private func errorSection(_ message: String) -> some View {
        Section("Export Error") {
            Text(message)
                .foregroundStyle(.red)
                .font(.caption)
        }
    }
}
