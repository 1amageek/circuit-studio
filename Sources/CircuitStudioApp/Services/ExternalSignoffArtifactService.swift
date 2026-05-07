import Foundation

public struct ExternalSignoffLogArtifact: Sendable, Hashable {
    public let kind: ExternalSignoffToolReport.Kind
    public let toolName: String
    public let logURL: URL
    public let success: Bool

    public init(
        kind: ExternalSignoffToolReport.Kind,
        toolName: String,
        logURL: URL,
        success: Bool
    ) {
        self.kind = kind
        self.toolName = toolName
        self.logURL = logURL
        self.success = success
    }
}

public enum ExternalSignoffArtifactError: Error, LocalizedError, Equatable {
    case emptyArtifactSet
    case missingLog(String)
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyArtifactSet:
            return "External signoff artifact set is empty"
        case .missingLog(let path):
            return "External signoff log not found: \(path)"
        case .readFailed(let message):
            return "External signoff log read failed: \(message)"
        }
    }
}

public struct ExternalSignoffArtifactService: Sendable {
    private let parser: ExternalSignoffReportParser

    public init(parser: ExternalSignoffReportParser = ExternalSignoffReportParser()) {
        self.parser = parser
    }

    public func load(logs: [ExternalSignoffLogArtifact]) throws -> ExternalSignoffReview {
        guard !logs.isEmpty else {
            throw ExternalSignoffArtifactError.emptyArtifactSet
        }

        let reports = try logs.map { artifact in
            try load(log: artifact)
        }
        return ExternalSignoffReview(reports: reports)
    }

    private func load(log artifact: ExternalSignoffLogArtifact) throws -> ExternalSignoffToolReport {
        let path = artifact.logURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            throw ExternalSignoffArtifactError.missingLog(path)
        }

        let contents: String
        do {
            contents = try String(contentsOf: artifact.logURL, encoding: .utf8)
        } catch {
            throw ExternalSignoffArtifactError.readFailed(error.localizedDescription)
        }

        return parser.parse(
            kind: artifact.kind,
            toolName: artifact.toolName,
            logPath: path,
            rawOutput: contents,
            success: artifact.success
        )
    }
}
