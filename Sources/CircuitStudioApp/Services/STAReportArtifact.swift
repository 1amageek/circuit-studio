import Foundation

public struct STAReportArtifact: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let kind: String
    public let runID: String?
    public let createdAt: Date
    public let designName: String
    public let timingLibraryArtifactID: String
    public let report: TimingReport
    public let status: TimingRunStatus

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        kind: String = "sta-report",
        runID: String? = nil,
        createdAt: Date = Date(),
        designName: String,
        timingLibraryArtifactID: String,
        report: TimingReport,
        status: TimingRunStatus
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.runID = runID
        self.createdAt = createdAt
        self.designName = designName
        self.timingLibraryArtifactID = timingLibraryArtifactID
        self.report = report
        self.status = status
    }
}
