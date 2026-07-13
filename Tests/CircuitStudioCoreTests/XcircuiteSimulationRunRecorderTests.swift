import Foundation
import Testing
import DesignFlowKernel
@testable import CircuitStudioApp
@testable import CircuitStudioCore

@Suite("Xcircuite simulation run recorder")
struct XcircuiteSimulationRunRecorderTests {
    @Test func completedSimulationUsesCanonicalRunLifecycle() async throws {
        let root = try makeTemporaryRoot("completed")
        defer { removeTemporaryRoot(root) }
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let recorder = XcircuiteSimulationRunRecorder(
            actor: XcircuiteRunActionActor(kind: .human, identifier: "layout-engineer"),
            runID: { "simulation-completed" }
        )

        let context = try recorder.begin(
            projectRoot: root,
            intent: "Run operating point simulation.",
            source: "Voltage divider\n.op\n.end\n",
            fileName: "divider.cir",
            startedAt: startedAt
        )
        let running = try XcircuitePackageStore().loadRunManifest(
            runID: context.runID,
            inProjectAt: root
        )
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

        let completed = try XcircuitePackageStore().loadRunManifest(
            runID: context.runID,
            inProjectAt: root
        )
        #expect(completed.status == .succeeded)
        #expect(completed.actor.identifier == "layout-engineer")
        #expect(completed.intent == "Run operating point simulation.")
        #expect(completed.artifacts.contains { $0.artifactID == "simulation-summary" })
    }

    @Test func explicitSimulationFailureIsPersisted() throws {
        let root = try makeTemporaryRoot("failed")
        defer { removeTemporaryRoot(root) }
        let recorder = XcircuiteSimulationRunRecorder(
            actor: XcircuiteRunActionActor(kind: .human, identifier: "layout-engineer"),
            runID: { "simulation-failed" }
        )
        let context = try recorder.begin(
            projectRoot: root,
            intent: "Run transient simulation.",
            source: "Transient\n.tran 1n 1u\n.end\n",
            fileName: "transient.cir",
            startedAt: Date(timeIntervalSince1970: 2_000)
        )

        try recorder.fail(context: context, reason: "non-convergence")

        let manifest = try XcircuitePackageStore().loadRunManifest(
            runID: context.runID,
            inProjectAt: root
        )
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.contains { $0.artifactID == "simulation-error" })
    }

    @Test func setupFailureRetainsCompletedEvidenceAndStructuredError() throws {
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
            actor: XcircuiteRunActionActor(kind: .human, identifier: "layout-engineer"),
            runID: { runID }
        )

        do {
            _ = try recorder.begin(
                projectRoot: root,
                intent: "Run setup failure regression.",
                source: "Voltage divider\n.op\n.end\n",
                fileName: "divider.cir",
                startedAt: Date(timeIntervalSince1970: 3_000)
            )
            Issue.record("Expected simulation setup to fail.")
        } catch {
            #expect(error is XcircuitePackageError)
        }

        let manifest = try XcircuitePackageStore().loadRunManifest(
            runID: runID,
            inProjectAt: root
        )
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.contains { $0.artifactID == "simulation-request" })
        #expect(manifest.artifacts.contains { $0.artifactID == "simulation-error" })
        #expect(!manifest.artifacts.contains { $0.artifactID == "simulation-input-netlist" })
    }

    @Test @MainActor func interactiveRunRequiresAProjectForCanonicalRecording() async {
        let appState = AppState()
        appState.spiceSource = "Voltage divider\n.op\n.end\n"
        let recorder = XcircuiteSimulationRunRecorder(
            actor: XcircuiteRunActionActor(kind: .human, identifier: "layout-engineer"),
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
            actor: XcircuiteRunActionActor(kind: .human, identifier: "layout-engineer"),
            runID: { "simulation-preflight-failed" }
        )

        await appState.runActiveSimulation(
            schematicDocument: SchematicDocument(),
            service: DesignFlowService(),
            recorder: recorder
        )

        let manifest = try XcircuitePackageStore().loadRunManifest(
            runID: "simulation-preflight-failed",
            inProjectAt: root
        )
        #expect(manifest.status == .failed)
        #expect(manifest.artifacts.contains { $0.artifactID == "simulation-request" })
        #expect(manifest.artifacts.contains { $0.artifactID == "simulation-error" })
        #expect(appState.simulationError == "No SPICE source loaded")
        #expect(appState.runHistory.isEmpty)
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
