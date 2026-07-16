import DesignFlowKernel
import SwiftUI

struct RunReviewSignoffArtifactRows: View {
    let artifacts: [FlowRunReviewArtifact]
    let runID: String
    let artifactPreviews: [String: RunReviewArtifactPreview]
    let artifactPreviewErrors: [String: String]
    @Binding var waveformSignalSelections: [String: Set<String>]
    let loadArtifactPreview: (FlowRunReviewArtifact) -> Void

    var body: some View {
        ForEach(artifacts, id: \.self) { artifact in
            let key = RunReviewArtifactPreviewKey.make(runID: runID, artifact: artifact)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: artifact.integrity?.status == .verified ? "checkmark.seal.fill" : "doc.text")
                    .foregroundStyle(integrityColor(artifact.integrity?.status))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(artifact.purpose.rawValue)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Text(artifact.reference.id.rawValue)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(artifact.reference.locator.format.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(artifact.reference.locator.location.value)
                        .font(.caption2.monospaced())
                        .foregroundStyle(integrityColor(artifact.integrity?.status))
                        .lineLimit(2)
                    if let preview = artifactPreviews[key] {
                        artifactPreview(preview, key: key)
                    } else if let error = artifactPreviewErrors[key] {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                }
                Button {
                    loadArtifactPreview(artifact)
                } label: {
                    Label("Preview", systemImage: "doc.text.magnifyingglass")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func artifactPreview(
        _ preview: RunReviewArtifactPreview,
        key: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let structuredPreview = preview.structuredPreview {
                    Text(structuredPreview)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(preview.previewByteCount) byte(s)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if preview.truncated {
                    Text("truncated")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            if let parseIssue = preview.parseIssue {
                Text(parseIssue)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            if let waveformPreview = preview.waveformPreview {
                waveformPreviewPane(waveformPreview, previewKey: key)
            }
            if preview.isText {
                Text(preview.text)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            } else {
                Text("Binary preview is not rendered as text.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func waveformPreviewPane(
        _ waveform: RunReviewWaveformPreview,
        previewKey: String
    ) -> some View {
        let signalNames = waveform.signals.map(\.name)
        let selectedNames = waveformSignalSelections[previewKey] ?? Set(signalNames)
        let selectedSignals = waveform.signals.filter { selectedNames.contains($0.name) }
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.secondary)
                Text(
                    "\(waveform.sweepColumn) \(RunReviewWaveformPresentation.value(waveform.sweepStart))..."
                        + "\(RunReviewWaveformPresentation.value(waveform.sweepEnd))"
                )
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                Text("\(waveform.sampleCount) sample(s)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 88), spacing: 6)],
                alignment: .leading,
                spacing: 3
            ) {
                ForEach(waveform.signals, id: \.name) { signal in
                    Toggle(isOn: waveformSignalBinding(
                        previewKey: previewKey,
                        signalName: signal.name,
                        allSignalNames: signalNames
                    )) {
                        Text(signal.name)
                            .font(.caption2.monospaced())
                            .lineLimit(1)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            if selectedSignals.isEmpty {
                Text("No selected traces")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                RunReviewWaveformOverlayChart(signals: selectedSignals)
                ForEach(selectedSignals.prefix(4), id: \.name) { signal in
                    HStack(spacing: 6) {
                        Text(signal.name)
                            .font(.caption2.monospaced())
                            .lineLimit(1)
                        Text(
                            "first \(RunReviewWaveformPresentation.value(signal.firstValue)) "
                                + "last \(RunReviewWaveformPresentation.value(signal.lastValue))"
                        )
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
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
    }

    private func waveformSignalBinding(
        previewKey: String,
        signalName: String,
        allSignalNames: [String]
    ) -> Binding<Bool> {
        Binding(
            get: {
                let selectedSignals = waveformSignalSelections[previewKey] ?? Set(allSignalNames)
                return selectedSignals.contains(signalName)
            },
            set: { isSelected in
                var selectedSignals = waveformSignalSelections[previewKey] ?? Set(allSignalNames)
                if isSelected {
                    selectedSignals.insert(signalName)
                } else {
                    selectedSignals.remove(signalName)
                }
                waveformSignalSelections[previewKey] = selectedSignals
            }
        )
    }

    private func integrityColor(_ status: FlowRunReviewArtifactIntegrityStatus?) -> Color {
        switch status {
        case .verified:
            return .green
        case .missingDigest, .missingByteCount:
            return .orange
        case .missingArtifact, .invalidDigest, .invalidByteCount, .byteCountMismatch, .sha256Mismatch,
             .invalidIdentifier, .noRecordedReference, .invalidPath, .unreadableArtifact:
            return .red
        case nil:
            return .secondary
        }
    }
}
