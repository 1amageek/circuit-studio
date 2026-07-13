import CircuiteFoundation
import DesignFlowKernel

/// Converts the frozen flow-record vocabulary into Foundation values at the
/// presentation boundary. The conversion is intentionally lossy-free for all
/// declared record cases and returns nil for a future open token that this UI
/// has not learned to render yet.
enum FoundationArtifactTypeProjection {
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
}
