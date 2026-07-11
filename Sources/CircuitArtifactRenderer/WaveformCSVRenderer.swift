import ArtifactCore
import ArtifactRenderer
import SwiftUI

public struct WaveformCSVRenderer: ArtifactRenderable, Sendable {
    public static let artifactType = CircuitArtifactTypes.waveformCSV
    public static let fileInput: ArtifactFileInput = .localFileURL
    public static let preferredContentInsets: EdgeInsets? = EdgeInsets()

    private let loader: any WaveformArtifactLoading

    public init(loader: any WaveformArtifactLoading = WaveformArtifactLoader()) {
        self.loader = loader
    }

    public func body(artifact: AnyArtifact, payload: String) -> some View {
        WaveformArtifactView(
            payload: payload,
            format: .csv,
            loader: loader
        )
    }
}
