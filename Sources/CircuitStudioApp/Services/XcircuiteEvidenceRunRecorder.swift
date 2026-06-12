import Foundation
import XcircuitePackage

/// Bridges the tapeout evidence bundle into the canonical `.xcircuite`
/// run ledger, so the human cockpit and the agent loop review ONE
/// record instead of per-flow ad-hoc files.
///
/// Claim artifacts are COPIED into the run directory — a run is an
/// immutable capture, and evidence files frequently live in temporary
/// build directories that outlive nothing. Every copy's sha256 is
/// recomputed; when the claim already states a digest the two must
/// match — a divergence is an integrity error, never a silent record.
public struct XcircuiteEvidenceRunRecorder: Sendable {

    public enum RecorderError: Error, LocalizedError, Equatable {
        case artifactFileMissing(id: String, path: String)
        case artifactDigestMismatch(id: String, claimed: String, actual: String)

        public var errorDescription: String? {
            switch self {
            case .artifactFileMissing(let id, let path):
                return "Claim artifact '\(id)' is declared available but '\(path)' does not exist."
            case .artifactDigestMismatch(let id, let claimed, let actual):
                return "Claim artifact '\(id)' digest mismatch: claimed \(claimed), actual \(actual)."
            }
        }
    }

    public struct RecordedRun: Sendable {
        public let runID: String
        public let runDirectory: URL
        public let manifest: XcircuiteRunManifest
    }

    private let store: XcircuitePackageStore
    private let hasher: XcircuiteHasher

    public init(store: XcircuitePackageStore = XcircuitePackageStore()) {
        self.store = store
        self.hasher = XcircuiteHasher()
    }

    /// Records `bundle` as run `runID` of the project at `projectRoot`:
    /// the bundle itself, every available claim artifact (copied in,
    /// digest-verified), and the GDS, all indexed as file references in
    /// the run manifest. The run status states the bundle's own verify
    /// verdict — a failing bundle is still recorded, as failed.
    @discardableResult
    public func record(
        _ bundle: TapeoutEvidenceBundle,
        projectRoot: URL,
        runID: String
    ) throws -> RecordedRun {
        try store.createPackage(at: projectRoot)
        let runDirectory = try store.createRunDirectory(for: runID, inProjectAt: projectRoot)
        var artifacts: [XcircuiteFileReference] = []

        // The bundle itself is the run's primary report.
        let evidenceURL = runDirectory.appending(path: "evidence.json")
        try store.writeJSON(bundle, to: evidenceURL, forProjectAt: projectRoot)
        artifacts.append(try fileReference(
            for: evidenceURL,
            projectRoot: projectRoot,
            kind: .report,
            format: .json,
            runID: runID
        ))

        // Claim artifacts, copied into the immutable capture.
        let artifactsDirectory = runDirectory.appending(path: "artifacts")
        for claim in bundle.claims {
            guard let artifact = claim.artifact, artifact.status == .available else { continue }
            let copied = try copyArtifact(artifact, into: artifactsDirectory)
            artifacts.append(try fileReference(
                for: copied,
                projectRoot: projectRoot,
                kind: fileKind(forClaimArtifactKind: artifact.kind),
                format: fileFormat(forFileAt: copied),
                runID: runID
            ))
        }

        if let gdsPath = bundle.gdsPath, !gdsPath.isEmpty {
            let gds = TapeoutEvidenceArtifact(
                id: "gds",
                kind: "layout",
                path: gdsPath,
                status: .available
            )
            let copied = try copyArtifact(gds, into: artifactsDirectory)
            artifacts.append(try fileReference(
                for: copied,
                projectRoot: projectRoot,
                kind: .layout,
                format: .gdsii,
                runID: runID
            ))
        }

        let status: XcircuiteRunStatus
        do {
            // Artifact presence is re-verified against the run's own
            // copies above; here the verdict is about the CLAIMS.
            try bundle.verify(requireArtifacts: false)
            status = .succeeded
        } catch {
            status = .failed
        }

        let manifest = XcircuiteRunManifest(runID: runID, status: status, artifacts: artifacts)
        try store.writeJSON(
            manifest,
            to: runDirectory.appending(path: "manifest.json"),
            forProjectAt: projectRoot
        )

        var project = try store.loadManifest(forProjectAt: projectRoot)
        if let index = project.runs.firstIndex(where: { $0.runID == runID }) {
            project.runs[index].status = status
        }
        try store.saveManifest(project, forProjectAt: projectRoot)

        return RecordedRun(runID: runID, runDirectory: runDirectory, manifest: manifest)
    }

    // MARK: - Internals

    private func copyArtifact(
        _ artifact: TapeoutEvidenceArtifact,
        into directory: URL
    ) throws -> URL {
        let source = URL(filePath: artifact.path)
        guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw RecorderError.artifactFileMissing(id: artifact.id, path: artifact.path)
        }
        try store.ensureDirectory(at: directory)
        let destination = directory.appending(path: "\(artifact.id)-\(source.lastPathComponent)")
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)

        let digest = try hasher.sha256(fileAt: destination)
        if let claimed = artifact.sha256, claimed != digest {
            throw RecorderError.artifactDigestMismatch(
                id: artifact.id,
                claimed: claimed,
                actual: digest
            )
        }
        return destination
    }

    private func fileReference(
        for url: URL,
        projectRoot: URL,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        runID: String
    ) throws -> XcircuiteFileReference {
        let rootPath = projectRoot.standardizedFileURL.path(percentEncoded: false)
        let filePath = url.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else {
            throw XcircuitePackageError.unsafeProjectPath(
                "artifact '\(filePath)' is outside the project root '\(rootPath)'"
            )
        }
        return XcircuiteFileReference(
            path: String(filePath.dropFirst(prefix.count)),
            kind: kind,
            format: format,
            sha256: try hasher.sha256(fileAt: url),
            producedByRunID: runID
        )
    }

    private func fileKind(forClaimArtifactKind kind: String) -> XcircuiteFileKind {
        switch kind.lowercased() {
        case "layout", "gds", "gdsii": return .layout
        case "netlist", "spice": return .netlist
        case "parasitic", "spef": return .parasitic
        case "waveform": return .waveform
        case "measurement": return .measurement
        case "ruledeck", "rule-deck": return .ruleDeck
        case "technology": return .technology
        case "model": return .model
        case "report", "log": return .report
        default: return .other
        }
    }

    private func fileFormat(forFileAt url: URL) -> XcircuiteFileFormat {
        switch url.pathExtension.lowercased() {
        case "gds", "gds2", "gdsii": return .gdsii
        case "oas", "oasis": return .oasis
        case "spice", "sp", "cir", "spi": return .spice
        case "spef": return .spef
        case "json": return .json
        case "lef": return .lef
        case "def": return .def
        case "csv": return .csv
        case "raw": return .raw
        case "txt", "log", "md", "rpt": return .text
        default: return .unknown
        }
    }
}
