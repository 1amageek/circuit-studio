import CircuiteFoundation
import Foundation

extension ArtifactReference {
    static func circuitStudioReference(
        id: String,
        kind: String,
        relativePath: String,
        data: Data,
        role: ArtifactRole = .output,
        producer: ProducerIdentity? = nil,
        digester: any ContentDigesting = SHA256ContentDigester()
    ) throws -> ArtifactReference {
        let locator = try circuitStudioLocator(
            kind: kind,
            relativePath: relativePath,
            role: role
        )
        let digest = try digester.digest(data: data, using: .sha256)
        return ArtifactReference(
            id: try ArtifactID(rawValue: id),
            locator: locator,
            digest: digest,
            byteCount: UInt64(data.count),
            producer: producer
        )
    }

    static func circuitStudioReference(
        id: String,
        kind: String,
        relativePath: String,
        fileURL: URL,
        role: ArtifactRole = .output,
        producer: ProducerIdentity? = nil,
        referencer: any ArtifactReferencing = LocalArtifactReferencer()
    ) throws -> ArtifactReference {
        let locator = try circuitStudioLocator(
            kind: kind,
            relativePath: relativePath,
            role: role
        )
        let fileLocator = ArtifactLocator(
            location: try ArtifactLocation(fileURL: fileURL),
            role: locator.role,
            kind: locator.kind,
            format: locator.format
        )
        let fileReference = try referencer.reference(
            fileLocator,
            relativeTo: nil,
            producer: producer
        )
        return ArtifactReference(
            id: try ArtifactID(rawValue: id),
            locator: locator,
            digest: fileReference.digest,
            byteCount: fileReference.byteCount,
            producer: producer
        )
    }

    static func circuitStudioLocator(
        kind: String,
        relativePath: String,
        role: ArtifactRole = .output
    ) throws -> ArtifactLocator {
        ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: relativePath),
            role: role,
            kind: try ArtifactKind(rawValue: kind),
            format: try ArtifactFormat(rawValue: circuitStudioFormat(for: relativePath))
        )
    }

    var circuitStudioPath: String {
        locator.location.value
    }

    var circuitStudioSHA256: String {
        digest.hexadecimalValue
    }

    var circuitStudioByteCount: Int64 {
        Int64(byteCount)
    }

    private static func circuitStudioFormat(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "gds":
            return ArtifactFormat.gdsii.rawValue
        case "cir", "sp", "spice", "net":
            return ArtifactFormat.spice.rawValue
        case "json":
            return ArtifactFormat.json.rawValue
        case "txt", "log", "md":
            return ArtifactFormat.text.rawValue
        case let value where !value.isEmpty:
            return value
        default:
            return ArtifactFormat.unknown.rawValue
        }
    }
}
