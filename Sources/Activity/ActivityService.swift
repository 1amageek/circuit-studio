import DesignFlowKernel
import Foundation
import Xcircuite

public actor ActivityService: ActivityRecording, ActivityQuerying {
    private let store: SQLiteActivityStore
    private let projectReader: any ActivityProjectReading
    private let projector: FlowRunActivityProjector

    public init(
        store: SQLiteActivityStore = SQLiteActivityStore(),
        projectReader: any ActivityProjectReading = XcircuiteActivityProjectStore(),
        projector: FlowRunActivityProjector = FlowRunActivityProjector()
    ) {
        self.store = store
        self.projectReader = projectReader
        self.projector = projector
    }

    public func prepare() async throws {
        try await store.prepare()
    }

    public func record(_ activity: Activity) async throws {
        try await store.record(activity)
    }

    public func record(_ activities: [Activity]) async throws {
        try await store.record(activities)
    }

    public func activities(for query: ActivityQuery) async throws -> [Activity] {
        try await store.activities(for: query)
    }

    public func reconcile(projectRoot: URL) async throws -> ActivityReconciliationResult {
        let projectManifest: XcircuiteProjectManifest
        do {
            projectManifest = try await projectReader.projectManifest(for: projectRoot)
        } catch {
            throw ActivityServiceError.projectManifestUnavailable(
                path: projectRoot.appending(path: ".xcircuite/project.json").path(percentEncoded: false)
            )
        }

        let runIDs = try await projectReader.runIDs(for: projectRoot)
        var activities: [Activity] = []
        for runID in runIDs {
            let ledger = try await projectReader.loadRunLedger(
                runID: runID,
                projectRoot: projectRoot
            )
            activities.append(contentsOf: projector.project(
                projectID: projectManifest.identity.projectID,
                ledger: ledger
            ))
        }
        try await store.record(activities)
        return ActivityReconciliationResult(
            projectID: projectManifest.identity.projectID,
            runCount: runIDs.count,
            activityCount: activities.count
        )
    }

    public func activities(
        forProjectAt projectRoot: URL,
        query: ActivityQuery = ActivityQuery()
    ) async throws -> [Activity] {
        let projectManifest: XcircuiteProjectManifest
        do {
            projectManifest = try await projectReader.projectManifest(for: projectRoot)
        } catch {
            throw ActivityServiceError.projectManifestUnavailable(
                path: projectRoot.appending(path: ".xcircuite/project.json").path(percentEncoded: false)
            )
        }
        let scopedQuery = ActivityQuery(
            projectID: projectManifest.identity.projectID,
            runID: query.runID,
            stageID: query.stageID,
            kind: query.kind,
            status: query.status,
            actorKind: query.actorKind,
            limit: query.limit
        )
        return try await store.activities(for: scopedQuery)
    }

    public func metrics() async throws -> ActivityStoreMetrics {
        try await store.metrics()
    }
}
