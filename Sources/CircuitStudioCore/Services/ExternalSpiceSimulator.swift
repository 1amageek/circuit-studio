import Foundation
import CoreSpiceEvent
import CoreSpiceWaveform

/// Orchestrates external simulation for netlists requiring advanced models.
public struct ExternalSpiceSimulator: Sendable {
    private let detector = ExternalModelDetector()
    private let preprocessor = ExternalSpicePreprocessor()
    private let runner = NgspiceRunner()
    private let parser = NgspiceRawParser()

    public init() {}

    public func requiresExternalSimulation(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration?
    ) -> Bool {
        detector.requiresExternalSimulation(
            source: source,
            fileName: fileName,
            processConfiguration: processConfiguration
        )
    }

    public func run(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration?,
        command: AnalysisCommand?,
        cancellation: CancellationToken
    ) async throws -> WaveformData {
        let prepared = try preprocessor.prepare(
            source: source,
            fileName: fileName,
            processConfiguration: processConfiguration,
            command: command
        )

        let rawURL = try await runner.run(
            netlistURL: prepared.netlistURL,
            rawURL: prepared.rawURL,
            workingDirectory: prepared.workingDirectory,
            cancellation: cancellation
        )

        return try parser.parse(rawURL: rawURL, fallbackAnalysis: prepared.analysis ?? command)
    }
}
