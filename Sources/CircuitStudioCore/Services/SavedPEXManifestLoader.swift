import Foundation

public struct SavedPEXManifestLoader: Sendable {
    private let artifactService: PEXArtifactService

    public init(artifactService: PEXArtifactService = PEXArtifactService()) {
        self.artifactService = artifactService
    }

    public func load(manifestURL: URL, cornerID: String) throws -> PEXExtractionResult {
        let manifest = try artifactService.loadManifest(manifestURL: manifestURL)
        let ir = try artifactService.loadIR(for: cornerID, manifestURL: manifestURL)
        return PEXExtractionResult(
            manifestURL: manifestURL,
            manifest: manifest,
            ir: ir
        )
    }
}
