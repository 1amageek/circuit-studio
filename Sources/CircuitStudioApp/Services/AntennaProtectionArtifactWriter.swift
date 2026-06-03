import Foundation

public struct AntennaProtectionArtifactWriter: Sendable {
    public init() {}

    public func write(_ plan: AntennaProtectionPlan, to url: URL) throws -> ArtifactPublicationRecord {
        try ArtifactPublisher(runDirectory: url.deletingLastPathComponent()).publishJSON(
            plan,
            id: AntennaProtectionPlan.artifactKind,
            kind: AntennaProtectionPlan.artifactKind,
            relativePath: url.lastPathComponent
        )
    }
}
