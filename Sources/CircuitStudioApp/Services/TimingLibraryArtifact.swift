import Foundation

public struct TimingLibraryArtifact: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let kind: String
    public let runID: String?
    public let createdAt: Date
    public let technology: TimingTechnologyContext
    public let library: TimingLibrary
    public let modelSources: [TimingModelSource]
    public let warnings: [String]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        kind: String = "timing-library",
        runID: String? = nil,
        createdAt: Date = Date(),
        technology: TimingTechnologyContext,
        library: TimingLibrary,
        modelSources: [TimingModelSource],
        warnings: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.runID = runID
        self.createdAt = createdAt
        self.technology = technology
        self.library = library
        self.modelSources = modelSources
        self.warnings = warnings
    }
}
