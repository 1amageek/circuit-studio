import SwiftUI

struct RunReviewWaveformEvidenceView: View {
    let waveforms: [RunReviewDesignEvidence.WaveformEvidence]

    @State private var selectedPath: String
    @State private var signalSelections: [String: Set<String>]

    init(waveforms: [RunReviewDesignEvidence.WaveformEvidence]) {
        self.waveforms = waveforms
        let selectedPath = waveforms.first?.artifact.path ?? ""
        _selectedPath = State(initialValue: selectedPath)
        _signalSelections = State(initialValue: Dictionary(
            uniqueKeysWithValues: waveforms.map { waveform in
                (waveform.artifact.path, Self.defaultSignals(for: waveform.preview))
            }
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if waveforms.count > 1 {
                Picker("Waveform source", selection: $selectedPath) {
                    ForEach(waveforms, id: \.artifact.path) { waveform in
                        Text(waveform.phase.rawValue)
                            .tag(waveform.artifact.path)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if let selectedWaveform {
                HStack(spacing: 12) {
                    Text("\(selectedWaveform.preview.sampleCount) samples")
                    Text("\(selectedWaveform.preview.signalCount) signals")
                    if let start = selectedWaveform.preview.sweepStart,
                       let end = selectedWaveform.preview.sweepEnd {
                        Text("\(formatted(start)) – \(formatted(end))")
                    }
                    Spacer()
                }
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)

                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(selectedWaveform.preview.signals, id: \.name) { signal in
                            Toggle(
                                signal.name,
                                isOn: signalBinding(
                                    signal.name,
                                    artifactPath: selectedWaveform.artifact.path
                                )
                            )
                            .toggleStyle(.checkbox)
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)

                RunReviewWaveformEvidenceChart(
                    preview: selectedWaveform.preview,
                    selectedSignalNames: signalSelections[selectedWaveform.artifact.path] ?? []
                )

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text(selectedWaveform.artifact.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .onChange(of: waveforms.map(\.artifact.path)) { _, paths in
            if !paths.contains(selectedPath) {
                selectedPath = paths.first ?? ""
            }
        }
    }

    private var selectedWaveform: RunReviewDesignEvidence.WaveformEvidence? {
        waveforms.first { $0.artifact.path == selectedPath } ?? waveforms.first
    }

    private func signalBinding(_ name: String, artifactPath: String) -> Binding<Bool> {
        Binding(
            get: { signalSelections[artifactPath, default: []].contains(name) },
            set: { selected in
                if selected {
                    signalSelections[artifactPath, default: []].insert(name)
                } else {
                    signalSelections[artifactPath, default: []].remove(name)
                }
            }
        )
    }

    private static func defaultSignals(for preview: RunReviewWaveformPreview) -> Set<String> {
        let voltageSignals = preview.signals.filter { signal in
            let lowercased = signal.name.lowercased()
            return lowercased.hasPrefix("v(") || lowercased.contains("[v]")
        }
        return Set((voltageSignals.isEmpty ? preview.signals : voltageSignals).prefix(4).map(\.name))
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.4g", value)
    }
}
