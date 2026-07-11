import Database
import Foundation

@Persistable
struct ActivityRecord {
    #Directory<ActivityRecord>("circuit-studio", "activity", "records")

    #Index(ScalarIndexKind<ActivityRecord>(fields: [\.projectID]))
    #Index(ScalarIndexKind<ActivityRecord>(fields: [\.runID]))
    #Index(ScalarIndexKind<ActivityRecord>(fields: [\.stageID]))
    #Index(ScalarIndexKind<ActivityRecord>(fields: [\.operationID]))
    #Index(ScalarIndexKind<ActivityRecord>(fields: [\.actorKind]))
    #Index(ScalarIndexKind<ActivityRecord>(fields: [\.kind]))
    #Index(ScalarIndexKind<ActivityRecord>(fields: [\.status]))
    #Index(ScalarIndexKind<ActivityRecord>(fields: [\.occurredAt]))

    var id: String = UUID().uuidString
    var projectID: String = ""
    var operationID: String = ""
    var parentOperationID: String = ""
    var sourceKind: String = ""
    var sourceID: String = ""
    var sourceRevision: Int = 0
    var runID: String = ""
    var stageID: String = ""
    var actorKind: String = ""
    var actorIdentifier: String = ""
    var kind: String = ""
    var status: String = ""
    var title: String = ""
    var summary: String = ""
    var commandJSON: String = "null"
    var artifactsJSON: String = "[]"
    var omittedArtifactCount: Int = 0
    var diagnosticsJSON: String = "[]"
    var omittedDiagnosticCount: Int = 0
    var occurredAt: Date = Date()
    var indexedAt: Date = Date()

    init(
        id: String,
        projectID: String,
        operationID: String,
        parentOperationID: String,
        sourceKind: String,
        sourceID: String,
        sourceRevision: Int,
        runID: String,
        stageID: String,
        actorKind: String,
        actorIdentifier: String,
        kind: String,
        status: String,
        title: String,
        summary: String,
        commandJSON: String,
        artifactsJSON: String,
        omittedArtifactCount: Int,
        diagnosticsJSON: String,
        omittedDiagnosticCount: Int,
        occurredAt: Date,
        indexedAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.operationID = operationID
        self.parentOperationID = parentOperationID
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.sourceRevision = sourceRevision
        self.runID = runID
        self.stageID = stageID
        self.actorKind = actorKind
        self.actorIdentifier = actorIdentifier
        self.kind = kind
        self.status = status
        self.title = title
        self.summary = summary
        self.commandJSON = commandJSON
        self.artifactsJSON = artifactsJSON
        self.omittedArtifactCount = omittedArtifactCount
        self.diagnosticsJSON = diagnosticsJSON
        self.omittedDiagnosticCount = omittedDiagnosticCount
        self.occurredAt = occurredAt
        self.indexedAt = indexedAt
    }
}
