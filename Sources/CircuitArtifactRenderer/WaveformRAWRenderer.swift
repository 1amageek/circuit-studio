import ArtifactCore
import ArtifactRenderer
import SwiftUI

public struct WaveformRAWRenderer: ArtifactRenderable, Sendable {
    public static let artifactType = CircuitArtifactTypes.waveformRAW
    public static let fileInput: ArtifactFileInput = .localFileURL
    public static let preferredContentInsets: EdgeInsets? = EdgeInsets()

    private let loader: any WaveformArtifactLoading

    public init(loader: any WaveformArtifactLoading = WaveformArtifactLoader()) {
        self.loader = loader
    }

    public func body(artifact: AnyArtifact, payload: String) -> some View {
        WaveformArtifactView(
            payload: payload,
            format: .ngspiceRAW,
            loader: loader
        )
    }
}
