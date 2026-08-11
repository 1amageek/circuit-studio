import CircuiteFoundation
import DesignFlowKernel

public protocol ArtifactIntegrityRecord: Sendable {
    var artifactLogicalID: String { get }
    var artifactDescriptor: ArtifactDescriptor { get }
    var artifactRelativePath: ArtifactRelativePath { get throws }
    var artifactBinding: FlowArtifactBinding? { get }
    var artifactIsAvailable: Bool { get }
}

extension ArtifactPublicationRecord: ArtifactIntegrityRecord {
    public var artifactLogicalID: String { id }
    public var artifactDescriptor: ArtifactDescriptor { descriptor }
    public var artifactRelativePath: ArtifactRelativePath { relativePath }
    public var artifactBinding: FlowArtifactBinding? { binding }
    public var artifactIsAvailable: Bool { status == .available }
}

extension HeadlessRoundTripService.Artifact: ArtifactIntegrityRecord {
    public var artifactLogicalID: String { binding.logicalID }
    public var artifactDescriptor: ArtifactDescriptor { binding.descriptor }
    public var artifactRelativePath: ArtifactRelativePath { get throws { try relativePath } }
    public var artifactBinding: FlowArtifactBinding? { binding }
    public var artifactIsAvailable: Bool { true }
}

extension TimingArtifactRecord: ArtifactIntegrityRecord {
    public var artifactLogicalID: String { id }
    public var artifactDescriptor: ArtifactDescriptor { publication.descriptor }
    public var artifactRelativePath: ArtifactRelativePath { publication.relativePath }
    public var artifactBinding: FlowArtifactBinding? { publication.binding }
    public var artifactIsAvailable: Bool { status == .available }
}
