import Foundation
import Testing
import CircuiteFoundation
import CircuiteFoundationCrypto
import DesignFlowKernel
import Xcircuite
@testable import CircuitStudioApp
@testable import CircuitStudioCore

@Suite("Xcircuite simulation run recorder")
struct XcircuiteSimulationRunRecorderTests {
    @Test func completedSimulationUsesCanonicalRunLifecycle() async throws {
        let root = try makeTemporaryRoot("completed")
        defer { removeTemporaryRoot(root) }
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let recorder = XcircuiteSimulationRunRecorder(
            actor: FlowRunActor(kind: .human, identifier: "layout-engineer"),
            runID: { "simulation-completed" }
        )

        let context = try await recorder.begin(
            projectRoot: root,
            intent: "Run operating point simulation.",
            source: "Voltage divider\n.op\n.end\n",
            fileName: "divider.cir",
            startedAt: startedAt
        )
        let running = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunManifest(runID: context.runID)
        #expect(running.status == .running)
        #expect(running.artifacts.contains { $0.artifactID == "simulation-request" })
        #expect(running.artifacts.contains { $0.artifactID == "simulation-input-netlist" })

        let result = SimulationResult(
            experimentID: UUID(),
            status: .completed,
            startedAt: startedAt,
            finishedAt: Date(timeIntervalSince1970: 1_001)
        )
        try await recorder.complete(
            context: context,
            source: nil,
            records: [
                AnalysisRunRecord(
                    analysis: .op,
                    status: .completed,
                    result: result,
                    startedAt: result.startedAt,
                    finishedAt: result.finishedAt
                ),
            ]
        )

        let completed = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunManifest(runID: context.runID)
        #expect(completed.status == .succeeded)
        #expect(completed.actor.identifier == "layout-engineer")
        #expect(completed.intent == "Run operating point simulation.")
        #expect(completed.artifacts.contains { $0.artifactID == "simulation-summary" })
        let ledger = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunLedger(runID: context.runID)
        let stage = try #require(ledger.stages.first)
        #expect(stage.stageID == "simulation")
        #expect(stage.status == .succeeded)
        #expect(stage.artifacts.contains { $0.artifactID == "simulation-summary" })
        #expect(ledger.evidence?.artifacts == ledger.artifacts.map(\.reference))
        let provenance = try #require(ledger.evidence?.provenance)
        #expect(provenance.producer.version.hasPrefix("sha256-"))
        #expect(provenance.producer.version.count == 71)
        #expect(provenance.producer.build == provenance.producer.version)
        let environment = try #require(provenance.environment)
        #expect(environment.platform.hasPrefix("macos-"))
        #expect(!environment.architecture.isEmpty)
        #expect(environment.architecture != "unknown")
        #expect(environment.toolchain.contains("Swift version"))
        #expect(environment.toolchain != "swift-6.3")
        #expect(environment.environmentDigest != nil)
    }

