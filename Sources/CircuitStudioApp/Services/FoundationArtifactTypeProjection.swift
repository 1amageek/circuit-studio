import Foundation
import CircuiteFoundation
import DesignFlowKernel

/// Converts the frozen flow-record vocabulary into Foundation values at the
/// presentation boundary. The conversion is intentionally lossy-free for all
/// declared record cases and returns nil for a future open token that this UI
/// has not learned to render yet.
enum FoundationArtifactTypeProjection {
    enum ConversionError: Error {
        case byteCountOutOfRange(String)
        case invalidLocation(String)
    }

    static func kind(_ value: XcircuiteFileKind) -> ArtifactKind? {
        let rawValue: String
        switch value {
        case .powerIntent:
            rawValue = "power-intent"
        case .timingLibrary:
            rawValue = "timing-library"
        case .testPattern:
            rawValue = "test-pattern"
        case .ruleDeck:
            rawValue = "rule-deck"
        default:
            rawValue = value.rawValue
        }
        do {
            return try ArtifactKind(rawValue: rawValue)
        } catch {
            return nil
        }
    }

    static func format(_ value: XcircuiteFileFormat) -> ArtifactFormat? {
        let normalized = value.rawValue
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        do {
            return try ArtifactFormat(rawValue: normalized)
        } catch {
            return nil
        }
    }

    static func reference(_ value: XcircuiteFileReference) -> ArtifactReference? {
        guard let digest = value.sha256, !digest.isEmpty,
              let byteCount = value.byteCount, byteCount >= 0,
              let kind = kind(value.kind),
              let format = format(value.format) else {
            return nil
        }
        do {
            let location: ArtifactLocation
            if value.path.hasPrefix("/") {
                location = try ArtifactLocation(fileURL: URL(filePath: value.path))
            } else {
                location = try ArtifactLocation(workspaceRelativePath: value.path)
            }
            return try ArtifactReference(
                id: value.artifactID.map { try ArtifactID(rawValue: $0) },
                locator: ArtifactLocator(
                    location: location,
                    role: .output,
                    kind: kind,
                    format: format
                ),
                digest: try ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: digest
                ),
                byteCount: UInt64(byteCount),
                producer: nil
            )
        } catch {
            return nil
        }
    }

    /// Projects a frozen manifest record even when the legacy record did not
    /// persist integrity metadata. Missing values are represented by a zero
    /// digest and zero byte count so callers can retain the artifact in the
    /// canonical model and let the verifier report the unverified state.
    static func referencePreservingUnverifiedIntegrity(
        _ value: XcircuiteFileReference
    ) -> ArtifactReference? {
        guard let kind = kind(value.kind),
              let format = format(value.format),
              value.byteCount == nil || value.byteCount! >= 0 else {
            return nil
        }

        let digestValue = value.sha256.flatMap { $0.isEmpty ? nil : $0 }
            ?? String(repeating: "0", count: 64)
        let byteCount = UInt64(value.byteCount ?? 0)
        do {
            let location: ArtifactLocation
            if value.path.hasPrefix("/") {
                location = try ArtifactLocation(fileURL: URL(filePath: value.path))
            } else {
                location = try ArtifactLocation(workspaceRelativePath: value.path)
            }
            return try ArtifactReference(
                id: value.artifactID.map { try ArtifactID(rawValue: $0) },
                locator: ArtifactLocator(
                    location: location,
                    role: .legacyUnspecified,
                    kind: kind,
                    format: format
                ),
                digest: try ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: digestValue
                ),
                byteCount: byteCount,
                producer: nil
            )
        } catch {
            return nil
        }
    }

    static func legacyReference(_ value: ArtifactReference) throws -> XcircuiteFileReference {
        guard value.byteCount <= UInt64(Int64.max) else {
            throw ConversionError.byteCountOutOfRange(value.locator.location.value)
        }
        let path: String
        switch value.locator.location.storage {
        case .workspaceRelative:
            path = value.locator.location.value
        case .absoluteFileURL:
            guard let url = URL(string: value.locator.location.value), url.isFileURL else {
                throw ConversionError.invalidLocation(value.locator.location.value)
            }
            path = url.path
        }
        let kind = XcircuiteFileKind(rawValue: legacyKindRawValue(value.locator.kind)) ?? .other
        let format = XcircuiteFileFormat(rawValue: legacyFormatRawValue(value.locator.format)) ?? .unknown
        return XcircuiteFileReference(
            artifactID: value.id.rawValue,
            path: path,
            kind: kind,
            format: format,
            sha256: value.digest.hexadecimalValue,
            byteCount: Int64(value.byteCount)
        )
    }

    private static func legacyKindRawValue(_ value: ArtifactKind) -> String {
        switch value.rawValue {
        case "power-intent": return XcircuiteFileKind.powerIntent.rawValue
        case "timing-library": return XcircuiteFileKind.timingLibrary.rawValue
        case "test-pattern": return XcircuiteFileKind.testPattern.rawValue
        case "rule-deck": return XcircuiteFileKind.ruleDeck.rawValue
        case "design-diff": return XcircuiteFileKind.designDiff.rawValue
        case "parasitics": return XcircuiteFileKind.parasitic.rawValue
        default: return value.rawValue
        }
    }

    private static func legacyFormatRawValue(_ value: ArtifactFormat) -> String {
        switch value.rawValue {
        case "system-verilog": return XcircuiteFileFormat.systemVerilog.rawValue
        default: return value.rawValue.uppercased()
        }
    }
}
