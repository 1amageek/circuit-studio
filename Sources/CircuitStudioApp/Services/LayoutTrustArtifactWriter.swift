import Foundation
import LayoutCore

public struct LayoutTrustArtifactWriter: Sendable {
    public struct WriteResult: Sendable, Hashable, Codable {
        public let directoryPath: String
        public let canonicalLayoutPath: String
        public let ownershipMapPath: String
        public let netAwareReportPath: String
        public let layoutTrustReportPath: String
        public let layoutArtifactManifestPath: String?

        public init(
            directoryPath: String,
            canonicalLayoutPath: String,
            ownershipMapPath: String,
            netAwareReportPath: String,
            layoutTrustReportPath: String,
            layoutArtifactManifestPath: String? = nil
        ) {
            self.directoryPath = directoryPath
            self.canonicalLayoutPath = canonicalLayoutPath
            self.ownershipMapPath = ownershipMapPath
            self.netAwareReportPath = netAwareReportPath
            self.layoutTrustReportPath = layoutTrustReportPath
            self.layoutArtifactManifestPath = layoutArtifactManifestPath
        }
    }

    public init() {}

    public func write(
        document: LayoutDocument,
        report: LayoutTrustReport,
        to directory: URL
    ) throws -> WriteResult {
        let publisher = ArtifactSetPublisher(runDirectory: directory)
        let payloadItems = [
            try ArtifactSetPublisher.jsonItem(
                document,
                id: "canonical-layout",
                kind: "canonical-layout",
                relativePath: "canonical-layout.json"
            ),
            try ArtifactSetPublisher.jsonItem(
                report.ownershipMap,
                id: "ownership-map",
                kind: "layout-ownership-map",
                relativePath: "ownership-map.json"
            ),
            try ArtifactSetPublisher.jsonItem(
                report.netAwareReport,
                id: "net-aware-report",
                kind: "net-aware-layout-report",
                relativePath: "net-aware-report.json"
            ),
            try ArtifactSetPublisher.jsonItem(
                report,
                id: LayoutTrustReport.artifactKind,
                kind: LayoutTrustReport.artifactKind,
                relativePath: "layout-trust-report.json"
            ),
        ]
        let preparedPayloads = try publisher.prepare(payloadItems)
        let manifest = ArtifactSetManifest(
            runID: runID(from: directory),
            artifactSetKind: "layout-trust",
            records: preparedPayloads.map(\.record).sorted { $0.id < $1.id }
        )
        let manifestItem = try ArtifactSetPublisher.jsonItem(
            manifest,
            id: "layout-artifact-manifest",
            kind: "artifact-set-manifest",
            relativePath: "layout-artifact-manifest.json"
        )
        let preparedManifest = try publisher.prepare([manifestItem])
        let records = try publisher.publish(preparedPayloads + preparedManifest)
        let recordByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })

        let canonicalLayoutURL = try url(for: "canonical-layout", records: recordByID, directory: directory)
        let ownershipMapURL = try url(for: "ownership-map", records: recordByID, directory: directory)
        let netAwareReportURL = try url(for: "net-aware-report", records: recordByID, directory: directory)
        let layoutTrustReportURL = try url(for: LayoutTrustReport.artifactKind, records: recordByID, directory: directory)
        let artifactManifestURL = try url(for: "layout-artifact-manifest", records: recordByID, directory: directory)

        return WriteResult(
            directoryPath: directory.path(percentEncoded: false),
            canonicalLayoutPath: canonicalLayoutURL.path(percentEncoded: false),
            ownershipMapPath: ownershipMapURL.path(percentEncoded: false),
            netAwareReportPath: netAwareReportURL.path(percentEncoded: false),
            layoutTrustReportPath: layoutTrustReportURL.path(percentEncoded: false),
            layoutArtifactManifestPath: artifactManifestURL.path(percentEncoded: false)
        )
    }

    private func runID(from directory: URL) -> String {
        let parent = directory.deletingLastPathComponent()
        guard parent.lastPathComponent != "" else {
            return directory.lastPathComponent
        }
        return parent.lastPathComponent
    }

    private func url(
        for id: String,
        records: [String: ArtifactPublicationRecord],
        directory: URL
    ) throws -> URL {
        guard let record = records[id] else {
            throw ArtifactSetPublisherError.missingPublishedRecord(id)
        }
        return directory.appending(path: record.path)
    }
}
