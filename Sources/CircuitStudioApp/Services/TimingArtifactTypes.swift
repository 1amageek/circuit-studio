import CircuiteFoundation
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
    case modelProfileSelection = "model-profile-selection"
    case staReport = "sta-report"
    case characterizationReport = "characterization-report"
    case measurementLog = "measurement-log"
    case spiceDeck = "spice-deck"
    case waveformCSV = "waveform-csv"
    case validationReport = "validation-report"
}

public struct TimingModelProfileReference: Sendable, Hashable, Codable {
    public let profileID: String
    public let resourceName: String?
    public let path: String?
    public let sha256: String?

    public init(
        profileID: String,
        resourceName: String? = nil,
        path: String? = nil,
        sha256: String? = nil
    ) {
        self.profileID = profileID
        self.resourceName = resourceName
        self.path = path
        self.sha256 = sha256
    }
}

public struct TimingTechnologyContext: Sendable, Hashable, Codable {
    public let processName: String
    public let cornerID: String
    public let supplyVoltage: Double
    public let temperatureC: Double?
    public let deviceModelID: String
    public let deviceModelHash: String?
    public let modelProfile: TimingModelProfileReference?

    public init(
        processName: String,
        cornerID: String,
        supplyVoltage: Double,
        temperatureC: Double? = nil,
        deviceModelID: String,
        deviceModelHash: String? = nil,
        modelProfile: TimingModelProfileReference? = nil
    ) {
        self.processName = processName
        self.cornerID = cornerID
        self.supplyVoltage = supplyVoltage
        self.temperatureC = temperatureC
        self.deviceModelID = deviceModelID
        self.deviceModelHash = deviceModelHash
        self.modelProfile = modelProfile
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
    public let publication: ArtifactPublicationRecord
    public let kind: TimingArtifactKind
    public let provenance: TimingArtifactProvenance?

    public init(
        reference: ArtifactReference,
        kind: TimingArtifactKind,
        createdAt: Date = Date(),
        provenance: TimingArtifactProvenance? = nil
    ) {
        publication = ArtifactPublicationRecord(
            reference: reference,
            createdAt: createdAt,
            sourcePath: provenance?.sourcePath
        )
        self.kind = kind
        self.provenance = provenance
    }

    public init(
        id: ArtifactID,
        locator: ArtifactLocator,
        kind: TimingArtifactKind,
        status: TimingArtifactStatus,
        createdAt: Date = Date(),
        provenance: TimingArtifactProvenance? = nil
    ) throws {
        publication = try ArtifactPublicationRecord(
            id: id,
            locator: locator,
            status: ArtifactPublicationStatus(timingStatus: status),
            createdAt: createdAt,
            sourcePath: provenance?.sourcePath
        )
        self.kind = kind
        self.provenance = provenance
    }

    public init(publicationRecord: ArtifactPublicationRecord, kind: TimingArtifactKind) {
        publication = publicationRecord
        self.kind = kind
        provenance = publicationRecord.sourcePath.map {
            TimingArtifactProvenance(sourcePath: $0)
        }
    }

    public var id: String { publication.id }
    public var path: String { publication.path }
    public var status: TimingArtifactStatus { TimingArtifactStatus(publicationStatus: publication.status) }
    public var reference: ArtifactReference? { publication.reference }
    public var locator: ArtifactLocator { publication.locator }
    public var sha256: String? { reference?.digest.hexadecimalValue }
    public var byteCount: Int64? { reference.map { Int64($0.byteCount) } }
    public var createdAt: Date { publication.createdAt }
}

extension TimingArtifactStatus {
    fileprivate init(publicationStatus: ArtifactPublicationStatus) {
        switch publicationStatus {
        case .available:
            self = .available
        case .omitted:
            self = .omitted
        case .missing:
            self = .missing
        }
    }
}

extension ArtifactPublicationStatus {
    fileprivate init(timingStatus: TimingArtifactStatus) {
        switch timingStatus {
        case .available:
            self = .available
        case .omitted:
            self = .omitted
        case .missing:
            self = .missing
        }
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
