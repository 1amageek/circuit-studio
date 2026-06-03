import Foundation

public enum ArtifactPublicationStatus: String, Sendable, Hashable, Codable {
    case available
    case omitted
    case missing
}

public struct ArtifactPublicationRecord: Sendable, Hashable, Codable {
    public let id: String
    public let kind: String
    public let path: String
    public let status: ArtifactPublicationStatus
    public let sha256: String?
    public let byteCount: Int64?
    public let createdAt: Date
    public let sourcePath: String?

    public init(
        id: String,
        kind: String,
        path: String,
        status: ArtifactPublicationStatus,
        sha256: String? = nil,
        byteCount: Int64? = nil,
        createdAt: Date = Date(),
        sourcePath: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.path = path
        self.status = status
        self.sha256 = sha256
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.sourcePath = sourcePath
    }
}

extension ArtifactPublicationRecord: ArtifactIntegrityRecord {
    public var artifactKind: String { kind }
    public var artifactPath: String { path }
    public var artifactSHA256: String? { sha256 }
    public var artifactByteCount: Int64? { byteCount }
    public var artifactIsAvailable: Bool { status == .available }
}

extension ArtifactPublicationRecord {
    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case path
        case status
        case sha256
        case byteCount
        case createdAt
        case sourcePath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedStatus = try container.decode(ArtifactPublicationStatus.self, forKey: .status)
        let decodedSHA256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        let decodedByteCount = try container.decodeIfPresent(Int64.self, forKey: .byteCount)
        if let validationError = Self.validationErrorDescription(
            status: decodedStatus,
            sha256: decodedSHA256,
            byteCount: decodedByteCount
        ) {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: validationError)
            )
        }

        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        path = try container.decode(String.self, forKey: .path)
        status = decodedStatus
        sha256 = decodedSHA256
        byteCount = decodedByteCount
        createdAt = try TimingArtifactDateCoding.decode(from: container, forKey: .createdAt)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
    }

    public func encode(to encoder: Encoder) throws {
        if let validationError = Self.validationErrorDescription(
            status: status,
            sha256: sha256,
            byteCount: byteCount
        ) {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(codingPath: encoder.codingPath, debugDescription: validationError)
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
        try container.encodeIfPresent(sourcePath, forKey: .sourcePath)
    }

    private static func validationErrorDescription(
        status: ArtifactPublicationStatus,
        sha256: String?,
        byteCount: Int64?
    ) -> String? {
        if let byteCount, byteCount < 0 {
            return "Artifact byteCount must be non-negative."
        }
        guard status == .available else {
            return nil
        }
        guard let sha256, RoundTripArtifactDigest.isValidSHA256(sha256) else {
            return "Available artifacts must include a 64-character hexadecimal sha256 digest."
        }
        guard byteCount != nil else {
            return "Available artifacts must include byteCount."
        }
        return nil
    }
}
