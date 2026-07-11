import Foundation

extension ActivityRecord {
    func hasSameContent(as other: ActivityRecord) -> Bool {
        id == other.id
            && projectID == other.projectID
            && operationID == other.operationID
            && parentOperationID == other.parentOperationID
            && sourceKind == other.sourceKind
            && sourceID == other.sourceID
            && sourceRevision == other.sourceRevision
            && runID == other.runID
            && stageID == other.stageID
            && actorKind == other.actorKind
            && actorIdentifier == other.actorIdentifier
            && kind == other.kind
            && status == other.status
            && title == other.title
            && summary == other.summary
            && commandJSON == other.commandJSON
            && artifactsJSON == other.artifactsJSON
            && omittedArtifactCount == other.omittedArtifactCount
            && diagnosticsJSON == other.diagnosticsJSON
            && omittedDiagnosticCount == other.omittedDiagnosticCount
            && occurredAt == other.occurredAt
    }

    init(activity: Activity) throws {
        self.init(
            id: activity.id,
            projectID: activity.projectID,
            operationID: activity.operationID,
            parentOperationID: activity.parentOperationID ?? "",
            sourceKind: activity.sourceKind.rawValue,
            sourceID: activity.sourceID,
            sourceRevision: activity.sourceRevision,
            runID: activity.runID ?? "",
            stageID: activity.stageID ?? "",
            actorKind: activity.actorKind.rawValue,
            actorIdentifier: activity.actorIdentifier,
            kind: activity.kind,
            status: activity.status.rawValue,
            title: activity.title,
            summary: activity.summary,
            commandJSON: try Self.encode(activity.command, field: "commandJSON"),
            artifactsJSON: try Self.encode(activity.artifacts, field: "artifactsJSON"),
            omittedArtifactCount: activity.omittedArtifactCount,
            diagnosticsJSON: try Self.encode(activity.diagnostics, field: "diagnosticsJSON"),
            omittedDiagnosticCount: activity.omittedDiagnosticCount,
            occurredAt: activity.occurredAt,
            indexedAt: activity.indexedAt
        )
    }

    func activity() throws -> Activity {
        guard let sourceKind = Activity.SourceKind(rawValue: sourceKind) else {
            throw ActivityStoreError.invalidStoredRecord(
                id: id,
                reason: "unknown source kind '\(sourceKind)'"
            )
        }
        guard let actorKind = Activity.ActorKind(rawValue: actorKind) else {
            throw ActivityStoreError.invalidStoredRecord(
                id: id,
                reason: "unknown actor kind '\(actorKind)'"
            )
        }
        guard let status = Activity.Status(rawValue: status) else {
            throw ActivityStoreError.invalidStoredRecord(
                id: id,
                reason: "unknown status '\(status)'"
            )
        }

        return Activity(
            id: id,
            projectID: projectID,
            operationID: operationID,
            parentOperationID: parentOperationID.isEmpty ? nil : parentOperationID,
            sourceKind: sourceKind,
            sourceID: sourceID,
            sourceRevision: sourceRevision,
            runID: runID.isEmpty ? nil : runID,
            stageID: stageID.isEmpty ? nil : stageID,
            actorKind: actorKind,
            actorIdentifier: actorIdentifier,
            kind: kind,
            status: status,
            title: title,
            summary: summary,
            command: try Self.decode(Activity.Command?.self, from: commandJSON, field: "commandJSON"),
            artifacts: try Self.decode([Activity.ArtifactReference].self, from: artifactsJSON, field: "artifactsJSON"),
            omittedArtifactCount: omittedArtifactCount,
            diagnostics: try Self.decode([Activity.Diagnostic].self, from: diagnosticsJSON, field: "diagnosticsJSON"),
            omittedDiagnosticCount: omittedDiagnosticCount,
            occurredAt: occurredAt,
            indexedAt: indexedAt
        )
    }

    private static func encode<T: Encodable>(_ value: T, field: String) throws -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        } catch {
            throw ActivityStoreError.invalidJSON(field: field, reason: error.localizedDescription)
        }
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from value: String,
        field: String
    ) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(value.utf8))
        } catch {
            throw ActivityStoreError.invalidJSON(field: field, reason: error.localizedDescription)
        }
    }
}
