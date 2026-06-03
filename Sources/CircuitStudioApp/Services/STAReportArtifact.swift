import Foundation

public struct STAReportArtifact: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1
    private static let expectedKind = "sta-report"

    public let schemaVersion: Int
    public let kind: String
    public let runID: String?
    public let createdAt: Date
    public let designName: String
    public let timingLibraryArtifactID: String
    public let report: TimingReport
    public let status: TimingRunStatus

    public init(
        runID: String? = nil,
        createdAt: Date = Date(),
        designName: String,
        timingLibraryArtifactID: String,
        report: TimingReport,
        status: TimingRunStatus
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.kind = Self.expectedKind
        self.runID = runID
        self.createdAt = createdAt
        self.designName = designName
        self.timingLibraryArtifactID = timingLibraryArtifactID
        self.report = report
        self.status = status
    }
}

extension STAReportArtifact {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case kind
        case runID
        case createdAt
        case designName
        case timingLibraryArtifactID
        case report
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard decodedSchemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported STA report artifact schema version \(decodedSchemaVersion)."
            )
        }
        let decodedKind = try container.decode(String.self, forKey: .kind)
        guard decodedKind == Self.expectedKind else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unsupported STA report artifact kind \(decodedKind)."
            )
        }
        schemaVersion = decodedSchemaVersion
        kind = decodedKind
        runID = try container.decodeIfPresent(String.self, forKey: .runID)
        createdAt = try TimingArtifactDateCoding.decode(from: container, forKey: .createdAt)
        designName = try container.decode(String.self, forKey: .designName)
        timingLibraryArtifactID = try container.decode(String.self, forKey: .timingLibraryArtifactID)
        report = try container.decode(TimingReport.self, forKey: .report)
        status = try container.decode(TimingRunStatus.self, forKey: .status)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(runID, forKey: .runID)
        try TimingArtifactDateCoding.encode(createdAt, to: &container, forKey: .createdAt)
        try container.encode(designName, forKey: .designName)
        try container.encode(timingLibraryArtifactID, forKey: .timingLibraryArtifactID)
        try container.encode(report, forKey: .report)
        try container.encode(status, forKey: .status)
    }
}
