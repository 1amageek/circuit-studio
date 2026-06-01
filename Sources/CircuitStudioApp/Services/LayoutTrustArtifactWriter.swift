import Foundation
import LayoutCore

public enum LayoutTrustArtifactWriterError: Error, LocalizedError, Equatable {
    case directoryCreationFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let path):
            return "Failed to create layout trust artifact directory at \(path)."
        case .writeFailed(let path):
            return "Failed to write layout trust artifact at \(path)."
        }
    }
}

public struct LayoutTrustArtifactWriter: Sendable {
    public struct WriteResult: Sendable, Hashable, Codable {
        public let directoryPath: String
        public let canonicalLayoutPath: String
        public let ownershipMapPath: String
        public let netAwareReportPath: String
        public let layoutTrustReportPath: String

        public init(
            directoryPath: String,
            canonicalLayoutPath: String,
            ownershipMapPath: String,
            netAwareReportPath: String,
            layoutTrustReportPath: String
        ) {
            self.directoryPath = directoryPath
            self.canonicalLayoutPath = canonicalLayoutPath
            self.ownershipMapPath = ownershipMapPath
            self.netAwareReportPath = netAwareReportPath
            self.layoutTrustReportPath = layoutTrustReportPath
        }
    }

    public init() {}

    public func write(
        document: LayoutDocument,
        report: LayoutTrustReport,
        to directory: URL
    ) throws -> WriteResult {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw LayoutTrustArtifactWriterError.directoryCreationFailed(directory.path(percentEncoded: false))
        }

        let canonicalLayoutURL = directory.appending(path: "canonical-layout.json")
        let ownershipMapURL = directory.appending(path: "ownership-map.json")
        let netAwareReportURL = directory.appending(path: "net-aware-report.json")
        let layoutTrustReportURL = directory.appending(path: "layout-trust-report.json")

        try writeJSON(document, to: canonicalLayoutURL)
        try writeJSON(report.ownershipMap, to: ownershipMapURL)
        try writeJSON(report.netAwareReport, to: netAwareReportURL)
        try writeJSON(report, to: layoutTrustReportURL)

        return WriteResult(
            directoryPath: directory.path(percentEncoded: false),
            canonicalLayoutPath: canonicalLayoutURL.path(percentEncoded: false),
            ownershipMapPath: ownershipMapURL.path(percentEncoded: false),
            netAwareReportPath: netAwareReportURL.path(percentEncoded: false),
            layoutTrustReportPath: layoutTrustReportURL.path(percentEncoded: false)
        )
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            throw LayoutTrustArtifactWriterError.writeFailed(url.path(percentEncoded: false))
        }
    }
}
