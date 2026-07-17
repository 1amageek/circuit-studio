import Foundation
import PEXEngine

public struct PEXArtifactService: Sendable {
    public init() {}

    public func loadManifest(manifestURL: URL) throws -> PEXArtifactManifest {
        do {
            return try PEXArtifactResolver(manifestURL: manifestURL).manifest
        } catch {
            throw StudioError.projectLoadFailed("Failed to load PEX artifact manifest: \(describe(error))")
        }
    }

    public func loadIR(for cornerID: String, manifestURL: URL) throws -> ParasiticIR {
        do {
            let resolver = try PEXArtifactResolver(manifestURL: manifestURL)
            return try resolver.loadIR(cornerID: PEXCornerID(cornerID))
        } catch {
            throw StudioError.projectLoadFailed("PEX corner '\(cornerID)' has no readable IR artifact: \(describe(error))")
        }
    }

    public func auditArtifactURLs(manifestURL: URL, cornerID: String) throws -> [URL] {
        do {
            let resolver = try PEXArtifactResolver(manifestURL: manifestURL)
            let corner = PEXCornerID(cornerID)
            let records = resolver.records(kind: .rawOutput, cornerID: corner, availability: .available)
                + resolver.records(kind: .parasiticIR, cornerID: corner, availability: .available)
                + resolver.records(kind: .log, cornerID: corner, availability: .available)
            let artifactURLs = try records.map { try resolver.validatedURL(for: $0) }
            return [manifestURL] + artifactURLs
        } catch {
            throw StudioError.projectLoadFailed("Failed to resolve PEX audit artifacts: \(describe(error))")
        }
    }

    private func describe(_ error: any Error) -> String {
        if let pexError = error as? PEXError {
            return pexError.description
        }
        return error.localizedDescription
    }

}
