import ArtifactView
import SwiftUI
import WaveformViewer

@MainActor
struct WaveformArtifactView: View {
    let payload: String
    let format: WaveformArtifactFormat
    let loader: any WaveformArtifactLoading

    @State private var viewModel = WaveformViewModel()
    @State private var phase: LoadingPhase = .loading
    @State private var retryAttempt = 0

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView("Loading waveform")
            case .loaded:
                WaveformResultView(viewModel: viewModel)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Unable to render waveform", systemImage: "waveform.badge.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry", systemImage: "arrow.clockwise") {
                        retryAttempt += 1
                    }
                }
            }
        }
        .artifactViewport(minHeight: 420)
        .task(id: LoadID(payload: payload, format: format, attempt: retryAttempt)) {
            await loadWaveform()
        }
    }

    private func loadWaveform() async {
        phase = .loading
        do {
            let waveform = try await loader.load(payload: payload, format: format)
            guard !Task.isCancelled else { return }
            viewModel.load(waveform: waveform)
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private enum LoadingPhase {
        case loading
        case loaded
        case failed(String)
    }

    private struct LoadID: Hashable {
        let payload: String
        let format: WaveformArtifactFormat
        let attempt: Int
    }
}
