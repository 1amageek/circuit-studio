import ArtifactCore
import XcircuitePackage

public protocol CircuitArtifactTypeResolving: Sendable {
    func artifactType(
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat
    ) -> ArtifactType?
}
