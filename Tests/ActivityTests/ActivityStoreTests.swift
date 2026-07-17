import Activity
import CircuiteFoundation
import DesignFlowKernel
import Foundation
import Testing

@Suite("CircuitStudio Activity Store Tests", .serialized)
struct ActivityStoreTests {
    @Test("In-memory store persists and queries an activity")
    func storesAndQueriesActivity() async throws {
        let store = SQLiteActivityStore(location: .inMemory)
        let occurredAt = Date(timeIntervalSince1970: 1_000)
        let activity = Activity(
            id: "project-1|app|open",
            projectID: "project-1",
            operationID: "operation-1",
            sourceKind: .app,
            sourceID: "open",
            actorKind: .human,
            actorIdentifier: "tester",
            kind: "project.opened",
            status: .informational,
            title: "Project opened",
            summary: "Opened project.",
            occurredAt: occurredAt,
            indexedAt: occurredAt
        )

        try await store.record(activity)
        let allRecords = try await store.activities(for: ActivityQuery())
        let records = try await store.activities(
            for: ActivityQuery(projectID: "project-1")
        )

        #expect(allRecords.count == 1)
        #expect(records == [activity])
    }

    @Test("Store round-trips the canonical artifact reference unchanged")
    func storesCanonicalArtifactReference() async throws {
        let store = SQLiteActivityStore(location: .inMemory)
        let reference = ArtifactReference(
            id: try ArtifactID(rawValue: "canonical-report"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: ".xcircuite/runs/run-canonical/report.json"
                ),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "b", count: 64)
            ),
            byteCount: 19
        )
        let activity = Activity(
            id: "project-1|run|canonical-artifact",
            projectID: "project-1",
            operationID: "run-canonical",
            sourceKind: .xcircuiteAction,
            sourceID: "canonical-artifact",
            runID: "run-canonical",
            actorKind: .system,
            actorIdentifier: "test",
            kind: "artifact.persisted",
            status: .succeeded,
            title: "Artifact persisted",
            summary: "Canonical artifact reference persisted.",
            artifacts: [Activity.Artifact(reference: reference, direction: .output)],
            occurredAt: Date(timeIntervalSince1970: 1_500),
            indexedAt: Date(timeIntervalSince1970: 1_500)
        )

        try await store.record(activity)
        let stored = try #require(
            try await store.activities(for: ActivityQuery(projectID: "project-1")).first
        )

        #expect(stored.artifacts == activity.artifacts)
        #expect(stored.artifacts.first?.reference == reference)
    }

    @Test("Repeated projection of the same immutable activity is idempotent")
    func repeatedRecordIsIdempotent() async throws {
        let store = SQLiteActivityStore(location: .inMemory)
        let activity = Activity(
            id: "project-1|app|same",
            projectID: "project-1",
            operationID: "operation-1",
            sourceKind: .app,
            sourceID: "same",
            actorKind: .system,
            actorIdentifier: "test",
            kind: "test",
            status: .succeeded,
            title: "Test",
            summary: "Test",
            occurredAt: Date(timeIntervalSince1970: 2_000),
            indexedAt: Date(timeIntervalSince1970: 2_001)
        )

        try await store.record(activity)
        try await store.record(activity)

        let conflictingActivity = Activity(
            id: activity.id,
            projectID: activity.projectID,
            operationID: activity.operationID,
            sourceKind: activity.sourceKind,
            sourceID: activity.sourceID,
            actorKind: activity.actorKind,
            actorIdentifier: activity.actorIdentifier,
            kind: activity.kind,
            status: activity.status,
            title: "Changed",
            summary: activity.summary,
            occurredAt: activity.occurredAt,
            indexedAt: activity.indexedAt
        )
        await #expect(throws: ActivityStoreError.immutableConflict(id: activity.id)) {
            try await store.record(conflictingActivity)
        }

        let metrics = try await store.metrics()
        #expect(metrics.rowCount == 1)
    }

    @Test("Projector keeps activity identity unique across runs")
    func projectorScopesIdentityToRun() throws {
        let projector = FlowRunActivityProjector()
        let first = try makeLedger(runID: "run-first")
        let second = try makeLedger(runID: "run-second")

        let firstActivities = projector.project(projectID: "project-1", ledger: first)
        let secondActivities = projector.project(projectID: "project-1", ledger: second)

        #expect(firstActivities.first?.sourceID == "run-first:created")
        #expect(secondActivities.first?.sourceID == "run-second:created")
        #expect(firstActivities.first?.id != secondActivities.first?.id)
    }

    @Test("Projector projects complete artifacts through Foundation")
    func projectorProjectsCompleteArtifactsThroughFoundation() throws {
        var ledger = try makeLedger(runID: "run-artifact")
        ledger.actions = [
            FlowRunActionRecord(
                actionID: "action-artifact",
                runID: "run-artifact",
                actor: FlowRunActor(kind: .system, identifier: "test"),
                actionKind: "artifact.capture",
                status: .succeeded,
                outputs: [
                    ArtifactReference(
                        id: try ArtifactID(rawValue: "captured-report"),
                        locator: ArtifactLocator(
                            location: try ArtifactLocation(
                                workspaceRelativePath: ".xcircuite/runs/run-artifact/report.json"
                            ),
                            role: .output,
                            kind: .report,
                            format: .json
                        ),
                        digest: try ContentDigest(
                            algorithm: .sha256,
                            hexadecimalValue: String(repeating: "a", count: 64)
                        ),
                        byteCount: 7
                    )
                ]
            )
        ]

        let activities = FlowRunActivityProjector().project(
            projectID: "project-1",
            ledger: ledger
        )
        let action = try #require(activities.first(where: { $0.kind == "artifact.capture" }))
        let artifact = try #require(action.artifacts.first)

        #expect(artifact.reference.id.rawValue == "captured-report")
        #expect(artifact.reference.locator.role == .output)
        #expect(artifact.reference.kind == .report)
        #expect(artifact.reference.format == .json)
        #expect(artifact.reference.digest.hexadecimalValue == String(repeating: "a", count: 64))
        #expect(artifact.reference.byteCount == 7)
        #expect(artifact.direction == .output)
    }

    @Test("Projector redacts separated secret argument values")
    func projectorRedactsSecretArguments() throws {
        var ledger = try makeLedger(runID: "run-secrets")
        ledger.actions = [
            FlowRunActionRecord(
                actionID: "action-secrets",
                runID: "run-secrets",
                actor: FlowRunActor(kind: .agent, identifier: "test-agent"),
                actionKind: "tool.execute",
                status: .succeeded,
                context: FlowRunActionContext(
                    suggestedCommand: FlowRunActionContext.SuggestedCommand(
                        nextActionID: "run-tool",
                        nextActionKind: "tool.execute",
                        commandID: "tool.execute.run",
                        readiness: "ready",
                        executable: "tool",
                        arguments: ["--token", "secret-value", "--mode=fast"],
                        reason: "Exercise command argument redaction."
                    )
                )
            )
        ]

        let activities = FlowRunActivityProjector().project(
            projectID: "project-1",
            ledger: ledger
        )
        let action = try #require(activities.first(where: { $0.kind == "tool.execute" }))

        #expect(action.command?.arguments == ["--token", "<redacted>", "--mode=fast"])
        #expect(action.command?.redactedArgumentCount == 1)
    }

    private func makeLedger(runID: String) throws -> FlowRunLedger {
        let date = Date(timeIntervalSince1970: 3_000)
        let manifest = try FlowRunManifest(
            runID: runID,
            status: .created,
            actor: FlowRunActor(kind: .agent, identifier: "test-agent"),
            intent: "Project activity test",
            createdAt: date,
            updatedAt: date
        )
        return FlowRunLedger(
            runID: runID,
            runManifest: manifest,
            stages: []
        )
    }
}