    @Test func explicitSimulationFailureIsPersisted() async throws {
        let root = try makeTemporaryRoot("failed")
        defer { removeTemporaryRoot(root) }
        let recorder = XcircuiteSimulationRunRecorder(
            actor: FlowRunActor(kind: .human, identifier: "layout-engineer"),
            runID: { "simulation-failed" }
        )
        let context = try await recorder.begin(
            projectRoot: root,
            intent: "Run transient simulation.",
            source: "Transient\n.tran 1n 1u\n.end\n",
            fileName: "transient.cir",
            startedAt: Date(timeIntervalSince1970: 2_000)
        )

        try await recorder.fail(context: context, reason: "non-convergence")

        let manifest = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunManifest(runID: context.runID)
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.contains { $0.artifactID == "simulation-error" })
        let ledger = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunLedger(runID: context.runID)
        #expect(ledger.stages.first?.status == .failed)
        #expect(ledger.stages.first?.artifacts.contains {
            $0.artifactID == "simulation-error"
        } == true)
        #expect(ledger.evidence?.artifacts == ledger.artifacts.map(\.reference))
    }

    @Test func duplicateRunIdentifierDoesNotOverwriteRecordedInputs() async throws {
        let root = try makeTemporaryRoot("duplicate-run-input-immutability")
        defer { removeTemporaryRoot(root) }
        let runID = "simulation-duplicate-inputs"
        let recorder = XcircuiteSimulationRunRecorder(
            actor: FlowRunActor(kind: .human, identifier: "layout-engineer"),
            runID: { runID }
        )
        _ = try await recorder.begin(
            projectRoot: root,
            intent: "Retain the original simulation request.",
            source: "Original\n.op\n.end\n",
            fileName: "original.cir",
            startedAt: Date(timeIntervalSince1970: 1_200)
        )
        let requestURL = root.appending(
            path: ".xcircuite/runs/\(runID)/simulation-request.json"
        )
        let netlistURL = root.appending(path: ".xcircuite/runs/\(runID)/input.cir")
        let originalRequest = try Data(contentsOf: requestURL)
        let originalNetlist = try Data(contentsOf: netlistURL)

        do {
            _ = try await recorder.begin(
                projectRoot: root,
                intent: "Replace the original simulation request.",
                source: "Replacement\n.tran 1n 1u\n.end\n",
                fileName: "replacement.cir",
                startedAt: Date(timeIntervalSince1970: 1_201)
            )
            Issue.record("Expected a duplicate run identifier to be rejected.")
        } catch {
            #expect(error is FlowRunLedgerPersistenceError)
        }

        #expect(try Data(contentsOf: requestURL) == originalRequest)
        #expect(try Data(contentsOf: netlistURL) == originalNetlist)
    }

    @Test func terminalSimulationRejectsFurtherWritesWithoutMutatingArtifacts() async throws {
        let root = try makeTemporaryRoot("terminal-immutability")
        defer { removeTemporaryRoot(root) }
        let runID = "simulation-terminal-immutability"
        let startedAt = Date(timeIntervalSince1970: 1_500)
        let recorder = XcircuiteSimulationRunRecorder(
            actor: FlowRunActor(kind: .human, identifier: "layout-engineer"),
            runID: { runID }
        )
        let context = try await recorder.begin(
            projectRoot: root,
            intent: "Verify terminal artifact immutability.",
            source: "Voltage divider\n.op\n.end\n",
            fileName: "divider.cir",
            startedAt: startedAt
        )
        let completedResult = SimulationResult(
            experimentID: UUID(),
            status: .completed,
            startedAt: startedAt,
            finishedAt: Date(timeIntervalSince1970: 1_501)
        )
        try await recorder.complete(
            context: context,
            source: nil,
            records: [
                AnalysisRunRecord(
                    analysis: .op,
                    status: .completed,
                    result: completedResult,
                    startedAt: completedResult.startedAt,
                    finishedAt: completedResult.finishedAt
                ),
            ]
        )
        let summaryURL = root.appending(
            path: ".xcircuite/runs/\(runID)/simulation-summary.json"
        )
        let retainedSummary = try Data(contentsOf: summaryURL)

        await #expect(throws: FlowRunLedgerPersistenceError.self) {
            try await recorder.complete(context: context, source: nil, records: [])
        }
        await #expect(throws: FlowRunLedgerPersistenceError.self) {
            try await recorder.fail(context: context, reason: "late failure")
        }

        #expect(try Data(contentsOf: summaryURL) == retainedSummary)
        #expect(!FileManager.default.fileExists(
            atPath: root.appending(
                path: ".xcircuite/runs/\(runID)/simulation-error.json"
            ).path(percentEncoded: false)
        ))
    }

    @Test func setupFailureRetainsCompletedEvidenceAndStructuredError() async throws {
        let root = try makeTemporaryRoot("setup-failed")
        defer { removeTemporaryRoot(root) }
        let runID = "simulation-setup-failed"
        let blockedInputURL = root
            .appending(path: ".xcircuite/runs")
            .appending(path: runID)
            .appending(path: "input.cir")
        try FileManager.default.createDirectory(
            at: blockedInputURL,
            withIntermediateDirectories: true
        )
        let recorder = XcircuiteSimulationRunRecorder(
            actor: FlowRunActor(kind: .human, identifier: "layout-engineer"),
            runID: { runID }
        )

        do {
            _ = try await recorder.begin(
                projectRoot: root,
                intent: "Run setup failure regression.",
                source: "Voltage divider\n.op\n.end\n",
                fileName: "divider.cir",
                startedAt: Date(timeIntervalSince1970: 3_000)
            )
            Issue.record("Expected simulation setup to fail.")
        } catch {
            #expect(error is XcircuiteWorkspaceStoreError)
        }

        let manifest = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunManifest(runID: runID)
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.contains { $0.artifactID == "simulation-request" })
        #expect(manifest.artifacts.contains { $0.artifactID == "simulation-error" })
        #expect(!manifest.artifacts.contains { $0.artifactID == "simulation-input-netlist" })
        let ledger = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunLedger(runID: runID)
        #expect(ledger.stages.first?.status == .failed)
        #expect(ledger.stages.first?.artifacts.contains {
            $0.artifactID == "simulation-error"
        } == true)
        #expect(ledger.evidence?.artifacts == ledger.artifacts.map(\.reference))
    }

    @Test @MainActor func interactiveRunRequiresAProjectForCanonicalRecording() async {
        let appState = AppState()
        appState.spiceSource = "Voltage divider\n.op\n.end\n"
        let recorder = XcircuiteSimulationRunRecorder(
            actor: FlowRunActor(kind: .human, identifier: "layout-engineer"),
            runID: { "simulation-without-project" }
        )

        await appState.runSimulation(
            service: DesignFlowService(),
            recorder: recorder
        )

        #expect(appState.simulationError == "Open or create a project before running a recorded simulation.")
        #expect(appState.runHistory.isEmpty)
        #expect(!appState.isSimulating)
    }

    @Test @MainActor func activeRunPreflightFailureIsRecordedInCanonicalRun() async throws {
        let root = try makeTemporaryRoot("preflight-failed")
        defer { removeTemporaryRoot(root) }
        let appState = AppState()
        appState.projectRootURL = root
        appState.showSchematic(.netlist)
        appState.spiceSource = ""
        let recorder = XcircuiteSimulationRunRecorder(
            actor: FlowRunActor(kind: .human, identifier: "layout-engineer"),
            runID: { "simulation-preflight-failed" }
        )

        await appState.runActiveSimulation(
            schematicDocument: SchematicDocument(),
            service: DesignFlowService(),
            recorder: recorder
        )

        let manifest = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunManifest(runID: "simulation-preflight-failed")
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.contains { $0.artifactID == "simulation-request" })
        #expect(manifest.artifacts.contains { $0.artifactID == "simulation-error" })
        #expect(appState.simulationError == "No SPICE source loaded")
        #expect(appState.runHistory.isEmpty)
    }

    @Test func missingExecutableFailsWithTypedProvenanceError() async throws {
        let missingPath = FileManager.default.temporaryDirectory
            .appending(path: "missing-circuit-studio-executable-\(UUID().uuidString)")
            .path(percentEncoded: false)

        do {
            _ = try await CircuitStudioExecutionEnvironment.producerIdentity(
                kind: .tool,
                identifier: "missing-tool",
                executablePath: missingPath
            )
            Issue.record("Expected a missing provenance executable to be rejected.")
        } catch let error as CircuitStudioExecutionEnvironmentError {
            guard case .executableOpenFailed(let path, let reason) = error else {
                Issue.record("Expected a typed open failure, got \(error).")
                return
            }
            #expect(path == missingPath)
            #expect(!reason.isEmpty)
        } catch {
            Issue.record("Expected a typed provenance error, got \(error).")
        }
    }

    @Test func symlinkExecutableIsFingerprintedThroughOneStableDescriptor() async throws {
        let root = try makeTemporaryRoot("provenance-symlink")
        defer { removeTemporaryRoot(root) }
        let executableURL = root.appending(path: "tool")
        let symlinkURL = root.appending(path: "tool-link")
        let executableData = Data("#!/bin/sh\nexit 0\n".utf8)
        try executableData.write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executableURL.path(percentEncoded: false)
        )
        try FileManager.default.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: executableURL
        )

        let identity = try await CircuitStudioExecutionEnvironment.producerIdentity(
            kind: .tool,
            identifier: "symlink-tool",
            executablePath: symlinkURL.path(percentEncoded: false)
        )
        let digest = try SHA256ContentDigester().digest(
            data: executableData,
            using: .sha256
        )

        #expect(identity.version == "sha256-\(digest.hexadecimalValue)")
        #expect(identity.build == identity.version)
    }

    @Test func executionEnvironmentFingerprintBindsEffectiveEnvironment() async throws {
        let first = try await CircuitStudioExecutionEnvironment.current(
            environment: ["SIMULATION_CORNER": "slow"]
        )
        let second = try await CircuitStudioExecutionEnvironment.current(
            environment: ["SIMULATION_CORNER": "fast"]
        )

        #expect(first.environmentDigest != nil)
        #expect(second.environmentDigest != nil)
        #expect(first.environmentDigest != second.environmentDigest)
    }

    @Test func artifactMergePreservesDistinctRolesAtTheSameAvailability() throws {
        let payload = Data("shared netlist".utf8)
        let digest = try SHA256ContentDigester().digest(data: payload, using: .sha256)
        let relativePath = try ArtifactRelativePath(segments: ["design", "shared.cir"])
        let inputReference = try ArtifactReference(
            digest: digest,
            byteCount: UInt64(payload.count),
            descriptor: ArtifactDescriptor(
                role: .input,
                kind: .netlist,
                format: .spice
            )
        )
        let outputReference = try ArtifactReference(
            digest: digest,
            byteCount: UInt64(payload.count),
            descriptor: ArtifactDescriptor(
                role: .output,
                kind: .netlist,
                format: .spice
            )
        )
        let rootID = try ArtifactRootID(rawValue: "simulation-test")
        let input = try FlowArtifactBinding(
            logicalID: "shared-netlist-input",
            reference: inputReference,
            availability: .local(
                artifactID: inputReference.id,
                rootID: rootID,
                relativePath: relativePath
            )
        )
        let output = try FlowArtifactBinding(
            logicalID: "shared-netlist-output",
            reference: outputReference,
            availability: .local(
                artifactID: outputReference.id,
                rootID: rootID,
                relativePath: relativePath
            )
        )

        let merged = try XcircuiteSimulationRunRecorder.mergeArtifacts([output, input])

        #expect(merged.count == 2)
        #expect(Set(merged.map(\.role)) == [.input, .output])
    }

    @Test func artifactMergeRejectsConflictingContentForTheSameLogicalMaterialization() throws {
        let descriptor = ArtifactDescriptor(
            role: .output,
            kind: .netlist,
            format: .spice
        )
        let relativePath = try ArtifactRelativePath(segments: ["design", "shared.cir"])
        let rootID = try ArtifactRootID(rawValue: "simulation-test")
        let firstReference = try ArtifactReference(
            digest: try SHA256ContentDigester().digest(data: Data("first".utf8), using: .sha256),
            byteCount: 5,
            descriptor: descriptor
        )
        let conflictingReference = try ArtifactReference(
            digest: try SHA256ContentDigester().digest(data: Data("second".utf8), using: .sha256),
            byteCount: 6,
            descriptor: descriptor
        )
        let first = try FlowArtifactBinding(
            logicalID: "shared-netlist",
            reference: firstReference,
            availability: .local(
                artifactID: firstReference.id,
                rootID: rootID,
                relativePath: relativePath
            )
        )
        let conflicting = try FlowArtifactBinding(
            logicalID: "shared-netlist",
            reference: conflictingReference,
            availability: .local(
                artifactID: conflictingReference.id,
                rootID: rootID,
                relativePath: relativePath
            )
        )

        #expect(throws: XcircuiteWorkspaceStoreError.self) {
            _ = try XcircuiteSimulationRunRecorder.mergeArtifacts([first, conflicting])
        }
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "XcircuiteSimulationRunRecorderTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary simulation project: \(error)")
        }
    }
}
