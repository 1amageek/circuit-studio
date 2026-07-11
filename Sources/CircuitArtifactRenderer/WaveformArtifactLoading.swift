import CoreSpiceIO

public protocol WaveformArtifactLoading: Sendable {
    func load(
        payload: String,
        format: WaveformArtifactFormat
    ) async throws -> WaveformData
}
