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
            config.executablePath = URL(filePath: executablePath).path(percentEncoded: false)
        }
        if let workspaceDirectory = request.workspaceDirectory {
            config.output.workspace = workspaceDirectory.path(percentEncoded: false)
        }

        let runRequest = try configMapper.mapToRunRequest(
            config: config,
            configFileURL: request.configURL
        )
        let runResult = try await engine.run(runRequest)
        guard runResult.status == .success else {
            throw PEXExtractionError.executionFailed(runResult)
        }
        guard let corner = runResult.cornerResults.first(where: {
            $0.cornerID == PEXCornerID(request.cornerID)
        }) else {
            throw PEXExtractionError.missingCorner(request.cornerID)
        }
        guard corner.status == .success else {
            throw PEXExtractionError.executionFailed(runResult)
        }
        guard let canonicalIR = corner.ir else {
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
