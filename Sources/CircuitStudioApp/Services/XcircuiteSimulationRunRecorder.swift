import Foundation
import CircuitStudioCore
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSimulationRunRecorder: SimulationRunRecording {
    private let store: XcircuiteWorkspaceStore
    private let actor: XcircuiteRunActionActor
    private let runID: @Sendable () -> String

    public init(
        store: XcircuiteWorkspaceStore = XcircuiteWorkspaceStore(),
        actor: XcircuiteRunActionActor,
        runID: @escaping @Sendable () -> String = {
            "simulation-\(UUID().uuidString.lowercased())"
        }
    ) {
        self.store = store
        self.actor = actor
        self.runID = runID
    }

    public func begin(
        projectRoot: URL,
        intent: String,
        source: String?,
        fileName: String?,
        startedAt: Date
    ) throws -> SimulationRunContext {
        try store.createWorkspace(at: projectRoot)
        let identifier = runID()
        _ = try store.createRunDirectory(
            for: identifier,
            descriptor: XcircuiteRunDescriptor(
                actor: actor,
                intent: intent,
                createdAt: startedAt
            ),
            inProjectAt: projectRoot
        )
        let context = SimulationRunContext(
            runID: identifier,
            projectRoot: projectRoot,
            startedAt: startedAt
        )

        var setupArtifacts: [ArtifactReference] = []
        do {
            setupArtifacts.append(try writeRequest(
                intent: intent,
                fileName: fileName,
                startedAt: startedAt,
                context: context
            ))
            if let source {
                setupArtifacts.append(try writeInputNetlist(
                    source,
                    context: context
                ))
            }
            _ = try store.transitionRun(
                runID: identifier,
                transition: XcircuiteRunTransition(
                    status: .running,
                    artifacts: try legacyReferences(setupArtifacts),
                    occurredAt: startedAt
                ),
                inProjectAt: projectRoot
            )
            return context
        } catch {
            do {
                _ = try store.transitionRun(
                    runID: identifier,
                    transition: XcircuiteRunTransition(
                        status: .running,
                        artifacts: try legacyReferences(setupArtifacts),
                        occurredAt: startedAt
                    ),
                    inProjectAt: projectRoot
                )
                try fail(
                    context: context,
                    reason: "Simulation run setup failed: \(error.localizedDescription)"
                )
            } catch let lifecycleError {
                throw XcircuiteWorkspaceError.writeFailed(
                    "Simulation run setup failed with '\(error.localizedDescription)' and lifecycle finalization failed: \(lifecycleError.localizedDescription)"
                )
            }
            throw error
        }
    }

    public func complete(
        context: SimulationRunContext,
        source: String?,
        records: [AnalysisRunRecord]
    ) async throws {
        do {
            var references: [ArtifactReference] = []
            let existing = try store.loadRunManifest(
                runID: context.runID,
                inProjectAt: context.projectRoot
            )
            if let source,
               !existing.artifacts.contains(where: { $0.artifactID == "simulation-input-netlist" }) {
                references.append(try writeInputNetlist(
                    source,
                    context: context
                ))
            }

            let waveformPaths = try await writeWaveforms(records: records, context: context)
            references.append(contentsOf: waveformPaths.map(\.reference))
            let summary = SimulationSummary(
                runID: context.runID,
                startedAt: context.startedAt,
                records: records.enumerated().map { index, record in
                    SimulationRecordSummary(
                        record: record,
                        waveformPath: waveformPaths.first { $0.index == index }?.reference.path
                    )
                }
            )
            let summaryURL = try runDirectory(for: context).appending(path: "simulation-summary.json")
            try store.writeJSON(summary, to: summaryURL, forProjectAt: context.projectRoot)
            references.append(try store.makeArtifactReference(
                forProjectRelativePath: runRelativePath(
                    "simulation-summary.json",
                    context: context
                ),
                artifactID: "simulation-summary",
                role: .output,
                kind: .report,
                format: .json,
                inProjectAt: context.projectRoot,
                producedByRunID: context.runID,
                verifiedByRunID: nil
            ))

            _ = try store.transitionRun(
                runID: context.runID,
                transition: XcircuiteRunTransition(
                    status: canonicalStatus(records),
                    artifacts: try legacyReferences(references)
                ),
                inProjectAt: context.projectRoot
            )
        } catch {
            do {
                try fail(context: context, reason: error.localizedDescription)
            } catch let lifecycleError {
                throw XcircuiteWorkspaceError.writeFailed(
                    "Simulation evidence persistence failed with '\(error.localizedDescription)' and lifecycle finalization failed: \(lifecycleError.localizedDescription)"
                )
            }
            throw error
        }
    }

    public func fail(
        context: SimulationRunContext,
        reason: String
    ) throws {
        let errorURL = try runDirectory(for: context).appending(path: "simulation-error.json")
        let payload = SimulationFailure(reason: reason, recordedAt: Date())
        try store.writeJSON(payload, to: errorURL, forProjectAt: context.projectRoot)
        let reference = try store.makeArtifactReference(
            forProjectRelativePath: runRelativePath("simulation-error.json", context: context),
            artifactID: "simulation-error",
            role: .output,
            kind: .report,
            format: .json,
            inProjectAt: context.projectRoot,
            producedByRunID: context.runID,
            verifiedByRunID: nil
        )
        _ = try store.transitionRun(
            runID: context.runID,
            transition: XcircuiteRunTransition(
                status: .failed,
                artifacts: try legacyReferences([reference])
            ),
            inProjectAt: context.projectRoot
        )
    }

    private func writeInputNetlist(
        _ source: String,
        context: SimulationRunContext
    ) throws -> ArtifactReference {
        let inputURL = try runDirectory(for: context).appending(path: "input.cir")
        try store.writeText(source, to: inputURL)
        return try store.makeArtifactReference(
            forProjectRelativePath: runRelativePath("input.cir", context: context),
            artifactID: "simulation-input-netlist",
            role: .input,
            kind: .netlist,
            format: .spice,
            inProjectAt: context.projectRoot,
            producedByRunID: context.runID,
            verifiedByRunID: nil
        )
    }

    private func writeRequest(
        intent: String,
        fileName: String?,
        startedAt: Date,
        context: SimulationRunContext
    ) throws -> ArtifactReference {
        let requestURL = try runDirectory(for: context).appending(path: "simulation-request.json")
        let request = SimulationRequest(
            intent: intent,
            sourceFileName: fileName,
            startedAt: startedAt
        )
        try store.writeJSON(request, to: requestURL, forProjectAt: context.projectRoot)
        return try store.makeArtifactReference(
            forProjectRelativePath: runRelativePath("simulation-request.json", context: context),
            artifactID: "simulation-request",
            role: .input,
            kind: .report,
            format: .json,
            inProjectAt: context.projectRoot,
            producedByRunID: context.runID,
            verifiedByRunID: nil
        )
    }

    private func writeWaveforms(
        records: [AnalysisRunRecord],
        context: SimulationRunContext
    ) async throws -> [(index: Int, reference: ArtifactReference)] {
        let waveformsDirectory = try runDirectory(for: context).appending(path: "waveforms")
        try store.ensureDirectory(at: waveformsDirectory)
        var references: [(index: Int, reference: ArtifactReference)] = []
        for (index, record) in records.enumerated() {
            guard let waveform = record.result?.waveform else {
                continue
            }
            let name = waveformFileName(index: index, record: record)
            let waveformURL = waveformsDirectory.appending(path: name)
            try await WaveformService().export(waveform: waveform, to: waveformURL)
            let reference = try store.makeArtifactReference(
                forProjectRelativePath: runRelativePath("waveforms/\(name)", context: context),
                artifactID: "simulation-waveform-\(index)",
                role: .output,
                kind: .waveform,
                format: .csv,
                inProjectAt: context.projectRoot,
                producedByRunID: context.runID,
                verifiedByRunID: nil
            )
            references.append((index, reference))
        }
        return references
    }

    private func canonicalStatus(_ records: [AnalysisRunRecord]) -> XcircuiteRunStatus {
        if records.isEmpty || records.contains(where: { $0.status == .failed }) {
            return .failed
        }
        if records.contains(where: { $0.status == .cancelled }) {
            return .cancelled
        }
        if records.allSatisfy({ $0.status == .completed }) {
            return .succeeded
        }
        return .partial
    }

    private func waveformFileName(index: Int, record: AnalysisRunRecord) -> String {
        let corner = record.cornerName.map(sanitizedFileComponent) ?? "base"
        return String(format: "%03d-%@-%@.csv", index, record.analysis.mnemonic, corner)
    }

    private func sanitizedFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        return String(scalars)
    }

    private func runRelativePath(_ suffix: String, context: SimulationRunContext) -> String {
        "\(XcircuiteWorkspace.directoryName)/runs/\(context.runID)/\(suffix)"
    }

    private func runDirectory(for context: SimulationRunContext) throws -> URL {
        try XcircuiteWorkspace(projectRoot: context.projectRoot)
            .runDirectoryURL(for: context.runID)
    }

    private func legacyReferences(
        _ references: [ArtifactReference]
    ) throws -> [XcircuiteFileReference] {
        try references.map(FoundationArtifactTypeProjection.legacyReference)
    }

    private struct SimulationSummary: Sendable, Encodable {
        let schemaVersion: Int = 1
        let runID: String
        let startedAt: Date
        let records: [SimulationRecordSummary]
    }

    private struct SimulationRequest: Sendable, Encodable {
        let schemaVersion: Int = 1
        let intent: String
        let sourceFileName: String?
        let startedAt: Date
    }

    private struct SimulationRecordSummary: Sendable, Encodable {
        let recordID: UUID
        let analysis: String
        let cornerName: String?
        let temperature: Double?
        let status: RunStatus
        let failureReason: String?
        let startedAt: Date
        let finishedAt: Date?
        let simulationResultID: UUID?
        let waveformPath: String?

        init(record: AnalysisRunRecord, waveformPath: String?) {
            recordID = record.id
            analysis = record.analysis.mnemonic
            cornerName = record.cornerName
            temperature = record.temperature
            status = record.status
            failureReason = record.failureReason
            startedAt = record.startedAt
            finishedAt = record.finishedAt
            simulationResultID = record.result?.id
            self.waveformPath = waveformPath
        }
    }

    private struct SimulationFailure: Sendable, Encodable {
        let reason: String
        let recordedAt: Date
    }
}
