import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFileSystem
import CircuiteFoundationFoundation
import DesignFlowKernel
import Foundation

extension ArtifactReference {
    static func circuitStudioReference(
        kind: String,
        relativePath: String,
        data: Data,
        role: ArtifactRole = .output,
        digester: any ContentDigesting = SHA256ContentDigester()
    ) throws -> ArtifactReference {
        let locator = try circuitStudioLocator(
            kind: kind,
            relativePath: relativePath,
            role: role
        )
        let digest = try digester.digest(data: data, using: .sha256)
        return try ArtifactReference(
            digest: digest,
            byteCount: UInt64(data.count),
            descriptor: locator.descriptor
        )
    }

    static func circuitStudioReference(
        kind: String,
        relativePath: String,
        fileURL: URL,
        role: ArtifactRole = .output,
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
        return try referencer.reference(
            fileLocator,
            relativeTo: nil
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

extension FlowArtifactBinding {
    var circuitStudioPresentationPath: String {
        switch availability {
        case .local(_, _, let relativePath):
            relativePath.stringValue
        case .service:
            availabilityDescription
        }
    }

    static func circuitStudioBinding(
        logicalID: String,
        kind: String,
        relativePath: String,
        data: Data,
        role: ArtifactRole = .output,
        producer: ProducerIdentity? = nil,
        digester: any ContentDigesting = SHA256ContentDigester()
    ) throws -> FlowArtifactBinding {
        let canonicalPath = try RoundTripArtifactPath(relativePath).value
        let reference = try ArtifactReference.circuitStudioReference(
            kind: kind,
            relativePath: canonicalPath,
            data: data,
            role: role,
            digester: digester
        )
        return try makeCircuitStudioBinding(
            logicalID: logicalID,
            reference: reference,
            relativePath: canonicalPath,
            producer: producer
        )
    }

    static func circuitStudioBinding(
        logicalID: String,
        kind: String,
        relativePath: String,
        fileURL: URL,
        role: ArtifactRole = .output,
        producer: ProducerIdentity? = nil,
        referencer: any ArtifactReferencing = LocalArtifactReferencer()
    ) throws -> FlowArtifactBinding {
        let canonicalPath = try RoundTripArtifactPath(relativePath).value
        let reference = try ArtifactReference.circuitStudioReference(
            kind: kind,
            relativePath: canonicalPath,
            fileURL: fileURL,
            role: role,
            referencer: referencer
        )
        return try makeCircuitStudioBinding(
            logicalID: logicalID,
            reference: reference,
            relativePath: canonicalPath,
            producer: producer
        )
    }

    private static func makeCircuitStudioBinding(
        logicalID: String,
        reference: ArtifactReference,
        relativePath: String,
        producer: ProducerIdentity?
    ) throws -> FlowArtifactBinding {
        let availabilityPath = try ArtifactRelativePath(
            segments: relativePath.split(separator: "/").map(String.init)
        )
        return try FlowArtifactBinding(
            logicalID: logicalID,
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: ArtifactRootID(rawValue: "circuit-studio-run-directory"),
                relativePath: availabilityPath
            ),
            producer: producer
        )
    }
}
