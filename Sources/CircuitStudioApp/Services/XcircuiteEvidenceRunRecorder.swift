import Foundation
import CircuiteFoundation
import DesignFlowKernel
import Xcircuite

/// Records tapeout evidence in the canonical `.xcircuite` run ledger so
/// the human cockpit and agent loop review the same immutable artifacts.
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
        public let manifest: FlowRunManifest
    }

    private let digester: any ContentDigesting
    private let workspaceStoreFactory: @Sendable (URL) throws -> XcircuiteWorkspaceStore

    public init(
        workspaceStoreFactory: @escaping @Sendable (URL) throws -> XcircuiteWorkspaceStore = {
            try XcircuiteWorkspaceStore(projectRoot: $0)
        }
    ) {
        self.digester = SHA256ContentDigester()
        self.workspaceStoreFactory = workspaceStoreFactory
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
    ) async throws -> RecordedRun {
        let store = try workspaceStoreFactory(projectRoot)
        try await store.createWorkspace()
        let runDirectory = try await store.url(
            for: "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)"
        )
        let createdAt = Date()
        let manifest = try FlowRunManifest(
            runID: runID,
            status: .created,
            actor: FlowRunActor(
                kind: .system,
                identifier: "tapeout-evidence-recorder"
            ),
            intent: "Record and verify tapeout evidence.",
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let coordinator = FlowRunLedgerCoordinator(persistence: store)
        try await coordinator.save(FlowRunLedger(
            runID: runID,
            runManifest: manifest,
            stages: []
        ))
        _ = try await coordinator.transition(runID: runID, to: .running, at: createdAt)
        do {
            return try await recordRunningBundle(
                bundle,
                store: store,
                projectRoot: projectRoot,
                runID: runID,
                runDirectory: runDirectory
            )
        } catch {
            do {
                let failureReference = try await recordFailure(
                    error,
                    store: store,
                    projectRoot: projectRoot,
                    runID: runID,
                    runDirectory: runDirectory
                )
                _ = try await coordinator.transition(
                    runID: runID,
                    to: .failed,
                    registering: [failureReference]
                )
            } catch let lifecycleError {
                throw XcircuiteWorkspaceStoreError.writeFailed(
                    "Evidence recording failed with '\(error.localizedDescription)' and the canonical run could not be marked failed: \(lifecycleError.localizedDescription)"
                )
            }
            throw error
        }
    }

    private func recordRunningBundle(
        _ bundle: TapeoutEvidenceBundle,
        store: XcircuiteWorkspaceStore,
        projectRoot: URL,
        runID: String,
        runDirectory: URL
    ) async throws -> RecordedRun {
        var artifacts: [ArtifactReference] = []
        var artifactIDs: Set<String> = []

        // The bundle itself is the run's primary report.
        try reserveArtifactID("tapeout-evidence", in: &artifactIDs)
        try reserveArtifactID("evidence-error", in: &artifactIDs)
        let evidenceURL = runDirectory.appending(path: "evidence.json")
        let evidencePath = "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/evidence.json"
        try await store.writeJSON(bundle, to: evidencePath)
        try await recordArtifact(try await artifactReference(
            for: evidenceURL,
            artifactID: "tapeout-evidence",
            store: store,
            projectRoot: projectRoot,
            kind: .report,
            format: .json
        ), artifacts: &artifacts, store: store, runID: runID)

        // Claim artifacts, copied into the immutable capture.
        for claim in bundle.claims {
            guard let artifact = claim.artifact, artifact.status == .available else { continue }
            try reserveArtifactID(artifact.id, in: &artifactIDs)
            let copied = try await copyArtifact(
                artifact,
                store: store,
                runID: runID
            )
            try await recordArtifact(try await artifactReference(
                for: copied,
                artifactID: artifact.id,
                store: store,
                projectRoot: projectRoot,
                kind: fileKind(forClaimArtifactKind: artifact.kind),
                format: fileFormat(forFileAt: copied)
            ), artifacts: &artifacts, store: store, runID: runID)
        }

        if let gdsPath = bundle.gdsPath, !gdsPath.isEmpty {
            try reserveArtifactID("gds", in: &artifactIDs)
            let gdsURL = URL(filePath: gdsPath)
            let gdsLocator = ArtifactLocator(
                location: try ArtifactLocation(fileURL: gdsURL),
                role: .input,
                kind: .layout,
                format: .gdsii
            )
            let gdsReference = try LocalArtifactReferencer().reference(gdsLocator)
            let gds = TapeoutEvidenceArtifact(
                publicationRecord: ArtifactPublicationRecord(
                    reference: ArtifactReference(
                        id: try ArtifactID(rawValue: "gds"),
                        locator: gdsReference.locator,
                        digest: gdsReference.digest,
                        byteCount: gdsReference.byteCount,
                        producer: gdsReference.producer
                    )
                )
            )
            let copied = try await copyArtifact(
                gds,
                store: store,
                runID: runID
            )
            try await recordArtifact(try await artifactReference(
                for: copied,
                artifactID: gds.id,
                store: store,
                projectRoot: projectRoot,
                kind: .layout,
                format: .gdsii
            ), artifacts: &artifacts, store: store, runID: runID)
        }

        let status: FlowRunStatus
        do {
            // Artifact presence is re-verified against the run's own
            // copies above; here the verdict is about the CLAIMS.
            try bundle.verify(requireArtifacts: false)
            status = .succeeded
        } catch {
            status = .failed
        }

        let ledger = try await FlowRunLedgerCoordinator(persistence: store).transition(
            runID: runID,
            to: status,
            registering: artifacts
        )

        return RecordedRun(
            runID: runID,
            runDirectory: runDirectory,
            manifest: ledger.runManifest
        )
    }

    // MARK: - Internals

    private func recordArtifact(
        _ reference: ArtifactReference,
        artifacts: inout [ArtifactReference],
        store: XcircuiteWorkspaceStore,
        runID: String
    ) async throws {
        artifacts.append(reference)
        _ = try await FlowRunLedgerCoordinator(persistence: store).register(
            runID: runID,
            artifacts: [reference]
        )
    }

    private func copyArtifact(
        _ artifact: TapeoutEvidenceArtifact,
        store: XcircuiteWorkspaceStore,
        runID: String
    ) async throws -> URL {
        try FlowIdentifierValidator().validate(artifact.id, kind: .artifactID)
        let source = URL(filePath: artifact.path)
        guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw RecorderError.artifactFileMissing(id: artifact.id, path: artifact.path)
        }
        let resolvedSource = source.resolvingSymlinksInPath()
        let sourceValues = try resolvedSource.resourceValues(forKeys: [.isRegularFileKey])
        guard sourceValues.isRegularFile == true else {
            throw RecorderError.artifactNotRegularFile(id: artifact.id, path: artifact.path)
        }
        let relativeDestination = "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/artifacts/\(artifact.id)-\(source.lastPathComponent)"
        let destination = try await store.url(for: relativeDestination)
        let artifactsPath = "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/artifacts"
        try await store.ensureWorkspaceDirectory(at: artifactsPath)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            throw RecorderError.artifactDestinationExists(
                destination.path(percentEncoded: false)
            )
        }
        try FileManager.default.copyItem(at: resolvedSource, to: destination)

        let digest = try digester.digest(fileAt: destination, using: .sha256).hexadecimalValue
        if let claimed = artifact.sha256, claimed != digest {
            throw RecorderError.artifactDigestMismatch(
                id: artifact.id,
                claimed: claimed,
                actual: digest
            )
        }
        let byteCount = try fileByteCount(at: destination)
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
        store: XcircuiteWorkspaceStore,
        projectRoot: URL,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) async throws -> ArtifactReference {
        let rootPath = projectRoot.standardizedFileURL.path(percentEncoded: false)
        let filePath = url.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else {
            throw XcircuiteWorkspaceStoreError.unsafeProjectPath(
                "artifact '\(filePath)' is outside the project root '\(rootPath)'"
            )
        }
        return try await store.makeArtifactReference(
            forProjectRelativePath: String(filePath.dropFirst(prefix.count)),
            artifactID: artifactID,
            role: .output,
            kind: kind,
            format: format
        )
    }

    private func reserveArtifactID(
        _ artifactID: String,
        in artifactIDs: inout Set<String>
    ) throws {
        try FlowIdentifierValidator().validate(artifactID, kind: .artifactID)
        guard artifactIDs.insert(artifactID).inserted else {
            throw RecorderError.duplicateArtifactID(artifactID)
        }
    }

    private func recordFailure(
        _ error: Error,
        store: XcircuiteWorkspaceStore,
        projectRoot: URL,
        runID: String,
        runDirectory: URL
    ) async throws -> ArtifactReference {
        let failureURL = runDirectory.appending(path: "evidence-error.json")
        let failurePath = "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/evidence-error.json"
        try await store.writeJSON(
            EvidenceFailure(
                reason: error.localizedDescription,
                errorType: String(describing: type(of: error)),
                recordedAt: Date()
            ),
            to: failurePath
        )
        return try await artifactReference(
            for: failureURL,
            artifactID: "evidence-error",
            store: store,
            projectRoot: projectRoot,
            kind: .report,
            format: .json
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

    private func fileByteCount(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size >= 0 else {
            throw RecorderError.artifactNotRegularFile(
                id: url.lastPathComponent,
                path: url.path(percentEncoded: false)
            )
        }
        return Int64(size)
    }
}
