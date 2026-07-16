import Foundation
import PEXEngine

public struct PEXExtractionResult: Sendable, Hashable {
    public let manifestURL: URL
    public let manifest: PEXArtifactManifest
    public let ir: PEXParasiticIR
    public let runResult: PEXRunResult?

    public init(
        manifestURL: URL,
        manifest: PEXArtifactManifest,
        ir: PEXParasiticIR,
        runResult: PEXRunResult? = nil
    ) {
        self.manifestURL = manifestURL
        self.manifest = manifest
        self.ir = ir
        self.runResult = runResult
    }
}
