import Activity
import DesignFlowKernel
import Foundation
import Testing
import XcircuitePackage

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

    @Test("Projector redacts separated secret argument values")
    func projectorRedactsSecretArguments() throws {
        var ledger = try makeLedger(runID: "run-secrets")
        ledger.actions = [
            XcircuiteRunActionRecord(
                actionID: "action-secrets",
                runID: "run-secrets",
                actor: XcircuiteRunActionActor(kind: .agent, identifier: "test-agent"),
                actionKind: "tool.execute",
                status: .succeeded,
                metadata: [
                    "executable": .string("tool"),
                    "arguments": .array([
                        .string("--token"),
                        .string("secret-value"),
                        .string("--mode=fast")
                    ])
                ]
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
        let manifest = try XcircuiteRunManifest(
            runID: runID,
            status: .created,
            actor: XcircuiteRunActionActor(kind: .agent, identifier: "test-agent"),
            intent: "Project activity test",
            createdAt: date,
            updatedAt: date
        )
        return FlowRunLedger(
            runID: runID,
            runDirectory: URL(fileURLWithPath: "/tmp/\(runID)"),
            runManifest: manifest,
            stages: []
        )
    }
}
