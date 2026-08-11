import Database
import DatabaseKitFoundation
import Foundation

@Persistable
struct ActivityRecord {
    #Directory<ActivityRecord>("circuit-studio", "activity", "records")

    #Index(.scalar, fields: [\ActivityRecord.projectID])
    #Index(.scalar, fields: [\ActivityRecord.runID])
    #Index(.scalar, fields: [\ActivityRecord.stageID])
    #Index(.scalar, fields: [\ActivityRecord.operationID])
    #Index(.scalar, fields: [\ActivityRecord.actorKind])
    #Index(.scalar, fields: [\ActivityRecord.kind])
    #Index(.scalar, fields: [\ActivityRecord.status])
    #Index(.scalar, fields: [\ActivityRecord.occurredAt])

    var id: String = UUID().uuidString
    var projectID: String = ""
    var operationID: String = ""
    var parentOperationID: String = ""
    var sourceKind: String = ""
    var sourceID: String = ""
    var sourceRevision: Int64 = 0
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
    var omittedArtifactCount: Int64 = 0
    var diagnosticsJSON: String = "[]"
    var omittedDiagnosticCount: Int64 = 0
    var occurredAt: Date = Date()
    var indexedAt: Date = Date()
}
