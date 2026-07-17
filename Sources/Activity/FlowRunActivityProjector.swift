import CircuiteFoundation
import DesignFlowKernel
import Foundation

public struct FlowRunActivityProjector: Sendable {
    private static let maximumArtifactReferences = 64
    private static let maximumDiagnostics = 32
    private static let maximumDiagnosticMessageBytes = 1_024
    private static let maximumTitleBytes = 512
    private static let maximumSummaryBytes = 4 * 1_024

    public init() {}

    public func project(
        projectID: String,
        ledger: FlowRunLedger
    ) -> [Activity] {
        let manifest = ledger.runManifest
        let actorKind = activityActorKind(manifest.actor)
        let actorIdentifier = manifest.actor.identifier
        var activities: [Activity] = []
        let createdSourceID = "\(ledger.runID):created"
        let startedSourceID = "\(ledger.runID):started"
        let finishedSourceID = "\(ledger.runID):finished"

        activities.append(Activity(
            id: activityID(projectID: projectID, sourceKind: .xcircuiteRun, sourceID: createdSourceID),
            projectID: projectID,
            operationID: ledger.runID,
            parentOperationID: manifest.parentRunID,
            sourceKind: .xcircuiteRun,
            sourceID: createdSourceID,
            sourceRevision: manifest.revision,
            runID: ledger.runID,
            actorKind: actorKind,
            actorIdentifier: actorIdentifier,
            kind: "run.created",
            status: .informational,
            title: "Run created",
            summary: bounded(manifest.intent ?? "Run created"),
            occurredAt: manifest.createdAt
        ))

        if let startedAt = manifest.startedAt {
            activities.append(Activity(
                id: activityID(projectID: projectID, sourceKind: .xcircuiteRun, sourceID: startedSourceID),
                projectID: projectID,
                operationID: ledger.runID,
                parentOperationID: manifest.parentRunID,
                sourceKind: .xcircuiteRun,
                sourceID: startedSourceID,
                sourceRevision: manifest.revision,
                runID: ledger.runID,
                actorKind: actorKind,
                actorIdentifier: actorIdentifier,
                kind: "run.started",
                status: .running,
                title: "Run started",
                summary: bounded(manifest.intent ?? "Run started"),
                occurredAt: startedAt
            ))
        }

        if let finishedAt = manifest.finishedAt {
            let artifactResult = artifactReferences(manifest.artifacts, direction: .related)
            activities.append(Activity(
                id: activityID(projectID: projectID, sourceKind: .xcircuiteRun, sourceID: finishedSourceID),
                projectID: projectID,
                operationID: ledger.runID,
                parentOperationID: manifest.parentRunID,
                sourceKind: .xcircuiteRun,
                sourceID: finishedSourceID,
                sourceRevision: manifest.revision,
                runID: ledger.runID,
                actorKind: actorKind,
                actorIdentifier: actorIdentifier,
                kind: "run.finished",
                status: activityStatus(manifest.status),
                title: "Run \(manifest.status.rawValue)",
                summary: bounded(manifest.intent ?? "Run finished with status \(manifest.status.rawValue)."),
                artifacts: artifactResult.references,
                omittedArtifactCount: artifactResult.omittedCount,
                occurredAt: finishedAt
            ))
        }

        for event in ledger.progressEvents {
            activities.append(Activity(
                id: activityID(
                    projectID: projectID,
                    sourceKind: .xcircuiteProgress,
                    sourceID: "\(ledger.runID):\(event.sequence)"
                ),
                projectID: projectID,
                operationID: ledger.runID,
                parentOperationID: manifest.parentRunID,
                sourceKind: .xcircuiteProgress,
                sourceID: "\(ledger.runID):\(event.sequence)",
                sourceRevision: manifest.revision,
                runID: ledger.runID,
                stageID: event.stageID,
                actorKind: actorKind,
                actorIdentifier: actorIdentifier,
                kind: "progress.\(event.kind.rawValue)",
                status: activityStatus(runStatus: event.runStatus, stageStatus: event.stageStatus),
                title: event.stageID.map { "Progress \($0)" } ?? "Run progress",
                summary: bounded(event.message),
                occurredAt: event.createdAt
            ))
        }

        for action in ledger.actions {
            let artifactResult = actionArtifacts(action)
            let diagnosticResult = actionDiagnostics(action.diagnostics)
            let sourceID = "\(ledger.runID):\(action.actionID)"
            activities.append(Activity(
                id: activityID(
                    projectID: projectID,
                    sourceKind: .xcircuiteAction,
                    sourceID: sourceID
                ),
                projectID: projectID,
                operationID: ledger.runID,
                parentOperationID: manifest.parentRunID,
                sourceKind: .xcircuiteAction,
                sourceID: sourceID,
                sourceRevision: manifest.revision,
                runID: ledger.runID,
                stageID: action.stageID,
                actorKind: activityActorKind(action.actor),
                actorIdentifier: action.actor.identifier,
                kind: action.actionKind,
                status: activityStatus(action.status),
                title: bounded(action.actionKind, maximumBytes: Self.maximumTitleBytes),
                summary: bounded(actionSummary(action)),
                command: nil,
                artifacts: artifactResult.references,
                omittedArtifactCount: artifactResult.omittedCount,
                diagnostics: diagnosticResult.diagnostics,
                omittedDiagnosticCount: diagnosticResult.omittedCount,
                occurredAt: action.createdAt
            ))
        }

        for stage in ledger.stages {
            let artifactResult = artifactReferences(stage.artifacts, direction: .related)
            let diagnosticResult = flowDiagnostics(stage.diagnostics)
            let stageSourceID = "\(ledger.runID):stage-result:\(stage.stageID)"
            activities.append(Activity(
                id: activityID(
                    projectID: projectID,
                    sourceKind: .xcircuiteAction,
                    sourceID: stageSourceID
                ),
                projectID: projectID,
                operationID: ledger.runID,
                parentOperationID: manifest.parentRunID,
                sourceKind: .xcircuiteAction,
                sourceID: stageSourceID,
                sourceRevision: manifest.revision,
                runID: ledger.runID,
                stageID: stage.stageID,
                actorKind: actorKind,
                actorIdentifier: actorIdentifier,
                kind: "stage.result",
                status: activityStatus(stage.status),
                title: "Stage \(stage.stageID)",
                summary: bounded("Stage \(stage.stageID) finished with status \(stage.status.rawValue)."),
                artifacts: artifactResult.references,
                omittedArtifactCount: artifactResult.omittedCount,
                diagnostics: diagnosticResult.diagnostics,
                omittedDiagnosticCount: diagnosticResult.omittedCount,
                occurredAt: stage.attempts.last?.finishedAt ?? manifest.updatedAt
            ))

            for attempt in stage.attempts {
                let attemptStatus = activityStatus(attempt.status)
                let attemptSourceID = "\(ledger.runID):attempt:\(attempt.stageID):\(attempt.attemptIndex)"
                activities.append(Activity(
                    id: activityID(
                        projectID: projectID,
                        sourceKind: .xcircuiteAction,
                        sourceID: attemptSourceID
                    ),
                    projectID: projectID,
                    operationID: ledger.runID,
                    parentOperationID: manifest.parentRunID,
                    sourceKind: .xcircuiteAction,
                    sourceID: attemptSourceID,
                    sourceRevision: manifest.revision,
                    runID: ledger.runID,
                    stageID: attempt.stageID,
                    actorKind: actorKind,
                    actorIdentifier: actorIdentifier,
                    kind: "stage.attempt",
                    status: attemptStatus,
                    title: "Stage \(attempt.stageID) attempt \(attempt.attemptIndex)",
                    summary: bounded(
                        "Status \(attempt.status.rawValue); retry \(attempt.retryDecision.reason.rawValue)."
                    ),
                    occurredAt: attempt.finishedAt
                ))
            }
        }

        if let designDiff = ledger.designDiff {
            var references: [Activity.Artifact] = []
            if let baseSnapshot = designDiff.baseSnapshot {
                references.append(activityArtifact(baseSnapshot, direction: .related))
            }
            if let proposedSnapshot = designDiff.proposedSnapshot {
                references.append(activityArtifact(proposedSnapshot, direction: .related))
            }
            for change in designDiff.changes {
                for artifact in change.artifacts {
                    references.append(activityArtifact(artifact, direction: .related))
                }
            }
            let artifactResult = boundedReferences(references)
            activities.append(Activity(
                id: activityID(
                    projectID: projectID,
                    sourceKind: .xcircuiteDesignDiff,
                    sourceID: "\(ledger.runID):design-diff"
                ),
                projectID: projectID,
                operationID: ledger.runID,
                parentOperationID: manifest.parentRunID,
                sourceKind: .xcircuiteDesignDiff,
                sourceID: "\(ledger.runID):design-diff",
                sourceRevision: manifest.revision,
                runID: ledger.runID,
                actorKind: actorKind,
                actorIdentifier: designDiff.actor,
                kind: "design.diff",
                status: designDiffStatus(designDiff.reviewState),
                title: bounded(designDiff.title, maximumBytes: Self.maximumTitleBytes),
                summary: bounded(
                    "\(designDiff.reviewState.rawValue) design diff with \(designDiff.changes.count) change(s)."
                ),
                artifacts: artifactResult.references,
                omittedArtifactCount: artifactResult.omittedCount,
                occurredAt: designDiff.createdAt
            ))
        }

        if let cancellationRequest = ledger.cancellationRequest {
            activities.append(Activity(
                id: activityID(
                    projectID: projectID,
                    sourceKind: .xcircuiteAction,
                    sourceID: "cancellation:\(cancellationRequest.runID):\(cancellationRequest.requestedAt.timeIntervalSince1970)"
                ),
                projectID: projectID,
                operationID: ledger.runID,
                parentOperationID: manifest.parentRunID,
                sourceKind: .xcircuiteAction,
                sourceID: "cancellation:\(cancellationRequest.runID):\(cancellationRequest.requestedAt.timeIntervalSince1970)",
                sourceRevision: manifest.revision,
                runID: ledger.runID,
                actorKind: .system,
                actorIdentifier: cancellationRequest.requestedBy,
                kind: "run.cancellation-requested",
                status: .cancelled,
                title: "Cancellation requested",
                summary: bounded(cancellationRequest.reason),
                occurredAt: cancellationRequest.requestedAt
            ))
        }

        return activities.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt {
                return lhs.occurredAt < rhs.occurredAt
            }
            return lhs.id < rhs.id
        }
    }

    private func activityID(
        projectID: String,
        sourceKind: Activity.SourceKind,
        sourceID: String
    ) -> String {
        "\(projectID)|\(sourceKind.rawValue)|\(sourceID)"
    }

    private func activityActorKind(_ actor: FlowRunActor) -> Activity.ActorKind {
        switch actor.kind {
        case .agent: return .agent
        case .human: return .human
        case .cli: return .cli
        case .system: return .system
        }
    }

    private func activityStatus(_ status: FlowRunStatus) -> Activity.Status {
        switch status {
        case .created: return .informational
        case .running: return .running
        case .succeeded: return .succeeded
        case .failed: return .failed
        case .cancelled: return .cancelled
        case .blocked: return .blocked
        case .partial: return .partial
        }
    }

    private func activityStatus(_ status: FlowRunActionStatus) -> Activity.Status {
        switch status {
        case .running: return .running
        case .succeeded: return .succeeded
        case .failed: return .failed
        case .cancelled: return .cancelled
        case .blocked: return .blocked
        case .partial: return .partial
        }
    }

    private func activityStatus(_ status: FlowStageStatus) -> Activity.Status {
        switch status {
        case .pending, .skipped: return .informational
        case .running: return .running
        case .succeeded: return .succeeded
        case .failed: return .failed
        case .blocked: return .blocked
        }
    }

    private func activityStatus(
        runStatus: FlowRunStatus?,
        stageStatus: FlowStageStatus?
    ) -> Activity.Status {
        if let runStatus {
            switch runStatus {
            case .created: return .informational
            case .running: return .running
            case .succeeded: return .succeeded
            case .failed: return .failed
            case .cancelled: return .cancelled
            case .blocked: return .blocked
            case .partial: return .partial
            }
        }
        if let stageStatus {
            return activityStatus(stageStatus)
        }
        return .informational
    }

    private func actionSummary(_ action: FlowRunActionRecord) -> String {
        if let diagnostic = action.diagnostics.first {
            return "\(action.actionKind): \(diagnostic.message)"
        }
        return "Recorded \(action.actionKind) with status \(action.status.rawValue)."
    }

    private func actionArtifacts(
        _ action: FlowRunActionRecord
    ) -> (references: [Activity.Artifact], omittedCount: Int) {
        let inputs = action.inputs.map { activityArtifact($0, direction: .input) }
        let outputs = action.outputs.map { activityArtifact($0, direction: .output) }
        let bounded = boundedReferences(inputs + outputs)
        return (bounded.references, bounded.omittedCount)
    }

    private func artifactReferences(
        _ references: [ArtifactReference],
        direction: Activity.ArtifactDirection
    ) -> (references: [Activity.Artifact], omittedCount: Int) {
        boundedReferences(references.map { activityArtifact($0, direction: direction) })
    }

    private func boundedReferences(
        _ references: [Activity.Artifact]
    ) -> (references: [Activity.Artifact], omittedCount: Int) {
        let limitedReferences = Array(references.prefix(Self.maximumArtifactReferences))
        return (
            limitedReferences,
            max(0, references.count - limitedReferences.count)
        )
    }

    private func activityArtifact(
        _ reference: ArtifactReference,
        direction: Activity.ArtifactDirection
    ) -> Activity.Artifact {
        Activity.Artifact(
            reference: reference,
            direction: direction
        )
    }

    private func flowDiagnostics(
        _ diagnostics: [FlowDiagnostic]
    ) -> (diagnostics: [Activity.Diagnostic], omittedCount: Int) {
        boundedDiagnostics(diagnostics.map {
            Activity.Diagnostic(
                severity: $0.severity.rawValue,
                code: $0.code,
                message: bounded($0.message, maximumBytes: Self.maximumDiagnosticMessageBytes)
            )
        })
    }

    private func actionDiagnostics(
        _ diagnostics: [FlowRunDiagnostic]
    ) -> (diagnostics: [Activity.Diagnostic], omittedCount: Int) {
        boundedDiagnostics(diagnostics.map {
            Activity.Diagnostic(
                severity: $0.severity.rawValue,
                code: $0.code,
                message: bounded($0.message, maximumBytes: Self.maximumDiagnosticMessageBytes)
            )
        })
    }

    private func boundedDiagnostics(
        _ diagnostics: [Activity.Diagnostic]
    ) -> (diagnostics: [Activity.Diagnostic], omittedCount: Int) {
        let boundedDiagnostics = Array(diagnostics.prefix(Self.maximumDiagnostics))
        return (
            boundedDiagnostics,
            max(0, diagnostics.count - boundedDiagnostics.count)
        )
    }

    private func sanitizedArgument(_ argument: String) -> String {
        let lowercased = argument.lowercased()
        let sensitiveMarkers = [
            "token=", "password=", "secret=", "api_key=", "apikey=",
            "client_secret=", "authorization=", "access_token=", "bearer="
        ]
        if sensitiveMarkers.contains(where: { lowercased.contains($0) }) {
            return "<redacted>"
        }
        return bounded(argument, maximumBytes: 512)
    }

    private func isSensitiveArgumentName(_ argument: String) -> Bool {
        let normalized = argument
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
        return [
            "token", "password", "secret", "api_key", "apikey",
            "client_secret", "authorization", "access_token", "bearer"
        ].contains(normalized)
    }

    private func designDiffStatus(
        _ state: DesignDiffReviewState
    ) -> Activity.Status {
        switch state {
        case .approved, .applied: return .succeeded
        case .rejected: return .failed
        case .proposed, .superseded: return .informational
        }
    }

    private func bounded(_ value: String, maximumBytes: Int = Self.maximumSummaryBytes) -> String {
        guard value.utf8.count > maximumBytes else { return value }
        var result = ""
        for scalar in value.unicodeScalars {
            let scalarValue = String(scalar)
            guard result.utf8.count + scalarValue.utf8.count <= maximumBytes else {
                break
            }
            result.append(contentsOf: scalarValue)
        }
        return "\(result)…"
    }
}
