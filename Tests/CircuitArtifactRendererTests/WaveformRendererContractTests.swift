import ArtifactRenderer
import CircuitArtifactRenderer
import Testing

@Suite("Waveform renderer contract")
struct WaveformRendererContractTests {
    @Test func csvRendererRequestsVerifiedLocalFileURLPayloads() {
        #expect(WaveformCSVRenderer.artifactType == CircuitArtifactTypes.waveformCSV)
        #expect(WaveformCSVRenderer.fileInput == .localFileURL)
    }

    @Test func rawRendererRequestsVerifiedLocalFileURLPayloads() {
        #expect(WaveformRAWRenderer.artifactType == CircuitArtifactTypes.waveformRAW)
        #expect(WaveformRAWRenderer.fileInput == .localFileURL)
    }
}
