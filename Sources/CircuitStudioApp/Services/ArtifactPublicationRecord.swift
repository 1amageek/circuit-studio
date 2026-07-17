import CircuiteFoundation
import Foundation

public enum ArtifactPublicationStatus: String, Sendable, Hashable, Codable {
    case available
    case omitted
    case missing
}

public enum ArtifactPublicationRecordValidationError: Error, LocalizedError, Equatable {
    case unavailableStatusRequired
    case payloadStatusMismatch

    public var errorDescription: String? {
        switch self {
        case .unavailableStatusRequired:
            return "An unavailable artifact declaration must be omitted or missing."
        case .payloadStatusMismatch:
            return "Artifact publication payload does not match its status."
        }
    }
}

public struct ArtifactPublicationRecord: Sendable, Hashable, Codable {
    public enum Payload: Sendable, Hashable, Codable {
        case available(ArtifactReference)
        case unavailable(id: ArtifactID, locator: ArtifactLocator)
    }

    public let payload: Payload
    public let status: ArtifactPublicationStatus
    public let createdAt: Date
    public let sourcePath: String?

    public init(
        reference: ArtifactReference,
        createdAt: Date = Date(),
        sourcePath: String? = nil
    ) {
        payload = .available(reference)
        status = .available
        self.createdAt = createdAt
        self.sourcePath = sourcePath
    }

    public init(
        id: ArtifactID,
        locator: ArtifactLocator,
        status: ArtifactPublicationStatus,
        createdAt: Date = Date(),
        sourcePath: String? = nil
    ) throws {
        switch status {
        case .available:
            throw ArtifactPublicationRecordValidationError.unavailableStatusRequired
        case .omitted, .missing:
            payload = .unavailable(id: id, locator: locator)
        }
        self.status = status
        self.createdAt = createdAt
        self.sourcePath = sourcePath
    }

    public var reference: ArtifactReference? {
        guard case .available(let reference) = payload else { return nil }
        return reference
    }

    public var id: String {
        switch payload {
        case .available(let reference):
            return reference.id.rawValue
        case .unavailable(let id, _):
            return id.rawValue
        }
    }

    public var locator: ArtifactLocator {
        switch payload {
        case .available(let reference):
            return reference.locator
        case .unavailable(_, let locator):
            return locator
        }
    }

    public var kind: String { locator.kind.rawValue }
    public var path: String { locator.path }
    public var sha256: String? { reference?.digest.hexadecimalValue }
    public var byteCount: Int64? { reference.map { Int64($0.byteCount) } }

    private enum CodingKeys: String, CodingKey {
        case payload
        case status
        case createdAt
        case sourcePath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let payload = try container.decode(Payload.self, forKey: .payload)
        let status = try container.decode(ArtifactPublicationStatus.self, forKey: .status)
        guard Self.matches(payload: payload, status: status) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: ArtifactPublicationRecordValidationError.payloadStatusMismatch.localizedDescription
                )
            )
        }
        self.payload = payload
        self.status = status
        createdAt = try TimingArtifactDateCoding.decode(from: container, forKey: .createdAt)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
    }

    public func encode(to encoder: Encoder) throws {
        guard Self.matches(payload: payload, status: status) else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: ArtifactPublicationRecordValidationError.payloadStatusMismatch.localizedDescription
                )
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(payload, forKey: .payload)
        try container.encode(status, forKey: .status)
        try TimingArtifactDateCoding.encode(createdAt, to: &container, forKey: .createdAt)
        try container.encodeIfPresent(sourcePath, forKey: .sourcePath)
    }

    private static func matches(payload: Payload, status: ArtifactPublicationStatus) -> Bool {
        switch (payload, status) {
        case (.available, .available), (.unavailable, .omitted), (.unavailable, .missing):
            return true
        default:
            return false
        }
    }
}
