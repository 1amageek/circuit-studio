import Foundation
import PEXEngine

public struct PEXExtractionService: Sendable {
    private let engine: any PEXRunning
    private let configMapper: PEXConfigMapper

    public init(
        engine: any PEXRunning = DefaultPEXEngine.withDefaults(),
        configMapper: PEXConfigMapper = PEXConfigMapper()
    ) {
        self.engine = engine
        self.configMapper = configMapper
    }

    public func extract(_ request: PEXExtractionRequest) async throws -> PEXExtractionResult {
        var config = try loadConfig(from: request.configURL)
        guard config.enabled else {
            throw PEXExtractionError.disabledConfiguration
        }
        config.corners = [request.cornerID]
        if let executablePath = request.executablePath {
            config.executablePath = executablePath
        }
        if let workspaceDirectory = request.workspaceDirectory {
            config.output.workspace = workspaceDirectory.path(percentEncoded: false)
        }

        let mappingURL = request.projectDirectory?
            .appending(path: request.configURL.lastPathComponent)
            ?? request.configURL
        let runRequest = try configMapper.mapToRunRequest(
            config: config,
            configFileURL: mappingURL
        )
        let runResult = try await engine.run(runRequest)
        guard let corner = runResult.cornerResults.first(where: {
            $0.cornerID == PEXCornerID(request.cornerID)
        }), let canonicalIR = corner.ir else {
            throw PEXExtractionError.missingCorner(request.cornerID)
        }
        return PEXExtractionResult(
            manifestURL: runResult.manifestURL,
            manifest: runResult.artifactManifest,
            ir: canonicalIR,
            runResult: runResult
        )
    }

    private func loadConfig(from url: URL) throws -> PEXProjectConfig {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PEXExtractionError.configurationReadFailed(error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode(PEXProjectConfig.self, from: data)
        } catch {
            throw PEXExtractionError.configurationDecodeFailed(error.localizedDescription)
        }
    }
}
