import Foundation

public enum TimingArtifactStatus: String, Sendable, Hashable, Codable {
    case available
    case omitted
    case missing
}

public enum TimingRunStatus: String, Sendable, Hashable, Codable {
    case passed
    case failed
}

public enum TimingModelKind: String, Sendable, Hashable, Codable {
    case combinationalCell = "combinational-cell"
    case sequentialCell = "sequential-cell"
}

public enum TimingModelSourceType: String, Sendable, Hashable, Codable {
    case characterized
    case imported
    case constantFixture = "constant-fixture"
}

public enum TimingArtifactKind: String, Sendable, Hashable, Codable {
    case timingManifest = "timing-manifest"
    case timingLibrary = "timing-library"
    case staReport = "sta-report"
    case characterizationReport = "characterization-report"
    case measurementLog = "measurement-log"
    case spiceDeck = "spice-deck"
    case waveformCSV = "waveform-csv"
    case validationReport = "validation-report"
}

public struct TimingTechnologyContext: Sendable, Hashable, Codable {
    public let processName: String
    public let cornerID: String
    public let supplyVoltage: Double
    public let temperatureC: Double?
    public let deviceModelID: String
    public let deviceModelHash: String?

    public init(
        processName: String,
        cornerID: String,
        supplyVoltage: Double,
        temperatureC: Double? = nil,
        deviceModelID: String,
        deviceModelHash: String? = nil
    ) {
        self.processName = processName
        self.cornerID = cornerID
        self.supplyVoltage = supplyVoltage
        self.temperatureC = temperatureC
        self.deviceModelID = deviceModelID
        self.deviceModelHash = deviceModelHash
    }
}

public struct TimingArtifactProvenance: Sendable, Hashable, Codable {
    public let sourcePath: String?
    public let generator: String?
    public let note: String?

    public init(sourcePath: String? = nil, generator: String? = nil, note: String? = nil) {
        self.sourcePath = sourcePath
        self.generator = generator
        self.note = note
    }
}

public struct TimingArtifactRecord: Sendable, Hashable, Codable {
    public let id: String
    public let kind: TimingArtifactKind
    public let path: String
    public let status: TimingArtifactStatus
    public let sha256: String?
    public let byteCount: Int64?
    public let createdAt: Date
    public let provenance: TimingArtifactProvenance?

    public init(
        id: String,
        kind: TimingArtifactKind,
        path: String,
        status: TimingArtifactStatus,
        sha256: String? = nil,
        byteCount: Int64? = nil,
        createdAt: Date = Date(),
        provenance: TimingArtifactProvenance? = nil
    ) {
        self.id = id
        self.kind = kind
        self.path = path
        self.status = status
        self.sha256 = sha256
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.provenance = provenance
    }
}

public struct TimingModelSource: Sendable, Hashable, Codable {
    public let modelID: String
    public let modelKind: TimingModelKind
    public let sourceType: TimingModelSourceType
    public let artifactIDs: [String]
    public let notes: String?

    public init(
        modelID: String,
        modelKind: TimingModelKind,
        sourceType: TimingModelSourceType,
        artifactIDs: [String],
        notes: String? = nil
    ) {
        self.modelID = modelID
        self.modelKind = modelKind
        self.sourceType = sourceType
        self.artifactIDs = artifactIDs
        self.notes = notes
    }
}
