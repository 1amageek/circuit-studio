import Foundation
import CircuitStudioCore

public struct TechnologyPackage: Sendable, Hashable {
    public let manifestURL: URL
    public let rootURL: URL
    public let manifest: TechnologyPackageManifest
    public let processConfiguration: ProcessConfiguration?
    public let pexProjectConfig: PEXProjectConfig?
    public let validationReport: TechnologyPackageValidationReport

    public init(
        manifestURL: URL,
        rootURL: URL,
        manifest: TechnologyPackageManifest,
        processConfiguration: ProcessConfiguration?,
        pexProjectConfig: PEXProjectConfig?,
        validationReport: TechnologyPackageValidationReport
    ) {
        self.manifestURL = manifestURL
        self.rootURL = rootURL
        self.manifest = manifest
        self.processConfiguration = processConfiguration
        self.pexProjectConfig = pexProjectConfig
        self.validationReport = validationReport
    }

    public func resolvedURL(for relativePath: String) -> URL {
        if relativePath.hasPrefix("/") {
            return URL(filePath: relativePath)
        }
        return rootURL.appending(path: relativePath)
    }
}
