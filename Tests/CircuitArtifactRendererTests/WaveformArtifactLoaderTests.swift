import CircuitArtifactRenderer
import Foundation
import Testing

@Suite("Waveform artifact loader")
struct WaveformArtifactLoaderTests {
    @Test func loadsCoreSpiceCSVIntoCanonicalWaveformData() async throws {
        let fixture = try TemporaryArtifactFile(
            extension: "csv",
            contents: """
            time [s],v(in) [V],v(out) [V]
            0,0,0
            1e-6,1,0.5
            """
        )
        defer { fixture.remove() }

        let waveform = try await WaveformArtifactLoader().load(
            payload: fixture.url.absoluteString,
            format: .csv
        )

        #expect(waveform.pointCount == 2)
        #expect(waveform.sweepVariable.name == "time")
        #expect(waveform.variables.map(\.name) == ["v(in)", "v(out)"])
        #expect(waveform.realValue(variable: 1, point: 1) == 0.5)
    }

    @Test func loadsNgspiceRAWIntoCanonicalWaveformData() async throws {
        let fixture = try TemporaryArtifactFile(
            extension: "raw",
            contents: """
            Title: transient fixture
            Plotname: Transient Analysis
            Flags: real
            No. Variables: 3
            No. Points: 2
            Variables:
                0 time time
                1 v(in) voltage
                2 v(out) voltage
            Values:
                0 0 0 0
                1 1e-6 1 0.5
            """
        )
        defer { fixture.remove() }

        let waveform = try await WaveformArtifactLoader().load(
            payload: fixture.url.absoluteString,
            format: .ngspiceRAW
        )

        #expect(waveform.pointCount == 2)
        #expect(waveform.sweepVariable.name == "time")
        #expect(waveform.variables.map(\.name) == ["v(in)", "v(out)"])
        #expect(waveform.realValue(variable: 1, point: 1) == 0.5)
    }

    @Test func rejectsRemoteURLsBeforeParsing() async {
        await #expect(throws: WaveformArtifactError.requiresLocalFileURL("https://example.com/a.csv")) {
            _ = try await WaveformArtifactLoader().load(
                payload: "https://example.com/a.csv",
                format: .csv
            )
        }
    }

    @Test func reportsParserFailuresWithFormatAndPath() async throws {
        let fixture = try TemporaryArtifactFile(extension: "csv", contents: "not,a,waveform")
        defer { fixture.remove() }

        do {
            _ = try await WaveformArtifactLoader().load(
                payload: fixture.url.absoluteString,
                format: .csv
            )
            Issue.record("Malformed waveform CSV was accepted.")
        } catch let error as WaveformArtifactError {
            guard case .decodeFailed(let format, let path, _) = error else {
                Issue.record("Unexpected waveform error: \(error)")
                return
            }
            #expect(format == .csv)
            #expect(path == fixture.url.path(percentEncoded: false))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

private struct TemporaryArtifactFile {
    let directory: URL
    let url: URL

    init(extension pathExtension: String, contents: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CircuitArtifactRendererTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "fixture.\(pathExtension)", directoryHint: .notDirectory)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        self.directory = directory
        self.url = url
    }

    func remove() {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record("Failed to remove waveform fixture: \(error)")
        }
    }
}
