import DesignFlowKernel
import Foundation
import XcircuitePackage

public actor ActivityService: ActivityRecording, ActivityQuerying {
    private let store: SQLiteActivityStore
    private let packageStore: XcircuitePackageStore
    private let ledgerLoader: FlowRunLedgerLoader
    private let projector: FlowRunActivityProjector

    public init(
        store: SQLiteActivityStore = SQLiteActivityStore(),
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        ledgerLoader: FlowRunLedgerLoader = FlowRunLedgerLoader(),
        projector: FlowRunActivityProjector = FlowRunActivityProjector()
    ) {
        self.store = store
        self.packageStore = packageStore
        self.ledgerLoader = ledgerLoader
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
            projectManifest = try packageStore.loadManifest(forProjectAt: projectRoot)
        } catch {
            throw ActivityServiceError.projectManifestUnavailable(
                path: projectRoot.appending(path: ".xcircuite/project.json").path(percentEncoded: false)
            )
        }

        let snapshots = try packageStore.listRunSnapshots(inProjectAt: projectRoot)
        var activities: [Activity] = []
        for snapshot in snapshots {
            let ledger = try ledgerLoader.loadRunLedger(
                runID: snapshot.runID,
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
            runCount: snapshots.count,
            activityCount: activities.count
        )
    }

    public func activities(
        forProjectAt projectRoot: URL,
        query: ActivityQuery = ActivityQuery()
    ) async throws -> [Activity] {
        let projectManifest: XcircuiteProjectManifest
        do {
            projectManifest = try packageStore.loadManifest(forProjectAt: projectRoot)
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
