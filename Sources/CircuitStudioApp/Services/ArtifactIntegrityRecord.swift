import CircuiteFoundation

public protocol ArtifactIntegrityRecord: Sendable {
    var artifactLocator: ArtifactLocator { get }
    var artifactReference: ArtifactReference? { get }
    var artifactIsAvailable: Bool { get }
}

extension ArtifactPublicationRecord: ArtifactIntegrityRecord {
    public var artifactLocator: ArtifactLocator { locator }
    public var artifactReference: ArtifactReference? { reference }
    public var artifactIsAvailable: Bool { status == .available }
}

extension ArtifactReference: ArtifactIntegrityRecord {
    public var artifactLocator: ArtifactLocator { locator }
    public var artifactReference: ArtifactReference? { self }
    public var artifactIsAvailable: Bool { true }
}

extension HeadlessRoundTripService.Artifact: ArtifactIntegrityRecord {
    public var artifactLocator: ArtifactLocator { reference.locator }
    public var artifactReference: ArtifactReference? { reference }
    public var artifactIsAvailable: Bool { true }
}

extension TimingArtifactRecord: ArtifactIntegrityRecord {
    public var artifactLocator: ArtifactLocator { locator }
    public var artifactReference: ArtifactReference? { reference }
    public var artifactIsAvailable: Bool { status == .available }
}
