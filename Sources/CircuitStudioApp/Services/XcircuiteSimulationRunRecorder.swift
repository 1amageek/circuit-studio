import Foundation
import CircuitStudioCore
import CircuiteFoundation
import DesignFlowKernel
import Xcircuite

public struct XcircuiteSimulationRunRecorder: SimulationRunRecording {
    private let actor: FlowRunActor
    private let runID: @Sendable () -> String
    private let workspaceStoreFactory: @Sendable (URL) throws -> XcircuiteWorkspaceStore

    public init(
        actor: FlowRunActor,
        runID: @escaping @Sendable () -> String = {
            "simulation-\(UUID().uuidString.lowercased())"
        },
        workspaceStoreFactory: @escaping @Sendable (URL) throws -> XcircuiteWorkspaceStore = {
            try XcircuiteWorkspaceStore(projectRoot: $0)
        }
    ) {
        self.actor = actor
        self.runID = runID
        self.workspaceStoreFactory = workspaceStoreFactory
    }

    public func begin(
        projectRoot: URL,
        intent: String,
        source: String?,
        fileName: String?,
        startedAt: Date
    ) async throws -> SimulationRunContext {
        let store = try workspaceStoreFactory(projectRoot)
        try await store.createWorkspace()
        let identifier = runID()
        let manifest = try FlowRunManifest(
            runID: identifier,
            status: .created,
            actor: actor,
            intent: intent,
            createdAt: startedAt,
            updatedAt: startedAt
        )
        let coordinator = FlowRunLedgerCoordinator(persistence: store)
        try await coordinator.save(FlowRunLedger(
            runID: identifier,
            runManifest: manifest,
            stages: []
        ))
        let context = SimulationRunContext(
            runID: identifier,
            projectRoot: projectRoot,
            startedAt: startedAt
        )

        var setupArtifacts: [ArtifactReference] = []
        do {
            setupArtifacts.append(try await writeRequest(
                intent: intent,
                fileName: fileName,
                startedAt: startedAt,
                context: context
            ))
            if let source {
                setupArtifacts.append(try await writeInputNetlist(
                    source,
                    context: context
                ))
            }
            _ = try await coordinator.transition(
                runID: identifier,
                to: .running,
                registering: setupArtifacts,
                at: startedAt
            )
            return context
        } catch {
            do {
                _ = try await coordinator.transition(
                    runID: identifier,
                    to: .running,
                    registering: setupArtifacts,
                    at: startedAt
                )
                try await fail(
                    context: context,
                    reason: "Simulation run setup failed: \(error.localizedDescription)"
                )
            } catch let lifecycleError {
                throw XcircuiteWorkspaceStoreError.writeFailed(
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
        let store = try workspaceStoreFactory(context.projectRoot)
        let coordinator = FlowRunLedgerCoordinator(persistence: store)
        do {
            var references: [ArtifactReference] = []
            let existing = try await store.loadRunManifest(runID: context.runID)
            if let source,
               !existing.artifacts.contains(where: { $0.artifactID == "simulation-input-netlist" }) {
                references.append(try await writeInputNetlist(
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
            let summaryPath = runRelativePath("simulation-summary.json", context: context)
            try await store.writeJSON(summary, to: summaryPath)
            references.append(try await store.makeArtifactReference(
                forProjectRelativePath: runRelativePath(
                    "simulation-summary.json",
                    context: context
                ),
                artifactID: "simulation-summary",
                role: .output,
                kind: .report,
                format: .json
            ))

            _ = try await coordinator.transition(
                runID: context.runID,
                to: canonicalStatus(records),
                registering: references
            )
        } catch {
            do {
                try await fail(context: context, reason: error.localizedDescription)
            } catch let lifecycleError {
                throw XcircuiteWorkspaceStoreError.writeFailed(
                    "Simulation evidence persistence failed with '\(error.localizedDescription)' and lifecycle finalization failed: \(lifecycleError.localizedDescription)"
                )
            }
            throw error
        }
    }

    public func fail(
        context: SimulationRunContext,
        reason: String
    ) async throws {
        let store = try workspaceStoreFactory(context.projectRoot)
        let coordinator = FlowRunLedgerCoordinator(persistence: store)
        let errorPath = runRelativePath("simulation-error.json", context: context)
        let payload = SimulationFailure(reason: reason, recordedAt: Date())
        try await store.writeJSON(payload, to: errorPath)
        let reference = try await store.makeArtifactReference(
            forProjectRelativePath: runRelativePath("simulation-error.json", context: context),
            artifactID: "simulation-error",
            role: .output,
            kind: .report,
            format: .json
        )
        _ = try await coordinator.transition(
            runID: context.runID,
            to: .failed,
            registering: [reference]
        )
    }

    private func writeInputNetlist(
        _ source: String,
        context: SimulationRunContext
    ) async throws -> ArtifactReference {
        let store = try workspaceStoreFactory(context.projectRoot)
        let path = runRelativePath("input.cir", context: context)
        try await store.writeWorkspaceText(source, to: path)
        return try await store.makeArtifactReference(
            forProjectRelativePath: runRelativePath("input.cir", context: context),
            artifactID: "simulation-input-netlist",
            role: .input,
            kind: .netlist,
            format: .spice
        )
    }

    private func writeRequest(
        intent: String,
        fileName: String?,
        startedAt: Date,
        context: SimulationRunContext
    ) async throws -> ArtifactReference {
        let store = try workspaceStoreFactory(context.projectRoot)
        let path = runRelativePath("simulation-request.json", context: context)
        let request = SimulationRequest(
            intent: intent,
            sourceFileName: fileName,
            startedAt: startedAt
        )
        try await store.writeJSON(request, to: path)
        return try await store.makeArtifactReference(
            forProjectRelativePath: runRelativePath("simulation-request.json", context: context),
            artifactID: "simulation-request",
            role: .input,
            kind: .report,
            format: .json
        )
    }

    private func writeWaveforms(
        records: [AnalysisRunRecord],
        context: SimulationRunContext
    ) async throws -> [(index: Int, reference: ArtifactReference)] {
        let store = try workspaceStoreFactory(context.projectRoot)
        let waveformsDirectory = try runDirectory(for: context).appending(path: "waveforms")
        try await store.ensureWorkspaceDirectory(
            at: runRelativePath("waveforms", context: context)
        )
        var references: [(index: Int, reference: ArtifactReference)] = []
        for (index, record) in records.enumerated() {
            guard let waveform = record.result?.waveform else {
                continue
            }
            let name = waveformFileName(index: index, record: record)
            let waveformURL = waveformsDirectory.appending(path: name)
            try await WaveformService().export(waveform: waveform, to: waveformURL)
            let reference = try await store.makeArtifactReference(
                forProjectRelativePath: runRelativePath("waveforms/\(name)", context: context),
                artifactID: "simulation-waveform-\(index)",
                role: .output,
                kind: .waveform,
                format: .csv
            )
            references.append((index, reference))
        }
        return references
    }

    private func canonicalStatus(_ records: [AnalysisRunRecord]) -> FlowRunStatus {
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
        "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(context.runID)/\(suffix)"
    }

    private func runDirectory(for context: SimulationRunContext) throws -> URL {
        try XcircuiteWorkspaceLayout(projectRoot: context.projectRoot)
            .runDirectoryURL(for: context.runID)
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
