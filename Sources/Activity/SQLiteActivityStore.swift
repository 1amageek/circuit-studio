import Database
import Foundation

public actor SQLiteActivityStore: ActivityRecording, ActivityQuerying {
    public enum Location: Sendable, Hashable {
        case applicationSupport
        case file(URL)
        case inMemory
    }

    private let location: Location
    private var container: DBContainer?
    private var preparedDatabaseURL: URL?

    public init(location: Location = .applicationSupport) {
        self.location = location
    }

    public func prepare() async throws {
        _ = try await preparedContainer()
    }

    public func record(_ activity: Activity) async throws {
        try await record([activity])
    }

    public func record(_ activities: [Activity]) async throws {
        guard !activities.isEmpty else { return }
        let container = try await preparedContainer()
        let records = try activities.map(ActivityRecord.init(activity:))
        let context = container.newContext()
        var insertedCount = 0

        for record in records {
            let existing = try await context.fetch(ActivityRecord.self)
                .where(ActivityRecord.fields.id == record.id)
                .execute()
                .first
            if let existing {
                guard existing.hasSameContent(as: record) else {
                    throw ActivityStoreError.immutableConflict(id: record.id)
                }
                continue
            }
            try context.insert(record)
            insertedCount += 1
        }

        guard insertedCount > 0 else { return }
        try await context.save()
    }

    public func activities(for query: ActivityQuery) async throws -> [Activity] {
        let container = try await preparedContainer()
        var request = container.newContext().fetch(ActivityRecord.self)
        if let projectID = query.projectID {
            request = request.where(ActivityRecord.fields.projectID == projectID)
        }
        if let runID = query.runID {
            request = request.where(ActivityRecord.fields.runID == runID)
        }
        if let stageID = query.stageID {
            request = request.where(ActivityRecord.fields.stageID == stageID)
        }
        if let kind = query.kind {
            request = request.where(ActivityRecord.fields.kind == kind)
        }
        if let status = query.status {
            request = request.where(ActivityRecord.fields.status == status.rawValue)
        }
        if let actorKind = query.actorKind {
            request = request.where(ActivityRecord.fields.actorKind == actorKind.rawValue)
        }

        let records = try await request
            .orderBy(ActivityRecord.fields.occurredAt, .descending)
            .execute()
        return try records.prefix(query.limit).map { try $0.activity() }
    }

    public func metrics() async throws -> ActivityStoreMetrics {
        let container = try await preparedContainer()
        let rowCount = try await container.newContext()
            .fetch(ActivityRecord.self)
            .count()
        let byteCount: Int64?
        if let databaseURL = preparedDatabaseURL {
            do {
                let values = try databaseURL.resourceValues(forKeys: [.fileSizeKey])
                byteCount = values.fileSize.map(Int64.init)
            } catch {
                throw ActivityStoreError.databaseSizeUnavailable(error.localizedDescription)
            }
        } else {
            byteCount = nil
        }
        return ActivityStoreMetrics(rowCount: rowCount, databaseByteCount: byteCount)
    }

    private func preparedContainer() async throws -> DBContainer {
        if let container {
            return container
        }

        let databaseURL: URL?
        switch location {
        case .applicationSupport:
            databaseURL = try ActivityDatabaseLocation.applicationDatabaseURL()
        case .file(let url):
            databaseURL = url
        case .inMemory:
            databaseURL = nil
        }

        let configuration: SQLiteStorageEngine.Configuration
        if let databaseURL {
            do {
                try FileManager.default.createDirectory(
                    at: databaseURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                throw ActivityStoreError.databasePathCreationFailed(error.localizedDescription)
            }
            configuration = .file(databaseURL.path(percentEncoded: false))
        } else {
            configuration = .inMemory
        }

        let newContainer = try await DBContainer.open(
            for: ActivitySchemaV1.self,
            migrationPlan: ActivityMigrationPlan.self,
            configuration: configuration,
            monotonicClock: ActivityDatabaseMonotonicClock(),
            wallClock: ActivityDatabaseWallClock(),
            runtimeConfiguration: try DatabaseFrameworkRuntime.configuration(
                entityRuntimes: [try DatabaseFrameworkRuntime.entity(ActivityRecord.self)]
            ),
            security: .disabled
        )
        try await newContainer.migrateIfNeeded()
        container = newContainer
        preparedDatabaseURL = databaseURL
        return newContainer
    }
}
