import CircuiteFoundation
import DesignFlowKernel
import Foundation

public enum ArtifactPublicationStatus: String, Sendable, Hashable, Codable {
    case available
    case omitted
    case missing
}

public enum ArtifactPublicationRecordValidationError: Error, LocalizedError, Equatable {
    case invalidLogicalID(String)
    case unavailableStatusRequired
    case localAvailabilityRequired(String)
    case payloadStatusMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidLogicalID(let logicalID):
            return "Artifact logical ID is invalid: \(logicalID)"
        case .unavailableStatusRequired:
            return "An unavailable artifact declaration must be omitted or missing."
        case .localAvailabilityRequired(let logicalID):
            return "Artifact publication requires local availability: \(logicalID)"
        case .payloadStatusMismatch:
            return "Artifact publication payload does not match its status."
        }
    }
}

public struct ArtifactPublicationRecord: Sendable, Hashable, Codable {
    public enum Payload: Sendable, Hashable, Codable {
        case available(FlowArtifactBinding)
        case unavailable(
            logicalID: String,
            descriptor: ArtifactDescriptor,
            relativePath: ArtifactRelativePath
        )
    }

    public let payload: Payload
    public let status: ArtifactPublicationStatus
    public let createdAt: Date
    public let sourcePath: String?

    public init(
        binding: FlowArtifactBinding,
        createdAt: Date = Date(),
        sourcePath: String? = nil
    ) throws {
        guard case .local = binding.availability else {
            throw ArtifactPublicationRecordValidationError.localAvailabilityRequired(binding.logicalID)
        }
        payload = .available(binding)
        status = .available
        self.createdAt = createdAt
        self.sourcePath = sourcePath
    }

    public init(
        logicalID: String,
        descriptor: ArtifactDescriptor,
        relativePath: ArtifactRelativePath,
        status: ArtifactPublicationStatus,
        createdAt: Date = Date(),
        sourcePath: String? = nil
    ) throws {
        do {
            try FlowIdentifierValidator().validate(logicalID, kind: .artifactID)
        } catch {
            throw ArtifactPublicationRecordValidationError.invalidLogicalID(logicalID)
        }
        switch status {
        case .available:
            throw ArtifactPublicationRecordValidationError.unavailableStatusRequired
        case .omitted, .missing:
            payload = .unavailable(
                logicalID: logicalID,
                descriptor: descriptor,
                relativePath: relativePath
            )
        }
        self.status = status
        self.createdAt = createdAt
        self.sourcePath = sourcePath
    }

    public var reference: ArtifactReference? {
        binding?.reference
    }

    public var binding: FlowArtifactBinding? {
        guard case .available(let binding) = payload else { return nil }
        return binding
    }

    public var id: String {
        switch payload {
        case .available(let binding):
            return binding.logicalID
        case .unavailable(let logicalID, _, _):
            return logicalID
        }
    }

    public var descriptor: ArtifactDescriptor {
        switch payload {
        case .available(let binding):
            return binding.descriptor
        case .unavailable(_, let descriptor, _):
            return descriptor
        }
    }

    public var relativePath: ArtifactRelativePath {
        switch payload {
        case .available(let binding):
            guard case .local(_, _, let relativePath) = binding.availability else {
                preconditionFailure("ArtifactPublicationRecord validated local availability at initialization.")
            }
            return relativePath
        case .unavailable(_, _, let relativePath):
            return relativePath
        }
    }

    public var kind: String { descriptor.kind.rawValue }
    public var path: String { relativePath.stringValue }
    public var sha256: String? { reference?.digest.hexadecimalValue }
    public var byteCount: UInt64? { reference?.byteCount }

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
        case (.available(let binding), .available):
            guard case .local = binding.availability else { return false }
            return true
        case (.unavailable(let logicalID, _, _), .omitted),
             (.unavailable(let logicalID, _, _), .missing):
            do {
                try FlowIdentifierValidator().validate(logicalID, kind: .artifactID)
                return true
            } catch {
                return false
            }
        default:
            return false
        }
    }
}
