import Foundation
import CircuiteFoundation
import DesignFlowKernel

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
        case artifactByteCountMismatch(id: String, claimed: Int64, actual: Int64)
        case artifactNotRegularFile(id: String, path: String)
        case duplicateArtifactID(String)
        case artifactDestinationExists(String)

        public var errorDescription: String? {
            switch self {
            case .artifactFileMissing(let id, let path):
                return "Claim artifact '\(id)' is declared available but '\(path)' does not exist."
            case .artifactDigestMismatch(let id, let claimed, let actual):
                return "Claim artifact '\(id)' digest mismatch: claimed \(claimed), actual \(actual)."
            case .artifactByteCountMismatch(let id, let claimed, let actual):
                return "Claim artifact '\(id)' byte count mismatch: claimed \(claimed), actual \(actual)."
            case .artifactNotRegularFile(let id, let path):
                return "Claim artifact '\(id)' must resolve to a regular file: \(path)"
            case .duplicateArtifactID(let id):
                return "Claim artifact ID '\(id)' is duplicated in the evidence bundle."
            case .artifactDestinationExists(let path):
                return "Evidence capture destination already exists: \(path)"
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
        let runDirectory = try store.createRunDirectory(
            for: runID,
            descriptor: XcircuiteRunDescriptor(
                actor: XcircuiteRunActionActor(
                    kind: .system,
                    identifier: "tapeout-evidence-recorder"
                ),
                intent: "Record and verify tapeout evidence."
            ),
            inProjectAt: projectRoot
        )
        _ = try store.transitionRun(
            runID: runID,
            transition: XcircuiteRunTransition(status: .running),
            inProjectAt: projectRoot
        )
        do {
            return try recordRunningBundle(
                bundle,
                projectRoot: projectRoot,
                runID: runID,
                runDirectory: runDirectory
            )
        } catch {
            do {
                let failureReference = try recordFailure(
                    error,
                    projectRoot: projectRoot,
                    runID: runID,
                    runDirectory: runDirectory
                )
                _ = try store.transitionRun(
                    runID: runID,
                    transition: XcircuiteRunTransition(
                        status: .failed,
                        artifacts: try legacyReferences([failureReference])
                    ),
                    inProjectAt: projectRoot
                )
            } catch let lifecycleError {
                throw XcircuitePackageError.writeFailed(
                    "Evidence recording failed with '\(error.localizedDescription)' and the canonical run could not be marked failed: \(lifecycleError.localizedDescription)"
                )
            }
            throw error
        }
    }

    private func recordRunningBundle(
        _ bundle: TapeoutEvidenceBundle,
        projectRoot: URL,
        runID: String,
        runDirectory: URL
    ) throws -> RecordedRun {
        var artifacts: [ArtifactReference] = []
        var artifactIDs: Set<String> = []

        // The bundle itself is the run's primary report.
        try reserveArtifactID("tapeout-evidence", in: &artifactIDs)
        try reserveArtifactID("evidence-error", in: &artifactIDs)
        let evidenceURL = runDirectory.appending(path: "evidence.json")
        try store.writeJSON(bundle, to: evidenceURL, forProjectAt: projectRoot)
        try recordArtifact(try artifactReference(
            for: evidenceURL,
            artifactID: "tapeout-evidence",
            projectRoot: projectRoot,
            kind: .report,
            format: .json,
            runID: runID
        ), artifacts: &artifacts, projectRoot: projectRoot, runID: runID)

        // Claim artifacts, copied into the immutable capture.
        let artifactsDirectory = runDirectory.appending(path: "artifacts")
        for claim in bundle.claims {
            guard let artifact = claim.artifact, artifact.status == .available else { continue }
            try reserveArtifactID(artifact.id, in: &artifactIDs)
            let copied = try copyArtifact(
                artifact,
                into: artifactsDirectory,
                projectRoot: projectRoot,
                runID: runID
            )
            try recordArtifact(try artifactReference(
                for: copied,
                artifactID: artifact.id,
                projectRoot: projectRoot,
                kind: fileKind(forClaimArtifactKind: artifact.kind),
                format: fileFormat(forFileAt: copied),
                runID: runID
            ), artifacts: &artifacts, projectRoot: projectRoot, runID: runID)
        }

        if let gdsPath = bundle.gdsPath, !gdsPath.isEmpty {
            try reserveArtifactID("gds", in: &artifactIDs)
            let gds = TapeoutEvidenceArtifact(
                id: "gds",
                kind: "layout",
                path: gdsPath,
                status: .available
            )
            let copied = try copyArtifact(
                gds,
                into: artifactsDirectory,
                projectRoot: projectRoot,
                runID: runID
            )
            try recordArtifact(try artifactReference(
                for: copied,
                artifactID: gds.id,
                projectRoot: projectRoot,
                kind: .layout,
                format: .gdsii,
                runID: runID
            ), artifacts: &artifacts, projectRoot: projectRoot, runID: runID)
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

        let manifest = try store.transitionRun(
            runID: runID,
            transition: XcircuiteRunTransition(
                status: status,
                artifacts: try legacyReferences(artifacts)
            ),
            inProjectAt: projectRoot
        )

        return RecordedRun(runID: runID, runDirectory: runDirectory, manifest: manifest)
    }

    // MARK: - Internals

    private func recordArtifact(
        _ reference: ArtifactReference,
        artifacts: inout [ArtifactReference],
        projectRoot: URL,
        runID: String
    ) throws {
        artifacts.append(reference)
        try store.registerArtifact(reference, runID: runID, inProjectAt: projectRoot)
    }

    private func copyArtifact(
        _ artifact: TapeoutEvidenceArtifact,
        into directory: URL,
        projectRoot: URL,
        runID: String
    ) throws -> URL {
        try XcircuiteIdentifierValidator().validate(artifact.id, kind: .artifactID)
        let source = URL(filePath: artifact.path)
        guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw RecorderError.artifactFileMissing(id: artifact.id, path: artifact.path)
        }
        let resolvedSource = source.resolvingSymlinksInPath()
        let sourceValues = try resolvedSource.resourceValues(forKeys: [.isRegularFileKey])
        guard sourceValues.isRegularFile == true else {
            throw RecorderError.artifactNotRegularFile(id: artifact.id, path: artifact.path)
        }
        try store.ensureDirectory(at: directory)
        let relativeDestination = "\(XcircuitePackage.directoryName)/runs/\(runID)/artifacts/\(artifact.id)-\(source.lastPathComponent)"
        let destination = try XcircuitePackage(projectRoot: projectRoot)
            .url(forProjectRelativePath: relativeDestination)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            throw RecorderError.artifactDestinationExists(
                destination.path(percentEncoded: false)
            )
        }
        try FileManager.default.copyItem(at: resolvedSource, to: destination)

        let digest = try hasher.sha256(fileAt: destination)
        if let claimed = artifact.sha256, claimed != digest {
            throw RecorderError.artifactDigestMismatch(
                id: artifact.id,
                claimed: claimed,
                actual: digest
            )
        }
        let byteCount = try hasher.byteCount(fileAt: destination)
        if let claimed = artifact.byteCount, claimed != byteCount {
            throw RecorderError.artifactByteCountMismatch(
                id: artifact.id,
                claimed: claimed,
                actual: byteCount
            )
        }
        return destination
    }

    private func artifactReference(
        for url: URL,
        artifactID: String,
        projectRoot: URL,
        kind: ArtifactKind,
        format: ArtifactFormat,
        runID: String
    ) throws -> ArtifactReference {
        let rootPath = projectRoot.standardizedFileURL.path(percentEncoded: false)
        let filePath = url.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else {
            throw XcircuitePackageError.unsafeProjectPath(
                "artifact '\(filePath)' is outside the project root '\(rootPath)'"
            )
        }
        return try store.makeArtifactReference(
            forProjectRelativePath: String(filePath.dropFirst(prefix.count)),
            artifactID: artifactID,
            role: .output,
            kind: kind,
            format: format,
            inProjectAt: projectRoot,
            producedByRunID: runID,
            verifiedByRunID: nil
        )
    }

    private func reserveArtifactID(
        _ artifactID: String,
        in artifactIDs: inout Set<String>
    ) throws {
        try XcircuiteIdentifierValidator().validate(artifactID, kind: .artifactID)
        guard artifactIDs.insert(artifactID).inserted else {
            throw RecorderError.duplicateArtifactID(artifactID)
        }
    }

    private func recordFailure(
        _ error: Error,
        projectRoot: URL,
        runID: String,
        runDirectory: URL
    ) throws -> ArtifactReference {
        let failureURL = runDirectory.appending(path: "evidence-error.json")
        try store.writeJSON(
            EvidenceFailure(
                reason: error.localizedDescription,
                errorType: String(describing: type(of: error)),
                recordedAt: Date()
            ),
            to: failureURL,
            forProjectAt: projectRoot
        )
        return try artifactReference(
            for: failureURL,
            artifactID: "evidence-error",
            projectRoot: projectRoot,
            kind: .report,
            format: .json,
            runID: runID
        )
    }

    private struct EvidenceFailure: Sendable, Encodable {
        let schemaVersion = 1
        let reason: String
        let errorType: String
        let recordedAt: Date
    }

    private func fileKind(forClaimArtifactKind kind: String) -> ArtifactKind {
        switch kind.lowercased() {
        case "layout", "gds", "gdsii": return .layout
        case "netlist", "spice": return .netlist
        case "parasitic", "spef": return .parasitics
        case "waveform": return .waveform
        case "measurement": return .measurement
        case "ruledeck", "rule-deck": return .ruleDeck
        case "technology": return .technology
        case "model": return .model
        case "report", "log": return .report
        default: return .other
        }
    }

    private func fileFormat(forFileAt url: URL) -> ArtifactFormat {
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

    private func legacyReferences(
        _ references: [ArtifactReference]
    ) throws -> [XcircuiteFileReference] {
        try references.map(FoundationArtifactTypeProjection.legacyReference)
    }
}
