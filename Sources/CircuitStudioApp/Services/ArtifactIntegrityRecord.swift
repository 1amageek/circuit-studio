import Foundation

public protocol ArtifactIntegrityRecord: Sendable {
    var artifactKind: String { get }
    var artifactPath: String { get }
    var artifactSHA256: String? { get }
    var artifactByteCount: Int64? { get }
    var artifactIsAvailable: Bool { get }
}

extension HeadlessRoundTripService.Artifact: ArtifactIntegrityRecord {
    public var artifactKind: String { kind }
    public var artifactPath: String { path }
    public var artifactSHA256: String? { sha256 }
    public var artifactByteCount: Int64? { byteCount }
    public var artifactIsAvailable: Bool { true }
}

extension TimingArtifactRecord: ArtifactIntegrityRecord {
    public var artifactKind: String { kind.rawValue }
    public var artifactPath: String { path }
    public var artifactSHA256: String? { sha256 }
    public var artifactByteCount: Int64? { byteCount }
    public var artifactIsAvailable: Bool { status == .available }
}
