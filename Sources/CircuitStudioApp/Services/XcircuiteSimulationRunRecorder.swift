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
        try await coordinator.create(FlowRunLedger(
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
        var references: [ArtifactReference] = []
        try await requireRunning(
            context: context,
            requestedStatus: canonicalStatus(records),
            store: store
        )
        do {
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
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            references.append(try await persistImmutableArtifact(
                encoder.encode(summary),
                path: "simulation-summary.json",
                artifactID: "simulation-summary",
                role: .output,
                kind: .report,
                format: .json,
                context: context,
                store: store
            ))

            guard !records.contains(where: { $0.status == .pending || $0.status == .running }) else {
                throw XcircuiteWorkspaceStoreError.writeFailed(
                    "Simulation completion cannot retain pending or running analysis records."
                )
            }
            let status = canonicalStatus(records)
            try await finalize(
                context: context,
                status: status,
                stage: try simulationStage(
                    status: status,
                    records: records,
                    artifacts: references.filter { $0.locator.role == .output }
                ),
                registering: references
            )
        } catch {
            do {
                try await finalizeFailure(
                    context: context,
                    reason: error.localizedDescription,
                    registering: references
                )
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
        try await finalizeFailure(context: context, reason: reason, registering: [])
    }

    private func finalizeFailure(
        context: SimulationRunContext,
        reason: String,
        registering retainedArtifacts: [ArtifactReference]
    ) async throws {
        let store = try workspaceStoreFactory(context.projectRoot)
        try await requireRunning(
            context: context,
            requestedStatus: .failed,
            store: store
        )
        let payload = SimulationFailure(reason: reason, recordedAt: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let reference = try await persistImmutableArtifact(
            encoder.encode(payload),
            path: "simulation-error.json",
            artifactID: "simulation-error",
            role: .output,
            kind: .report,
            format: .json,
            context: context,
            store: store
        )
        let diagnostic = FlowDiagnostic(
            severity: .error,
            code: "SIMULATION_FAILED",
            message: reason
        )
        try await finalize(
            context: context,
            status: .failed,
            stage: FlowStageResult(
                stageID: "simulation",
                status: .failed,
                diagnostics: [diagnostic],
                gates: [
                    FlowGateResult(
                        gateID: "simulation",
                        status: .failed,
                        diagnostics: [diagnostic]
                    ),
                ],
                artifacts: (retainedArtifacts + [reference]).filter {
                    $0.locator.role == .output
                }
            ),
            registering: retainedArtifacts + [reference]
        )
    }

    private func finalize(
        context: SimulationRunContext,
        status: FlowRunStatus,
        stage: FlowStageResult,
        registering references: [ArtifactReference]
    ) async throws {
        let store = try workspaceStoreFactory(context.projectRoot)
        let ledger = try await store.loadRunLedger(runID: context.runID)
        let artifacts = try Self.mergeArtifacts(ledger.artifacts + references)
        let completedAt = Date()
        let producer = try await CircuitStudioExecutionEnvironment.producerIdentity(
            kind: .engine,
            identifier: "circuit-studio-simulation"
        )
        let provenance = try ExecutionProvenance(
            producer: producer,
            inputs: artifacts.filter { $0.locator.role == .input },
            invocation: try .inProcess(entryPoint: "SimulationService.runSPICE"),
            environment: try await CircuitStudioExecutionEnvironment.current(),
            startedAt: context.startedAt,
            completedAt: completedAt
        )
        _ = try await FlowRunLedgerCoordinator(persistence: store).finalize(
            runID: context.runID,
            status: status,
            stages: [stage],
            toolchain: FlowToolchainManifest(
                runID: context.runID,
                stages: [
                    FlowToolchainStageRecord(
                        stageID: stage.stageID,
                        executorToolID: "circuit-studio-simulation"
                    ),
                ]
            ),
            evidence: EvidenceManifest(provenance: provenance, artifacts: artifacts),
            artifacts: artifacts,
            at: completedAt
        )
    }

    private func simulationStage(
        status: FlowRunStatus,
        records: [AnalysisRunRecord],
        artifacts: [ArtifactReference]
    ) throws -> FlowStageResult {
        switch status {
        case .succeeded:
            return FlowStageResult(
                stageID: "simulation",
                status: .succeeded,
                artifacts: artifacts
            )
        case .cancelled:
            let diagnostic = FlowDiagnostic(
                severity: .warning,
                code: "SIMULATION_CANCELLED",
                message: "Simulation execution was cancelled."
            )
            return FlowStageResult(
                stageID: "simulation",
                status: .blocked,
                diagnostics: [diagnostic],
                gates: [FlowGateResult(gateID: "cancellation", status: .blocked)],
                artifacts: artifacts
            )
        case .failed:
            let reason = records.compactMap(\.failureReason).first
                ?? (records.isEmpty ? "Simulation produced no analysis records." : "Simulation analysis failed.")
            let diagnostic = FlowDiagnostic(
                severity: .error,
                code: "SIMULATION_FAILED",
                message: reason
            )
            return FlowStageResult(
                stageID: "simulation",
                status: .failed,
                diagnostics: [diagnostic],
                gates: [FlowGateResult(gateID: "simulation", status: .failed)],
                artifacts: artifacts
            )
        case .created, .running, .blocked, .partial:
            throw XcircuiteWorkspaceStoreError.writeFailed(
                "Simulation completion requires a supported terminal run status."
            )
        }
    }

    static func mergeArtifacts(_ artifacts: [ArtifactReference]) throws -> [ArtifactReference] {
        var byLocator: [ArtifactLocator: ArtifactReference] = [:]
        for artifact in artifacts {
            if let existing = byLocator[artifact.locator], existing != artifact {
                throw XcircuiteWorkspaceStoreError.writeFailed(
                    "Conflicting simulation artifact metadata for \(artifact.locator.location.value) "
                        + "with role \(artifact.locator.role.rawValue)."
                )
            }
            byLocator[artifact.locator] = artifact
        }
        return Array(byLocator.values).sorted { (lhs: ArtifactReference, rhs: ArtifactReference) in
            let left = lhs.locator
            let right = rhs.locator
            if left.location.value != right.location.value {
                return left.location.value < right.location.value
            }
            if left.role.rawValue != right.role.rawValue {
                return left.role.rawValue < right.role.rawValue
            }
            if left.kind.rawValue != right.kind.rawValue {
                return left.kind.rawValue < right.kind.rawValue
            }
            return left.format.rawValue < right.format.rawValue
        }
    }

    private func writeInputNetlist(
        _ source: String,
        context: SimulationRunContext
    ) async throws -> ArtifactReference {
        let store = try workspaceStoreFactory(context.projectRoot)
        return try await persistImmutableArtifact(
            Data(source.utf8),
            path: "input.cir",
            artifactID: "simulation-input-netlist",
            role: .input,
            kind: .netlist,
            format: .spice,
            context: context,
            store: store
        )
    }

    private func writeRequest(
        intent: String,
        fileName: String?,
        startedAt: Date,
        context: SimulationRunContext
    ) async throws -> ArtifactReference {
        let store = try workspaceStoreFactory(context.projectRoot)
        let request = SimulationRequest(
            intent: intent,
            sourceFileName: fileName,
            startedAt: startedAt
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try await persistImmutableArtifact(
            encoder.encode(request),
            path: "simulation-request.json",
            artifactID: "simulation-request",
            role: .input,
            kind: .report,
            format: .json,
            context: context,
            store: store
        )
    }

    private func writeWaveforms(
        records: [AnalysisRunRecord],
        context: SimulationRunContext
    ) async throws -> [(index: Int, reference: ArtifactReference)] {
        let store = try workspaceStoreFactory(context.projectRoot)
        var references: [(index: Int, reference: ArtifactReference)] = []
        for (index, record) in records.enumerated() {
            guard let waveform = record.result?.waveform else {
                continue
            }
            let name = waveformFileName(index: index, record: record)
            let temporaryURL = FileManager.default.temporaryDirectory
                .appending(path: "circuit-studio-waveform-\(UUID().uuidString).csv")
            try await WaveformService().export(waveform: waveform, to: temporaryURL)
            let data: Data
            do {
                data = try Data(contentsOf: temporaryURL)
                try FileManager.default.removeItem(at: temporaryURL)
            } catch let stagingError {
                var message = "Simulation waveform staging failed: \(stagingError.localizedDescription)"
                if FileManager.default.fileExists(
                    atPath: temporaryURL.path(percentEncoded: false)
                ) {
                    do {
                        try FileManager.default.removeItem(at: temporaryURL)
                    } catch let cleanupError {
                        message += "; temporary waveform cleanup failed: \(cleanupError.localizedDescription)"
                    }
                }
                throw XcircuiteWorkspaceStoreError.writeFailed(
                    message
                )
            }
            let reference = try await persistImmutableArtifact(
                data,
                path: "waveforms/\(name)",
                artifactID: "simulation-waveform-\(index)",
                role: .output,
                kind: .waveform,
                format: .csv,
                context: context,
                store: store
            )
            references.append((index, reference))
        }
        return references
    }

    private func persistImmutableArtifact(
        _ content: Data,
        path: String,
        artifactID: String,
        role: ArtifactRole,
        kind: ArtifactKind,
        format: ArtifactFormat,
        context: SimulationRunContext,
        store: XcircuiteWorkspaceStore
    ) async throws -> ArtifactReference {
        do {
            return try await store.persistArtifact(
                content: content,
                id: try ArtifactID(rawValue: artifactID),
                locator: ArtifactLocator(
                    location: try ArtifactLocation(
                        workspaceRelativePath: runRelativePath(path, context: context)
                    ),
                    role: role,
                    kind: kind,
                    format: format
                ),
                runID: context.runID,
                mode: .immutable
            )
        } catch let error as XcircuiteWorkspaceStoreError {
            throw error
        } catch {
            throw XcircuiteWorkspaceStoreError.writeFailed(
                "Failed to persist simulation artifact '\(artifactID)' at '\(path)': "
                    + error.localizedDescription
            )
        }
    }

    private func requireRunning(
        context: SimulationRunContext,
        requestedStatus: FlowRunStatus,
        store: XcircuiteWorkspaceStore
    ) async throws {
        let ledger = try await store.loadRunLedger(runID: context.runID)
        guard ledger.runManifest.status == .running else {
            throw FlowRunLedgerPersistenceError.invalidTransition(
                runID: context.runID,
                from: ledger.runManifest.status.rawValue,
                to: requestedStatus.rawValue
            )
        }
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
