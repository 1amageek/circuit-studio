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

    public init(publicationRecord: ArtifactPublicationRecord, kind: TimingArtifactKind) {
        self.init(
            id: publicationRecord.id,
            kind: kind,
            path: publicationRecord.path,
            status: TimingArtifactStatus(publicationStatus: publicationRecord.status),
            sha256: publicationRecord.sha256,
            byteCount: publicationRecord.byteCount,
            createdAt: publicationRecord.createdAt,
            provenance: publicationRecord.sourcePath.map {
                TimingArtifactProvenance(sourcePath: $0)
            }
        )
    }
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

extension TimingArtifactRecord {
    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case path
        case status
        case sha256
        case byteCount
        case createdAt
        case provenance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedStatus = try container.decode(TimingArtifactStatus.self, forKey: .status)
        let decodedSha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        let decodedByteCount = try container.decodeIfPresent(Int64.self, forKey: .byteCount)
        if let validationError = Self.validationErrorDescription(
            status: decodedStatus,
            sha256: decodedSha256,
            byteCount: decodedByteCount
        ) {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: validationError
                )
            )
        }

        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(TimingArtifactKind.self, forKey: .kind)
        path = try container.decode(String.self, forKey: .path)
        status = decodedStatus
        sha256 = decodedSha256
        byteCount = decodedByteCount
        createdAt = try TimingArtifactDateCoding.decode(from: container, forKey: .createdAt)
        provenance = try container.decodeIfPresent(TimingArtifactProvenance.self, forKey: .provenance)
    }

    public func encode(to encoder: Encoder) throws {
        if let validationError = Self.validationErrorDescription(
            status: status,
            sha256: sha256,
            byteCount: byteCount
        ) {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: validationError
                )
            )
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(path, forKey: .path)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(sha256, forKey: .sha256)
        try container.encodeIfPresent(byteCount, forKey: .byteCount)
        try TimingArtifactDateCoding.encode(createdAt, to: &container, forKey: .createdAt)
        try container.encodeIfPresent(provenance, forKey: .provenance)
    }

    private static func validationErrorDescription(
        status: TimingArtifactStatus,
        sha256: String?,
        byteCount: Int64?
    ) -> String? {
        if let byteCount, byteCount < 0 {
            return "Timing artifact byteCount must be non-negative."
        }
        guard status == .available else {
            return nil
        }
        guard let sha256, RoundTripArtifactDigest.isValidSHA256(sha256) else {
            return "Available timing artifacts must include a 64-character hexadecimal sha256 digest."
        }
        guard byteCount != nil else {
            return "Available timing artifacts must include byteCount."
        }
        return nil
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
