import Foundation

/// Persisted simulation configuration stored in `.xcircuite/simulation.json`.
public struct SimulationConfig: Sendable, Codable {
    public var version: Int
    public var selectedAnalysis: AnalysisCommand
    public var processConfiguration: ProcessConfiguration

    public init(
        version: Int = 1,
        selectedAnalysis: AnalysisCommand = .op,
        processConfiguration: ProcessConfiguration = ProcessConfiguration()
    ) {
        self.version = version
        self.selectedAnalysis = selectedAnalysis
        self.processConfiguration = processConfiguration
    }
}
