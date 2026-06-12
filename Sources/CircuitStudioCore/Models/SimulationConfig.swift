import Foundation

/// Persisted simulation configuration stored in `.xcircuite/simulation.json`.
public struct SimulationConfig: Sendable, Codable {
    public var version: Int
    public var selectedAnalysis: AnalysisCommand
    public var processConfiguration: ProcessConfiguration
    /// Names of corners selected for matrix runs. Stored by name because
    /// generic corner sets mint fresh UUIDs per session.
    public var matrixCornerNames: [String]

    public init(
        version: Int = 1,
        selectedAnalysis: AnalysisCommand = .op,
        processConfiguration: ProcessConfiguration = ProcessConfiguration(),
        matrixCornerNames: [String] = []
    ) {
        self.version = version
        self.selectedAnalysis = selectedAnalysis
        self.processConfiguration = processConfiguration
        self.matrixCornerNames = matrixCornerNames
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case selectedAnalysis
        case processConfiguration
        case matrixCornerNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.selectedAnalysis = try container.decode(AnalysisCommand.self, forKey: .selectedAnalysis)
        self.processConfiguration = try container.decode(ProcessConfiguration.self, forKey: .processConfiguration)
        self.matrixCornerNames = try container.decodeIfPresent([String].self, forKey: .matrixCornerNames) ?? []
    }
}
