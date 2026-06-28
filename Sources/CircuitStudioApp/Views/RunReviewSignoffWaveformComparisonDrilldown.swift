import DesignFlowKernel
import SwiftUI

struct RunReviewSignoffWaveformComparisonDrilldown: View {
    let card: RunReviewSignoffCard
    let runID: String
    let artifactPreviews: [String: RunReviewArtifactPreview]
    @Binding var waveformComparisonSelections: [String: String]
    let loadArtifactPreviews: ([FlowRunReviewArtifact]) -> Void

    private var waveformArtifacts: [FlowRunReviewArtifact] {
        card.relatedArtifacts.filter { $0.kind == .waveform }
    }

    var body: some View {
        if waveformArtifacts.count >= 2 {
            let comparisonKey = RunReviewArtifactPreviewKey.make(runID: runID, artifactPath: card.artifact.path)
            let sources = waveformComparisonSources(artifacts: waveformArtifacts)
            let commonSignals = commonWaveformSignalNames(sources)
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Button {
                            loadArtifactPreviews(waveformArtifacts)
                        } label: {
                            Label("Load waveforms", systemImage: "waveform.path.badge.plus")
                        }
                        .font(.caption)
                        if !sources.isEmpty {
                            Picker(
                                "Signal",
                                selection: waveformComparisonBinding(
                                    comparisonKey: comparisonKey,
                                    signalNames: commonSignals
                                )
                            ) {
                                ForEach(commonSignals, id: \.self) { signalName in
                                    Text(signalName).tag(signalName)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                    if sources.count >= 2,
                       let signalName = selectedWaveformComparisonSignal(
                        comparisonKey: comparisonKey,
                        sources: sources
                       ) {
                        RunReviewWaveformComparisonChart(
                            sources: sources,
                            signalName: signalName
                        )
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 112), spacing: 6)],
                            alignment: .leading,
                            spacing: 3
                        ) {
                            ForEach(sources, id: \.artifact.path) { source in
                                if let signal = source.preview.signals.first(where: { $0.name == signalName }) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(source.label)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                        Text("last \(RunReviewWaveformPresentation.value(signal.lastValue))")
                                            .font(.caption2.monospaced())
                                        Text(
                                            "min \(RunReviewWaveformPresentation.value(signal.minValue)) "
                                                + "max \(RunReviewWaveformPresentation.value(signal.maxValue))"
                                        )
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("Load at least two waveform previews to compare traces.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 3)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path")
                        .foregroundStyle(.secondary)
                    Text("Waveform Comparison")
                        .font(.caption.weight(.semibold))
                    Text("\(waveformArtifacts.count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func waveformComparisonSources(
        artifacts: [FlowRunReviewArtifact]
    ) -> [RunReviewWaveformComparisonSource] {
        artifacts.compactMap { artifact in
            let key = RunReviewArtifactPreviewKey.make(runID: runID, artifactPath: artifact.path)
            guard let preview = artifactPreviews[key]?.waveformPreview else {
                return nil
            }
            return RunReviewWaveformComparisonSource(
                artifact: artifact,
                label: waveformSourceLabel(artifact),
                preview: preview
            )
        }
    }

    private func commonWaveformSignalNames(
        _ sources: [RunReviewWaveformComparisonSource]
    ) -> [String] {
        guard let first = sources.first else {
            return []
        }
        return first.preview.signals.map(\.name).filter { signalName in
            sources.allSatisfy { source in
                source.preview.signals.contains { $0.name == signalName }
            }
        }
    }

    private func selectedWaveformComparisonSignal(
        comparisonKey: String,
        sources: [RunReviewWaveformComparisonSource]
    ) -> String? {
        let signals = commonWaveformSignalNames(sources)
        guard !signals.isEmpty else {
            return nil
        }
        if let selected = waveformComparisonSelections[comparisonKey],
           signals.contains(selected) {
            return selected
        }
        return signals.first
    }

    private func waveformComparisonBinding(
        comparisonKey: String,
        signalNames: [String]
    ) -> Binding<String> {
        Binding(
            get: {
                if let selected = waveformComparisonSelections[comparisonKey],
                   signalNames.contains(selected) {
                    return selected
                }
                return signalNames.first ?? ""
            },
            set: { selection in
                waveformComparisonSelections[comparisonKey] = selection
            }
        )
    }

    private func waveformSourceLabel(_ artifact: FlowRunReviewArtifact) -> String {
        let searchable = [
            artifact.artifactID,
            artifact.role,
            artifact.path,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        if searchable.contains("pre-layout") {
            return "pre"
        }
        if searchable.contains("post-layout") {
            return "post"
        }
        return artifact.artifactID ?? artifact.role
    }
}
