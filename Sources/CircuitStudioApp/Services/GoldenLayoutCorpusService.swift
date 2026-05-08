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
        public let signoffLogs: [SignoffLog]
        public let signoffReview: ExternalSignoffReview

        public init(
            id: String,
            format: String,
            topCell: String,
            layoutURL: URL,
            signoffLogs: [SignoffLog],
            signoffReview: ExternalSignoffReview
        ) {
            self.id = id
            self.format = format
            self.topCell = topCell
            self.layoutURL = layoutURL
            self.signoffLogs = signoffLogs
            self.signoffReview = signoffReview
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

        return LayoutEntry(
            id: dto.id,
            format: dto.format,
            topCell: dto.topCell,
            layoutURL: layoutURL,
            signoffLogs: signoffLogs,
            signoffReview: review
        )
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
    let signoffLogs: [SignoffLogDTO]
}

private struct SignoffLogDTO: Decodable {
    let kind: String
    let toolName: String
    let logFile: String
    let success: Bool
}
