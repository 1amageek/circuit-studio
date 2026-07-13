import ArtifactCore
import CircuiteFoundation

public protocol CircuitArtifactTypeResolving: Sendable {
    func artifactType(
        kind: ArtifactKind,
        format: ArtifactFormat
    ) -> ArtifactType?
}
