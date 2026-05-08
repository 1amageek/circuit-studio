import Foundation
import CircuitStudioCore

public struct GoldenLayoutCorpusService: Sendable {
    public struct Corpus: Sendable, Hashable {
        public let id: String
        public let layouts: [LayoutEntry]

        public init(id: String, layouts: [LayoutEntry]) {
            self.id = id
            self.layouts = layouts
        }
    }

    public struct LayoutEntry: Sendable, Hashable {
        public let id: String
        public let format: String
        public let topCell: String
        public let layoutURL: URL
        public let technologyFiles: [TechnologyFile]
        public let signoffLogs: [SignoffLog]
        public let signoffReview: ExternalSignoffReview
        public let pexManifests: [PEXManifest]
        public let requiresApproval: Bool

        public init(
            id: String,
            format: String,
            topCell: String,
            layoutURL: URL,
            technologyFiles: [TechnologyFile],
            signoffLogs: [SignoffLog],
            signoffReview: ExternalSignoffReview,
            pexManifests: [PEXManifest],
            requiresApproval: Bool
        ) {
            self.id = id
            self.format = format
            self.topCell = topCell
            self.layoutURL = layoutURL
            self.technologyFiles = technologyFiles
            self.signoffLogs = signoffLogs
            self.signoffReview = signoffReview
            self.pexManifests = pexManifests
            self.requiresApproval = requiresApproval
        }
    }

    public struct TechnologyFile: Sendable, Hashable {
        public let kind: String
        public let fileURL: URL

        public init(kind: String, fileURL: URL) {
            self.kind = kind
            self.fileURL = fileURL
        }
    }

    public struct SignoffLog: Sendable, Hashable {
        public let kind: ExternalSignoffToolReport.Kind
        public let toolName: String
        public let logURL: URL
        public let success: Bool

        public init(kind: ExternalSignoffToolReport.Kind, toolName: String, logURL: URL, success: Bool) {
            self.kind = kind
            self.toolName = toolName
            self.logURL = logURL
            self.success = success
        }
    }

    public struct PEXManifest: Sendable, Hashable {
        public let manifestURL: URL
        public let defaultCornerID: String?
        public let artifacts: PEXRunArtifacts

        public init(manifestURL: URL, defaultCornerID: String?, artifacts: PEXRunArtifacts) {
            self.manifestURL = manifestURL
            self.defaultCornerID = defaultCornerID
            self.artifacts = artifacts
        }
    }

    private let decoder: JSONDecoder

    public init() {
        self.decoder = JSONDecoder()
    }

    public func load(manifestURL: URL) throws -> Corpus {
        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL)
        } catch {
            throw StudioError.projectLoadFailed("Failed to read golden layout corpus manifest: \(error.localizedDescription)")
        }

        let manifest: ManifestDTO
        do {
            manifest = try decoder.decode(ManifestDTO.self, from: manifestData)
        } catch {
            throw StudioError.projectLoadFailed("Failed to decode golden layout corpus manifest: \(error.localizedDescription)")
        }

        let root = manifestURL.deletingLastPathComponent()
        let layouts = try manifest.layouts.map { dto in
            try loadLayoutEntry(dto, root: root)
        }
        return Corpus(id: manifest.corpusID, layouts: layouts)
    }

    private func loadLayoutEntry(_ dto: LayoutDTO, root: URL) throws -> LayoutEntry {
        let layoutURL = root.appending(path: dto.layoutFile)
        guard FileManager.default.fileExists(atPath: layoutURL.path(percentEncoded: false)) else {
            throw StudioError.fileNotFound(layoutURL.path(percentEncoded: false))
        }

        let signoffLogs = try dto.signoffLogs.map { logDTO in
            try loadSignoffLog(logDTO, root: root)
        }
        let review = try ExternalSignoffArtifactService().load(
            logs: signoffLogs.map { log in
                ExternalSignoffLogArtifact(
                    kind: log.kind,
                    toolName: log.toolName,
                    logURL: log.logURL,
                    success: log.success
                )
            }
        )
        let technologyFiles = try (dto.technologyFiles ?? []).map { technologyDTO in
            try loadTechnologyFile(technologyDTO, root: root)
        }
        let pexManifests = try (dto.pexManifests ?? []).map { pexDTO in
            try loadPEXManifest(pexDTO, root: root)
        }

        return LayoutEntry(
            id: dto.id,
            format: dto.format,
            topCell: dto.topCell,
            layoutURL: layoutURL,
            technologyFiles: technologyFiles,
            signoffLogs: signoffLogs,
            signoffReview: review,
            pexManifests: pexManifests,
            requiresApproval: dto.requiresApproval ?? true
        )
    }

    private func loadTechnologyFile(_ dto: TechnologyFileDTO, root: URL) throws -> TechnologyFile {
        let fileURL = root.appending(path: dto.file)
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            throw StudioError.fileNotFound(fileURL.path(percentEncoded: false))
        }

        return TechnologyFile(kind: dto.kind, fileURL: fileURL)
    }

    private func loadSignoffLog(_ dto: SignoffLogDTO, root: URL) throws -> SignoffLog {
        guard let kind = ExternalSignoffToolReport.Kind(rawValue: dto.kind) else {
            throw StudioError.projectLoadFailed("Unsupported signoff log kind in golden layout corpus: \(dto.kind)")
        }

        let logURL = root.appending(path: dto.logFile)
        guard FileManager.default.fileExists(atPath: logURL.path(percentEncoded: false)) else {
            throw StudioError.fileNotFound(logURL.path(percentEncoded: false))
        }

        return SignoffLog(
            kind: kind,
            toolName: dto.toolName,
            logURL: logURL,
            success: dto.success
        )
    }

    private func loadPEXManifest(_ dto: PEXManifestDTO, root: URL) throws -> PEXManifest {
        let manifestURL = root.appending(path: dto.manifestFile)
        guard FileManager.default.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
            throw StudioError.fileNotFound(manifestURL.path(percentEncoded: false))
        }

        let artifacts = try PEXArtifactService().loadArtifacts(manifestURL: manifestURL)
        return PEXManifest(
            manifestURL: manifestURL,
            defaultCornerID: dto.defaultCornerID,
            artifacts: artifacts
        )
    }
}

private struct ManifestDTO: Decodable {
    let corpusID: String
    let layouts: [LayoutDTO]
}

private struct LayoutDTO: Decodable {
    let id: String
    let format: String
    let topCell: String
    let layoutFile: String
    let technologyFiles: [TechnologyFileDTO]?
    let signoffLogs: [SignoffLogDTO]
    let pexManifests: [PEXManifestDTO]?
    let requiresApproval: Bool?
}

private struct TechnologyFileDTO: Decodable {
    let kind: String
    let file: String
}

private struct SignoffLogDTO: Decodable {
    let kind: String
    let toolName: String
    let logFile: String
    let success: Bool
}

private struct PEXManifestDTO: Decodable {
    let manifestFile: String
    let defaultCornerID: String?
}
