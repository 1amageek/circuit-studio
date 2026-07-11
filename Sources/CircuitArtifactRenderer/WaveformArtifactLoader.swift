import CircuitStudioCore
import CoreSpiceIO
import Foundation

public actor WaveformArtifactLoader: WaveformArtifactLoading {
    public init() {}

    public func load(
        payload: String,
        format: WaveformArtifactFormat
    ) async throws -> WaveformData {
        try Task.checkCancellation()

        let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedPayload) else {
            throw WaveformArtifactError.invalidPayload(trimmedPayload)
        }
        guard url.isFileURL else {
            throw WaveformArtifactError.requiresLocalFileURL(trimmedPayload)
        }

        let path = url.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw WaveformArtifactError.inputMissing(path: path)
        }
        guard !isDirectory.boolValue else {
            throw WaveformArtifactError.inputIsDirectory(path: path)
        }

        do {
            switch format {
            case .csv:
                return try CSVWaveformReader().read(contentsOfFile: path)
            case .ngspiceRAW:
                return try NgspiceRawParser().parse(rawURL: url, fallbackAnalysis: nil)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WaveformArtifactError.decodeFailed(
                format: format,
                path: path,
                reason: error.localizedDescription
            )
        }
    }
}
