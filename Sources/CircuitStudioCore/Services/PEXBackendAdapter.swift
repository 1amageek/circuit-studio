import Foundation
import PEXEngine

public struct PEXBackendExtractionRequest: Sendable, Hashable {
    public let configURL: URL
    public let workingDirectory: URL?
    public let cornerID: String
    public let executablePath: String?
    public let additionalArguments: [String]

    public init(
        configURL: URL,
        workingDirectory: URL? = nil,
        cornerID: String = "tt_25c_1v0",
        executablePath: String? = nil,
        additionalArguments: [String] = []
    ) {
        self.configURL = configURL
        self.workingDirectory = workingDirectory
        self.cornerID = cornerID
        self.executablePath = executablePath
        self.additionalArguments = additionalArguments
    }
}

public struct PEXBackendExtractionResult: Sendable, Hashable {
    public let manifestURL: URL
    public let manifest: PEXArtifactManifest
    public let ir: PEXParasiticIR
    public let commandResult: PEXCommandResult?

    public init(
        manifestURL: URL,
        manifest: PEXArtifactManifest,
        ir: PEXParasiticIR,
        commandResult: PEXCommandResult? = nil
    ) {
        self.manifestURL = manifestURL
        self.manifest = manifest
        self.ir = ir
        self.commandResult = commandResult
    }
}

public protocol PEXBackendAdapter: Sendable {
    var backendID: String { get }
    func extract(request: PEXBackendExtractionRequest) async throws -> PEXBackendExtractionResult
}

public enum PEXBackendAdapterError: Error, LocalizedError, Equatable {
    case missingManifestURLInCommandOutput
    case invalidManifestURL(String)

    public var errorDescription: String? {
        switch self {
        case .missingManifestURLInCommandOutput:
            return "PEX backend command output did not include artifacts.manifestURL."
        case .invalidManifestURL(let value):
            return "PEX backend command output included an invalid manifest URL: \(value)"
        }
    }
}

public struct SavedPEXManifestBackendAdapter: PEXBackendAdapter {
    public let backendID: String
    private let artifactService: PEXArtifactService

    public init(
        backendID: String = "saved-manifest",
        artifactService: PEXArtifactService = PEXArtifactService()
    ) {
        self.backendID = backendID
        self.artifactService = artifactService
    }

    public func extract(request: PEXBackendExtractionRequest) async throws -> PEXBackendExtractionResult {
        let manifest = try artifactService.loadManifest(manifestURL: request.configURL)
        let ir = try artifactService.loadIR(for: request.cornerID, manifestURL: request.configURL)
        return PEXBackendExtractionResult(manifestURL: request.configURL, manifest: manifest, ir: ir)
    }
}

public struct PEXEngineCommandBackendAdapter: PEXBackendAdapter {
    public let backendID: String
    private let executablePath: String?
    private let artifactService: PEXArtifactService

    public init(
        backendID: String = "pexengine-command",
        executablePath: String? = nil,
        artifactService: PEXArtifactService = PEXArtifactService()
    ) {
        self.backendID = backendID
        self.executablePath = executablePath
        self.artifactService = artifactService
    }

    public func extract(request: PEXBackendExtractionRequest) async throws -> PEXBackendExtractionResult {
        let commandService = PEXCommandService(executablePath: request.executablePath ?? executablePath)
        let arguments = request.additionalArguments.contains("--json")
            ? request.additionalArguments
            : request.additionalArguments + ["--json"]
        let result = try await commandService.extract(
            configURL: request.configURL,
            workingDirectory: request.workingDirectory,
            additionalArguments: arguments
        )
        let manifestURL = try manifestURL(from: result.standardOutput)
        let manifest = try artifactService.loadManifest(manifestURL: manifestURL)
        let ir = try artifactService.loadIR(for: request.cornerID, manifestURL: manifestURL)
        return PEXBackendExtractionResult(
            manifestURL: manifestURL,
            manifest: manifest,
            ir: ir,
            commandResult: result
        )
    }

    private func manifestURL(from standardOutput: String) throws -> URL {
        guard let data = standardOutput.data(using: .utf8) else {
            throw PEXBackendAdapterError.missingManifestURLInCommandOutput
        }
        do {
            let decoded = try JSONDecoder().decode(PEXCommandOutputDTO.self, from: data)
            let manifestURL = decoded.manifestURL ?? decoded.artifacts?.manifestURL
            guard let manifestURL else {
                throw PEXBackendAdapterError.missingManifestURLInCommandOutput
            }
            if let url = manifestURL.urlValue {
                return url
            }
            throw PEXBackendAdapterError.invalidManifestURL(manifestURL.value)
        } catch let error as PEXBackendAdapterError {
            throw error
        } catch {
            throw PEXBackendAdapterError.missingManifestURLInCommandOutput
        }
    }
}

private struct PEXCommandOutputDTO: Decodable {
    struct Artifacts: Decodable {
        let manifestURL: FlexibleURL
    }

    let manifestURL: FlexibleURL?
    let artifacts: Artifacts?
}

private struct FlexibleURL: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(String.self)
    }

    var urlValue: URL? {
        if value.hasPrefix("file://"), let url = URL(string: value) {
            return url
        }
        if value.hasPrefix("/") {
            return URL(filePath: value)
        }
        return nil
    }
}
