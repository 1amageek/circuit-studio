import Foundation
import Testing
import CircuiteFoundation
import DesignFlowKernel
import LayoutCore
import ToolQualification
import Xcircuite
@testable import CircuitStudioApp
@testable import CircuitStudioCore

struct RunReviewPassingExecutor: FlowStageExecutor {
    let stageID: String
    let toolID = "stub-tool"
    var artifacts: [ArtifactReference] = []
    var artifactPayloads: [String: Data] = [:]

    func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        var resolvedArtifacts = artifacts
        for index in resolvedArtifacts.indices {
            let path = resolvedArtifacts[index].locator.location.value
            guard let payload = artifactPayloads[path] else {
                continue
            }
            let existing = resolvedArtifacts[index]
            resolvedArtifacts[index] = try await context.infrastructure.persistArtifact(
                content: payload,
                id: existing.id,
                locator: existing.locator,
                runID: context.runID,
                mode: .replaceable
            )
        }

        return FlowStageResult(
            stageID: stage.stageID,
            status: .succeeded,
            gates: [FlowGateResult(gateID: "drc", status: .passed)],
            artifacts: resolvedArtifacts
        )
    }
}

enum RunReviewTestSupport {
    static func artifactReference(
        artifactID: String,
        path: String,
        kind: ArtifactKind = .report,
        format: ArtifactFormat = .json,
        byteCount: UInt64 = 0
    ) throws -> ArtifactReference {
        let location = try ArtifactLocation(workspaceRelativePath: path)
        let locator = ArtifactLocator(
            location: location,
            role: .output,
            kind: kind,
            format: format
        )
        let digest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "0", count: 64)
        )
        let id = try ArtifactID(rawValue: artifactID)
        return ArtifactReference(
            id: id,
            locator: locator,
            digest: digest,
            byteCount: byteCount
        )
    }

    static func orchestrator(projectRoot: URL) throws -> DefaultFlowOrchestrator {
        let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        return DefaultFlowOrchestrator(
            infrastructure: store,
            ledgerPersistence: store,
            producer: try ProducerIdentity(
                kind: .library,
                identifier: "circuit-studio-tests",
                version: "development"
            ),
            progressStore: FlowRunProgressStore(persistence: store)
        )
    }

    static func workspaceID(projectRoot: URL) async throws -> FlowWorkspaceID {
        let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        try await store.createWorkspace()
        let manifest = try await store.loadManifest()
        return try FlowWorkspaceID(rawValue: manifest.identity.projectID)
    }

    static func feedbackPenalizedActionIDs(
        from trace: XcircuiteSymbolicPlannerTrace
    ) -> [String] {
        let actionIDs = trace.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.compactMap { actionTrace in
                actionTrace.scoreComponents.contains {
                    $0.termID.hasPrefix("feedback.") && $0.contribution < 0
                } ? actionTrace.actionID : nil
            }
        }
        return Self.uniquePreservingOrder(actionIDs)
    }
    
    static func selectedActionDomainIDs(
        from trace: XcircuiteSymbolicPlannerTrace
    ) -> [String] {
        let domainIDs = trace.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.compactMap { actionTrace in
                actionTrace.selected ? actionTrace.domainID : nil
            }
        }
        return Self.uniquePreservingOrder(domainIDs)
    }
    
    static func selectedObjectiveDomainIDs(
        from trace: XcircuiteSymbolicPlannerTrace,
        problem: XcircuiteCircuitPlanningProblem
    ) -> [String] {
        let domainsByObjectiveID = Dictionary(
            uniqueKeysWithValues: problem.objectives.map { ($0.objectiveID, $0.domain) }
        )
        let objectiveIDs = trace.objectiveTraces.compactMap { objectiveTrace in
            objectiveTrace.selectedActionID == nil ? nil : objectiveTrace.objectiveID
        }
        return Self.uniquePreservingOrder(objectiveIDs.compactMap { domainsByObjectiveID[$0] })
    }
    
    static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
    
    static func feedbackRankChanges(
        from trace: XcircuiteSymbolicPlannerTrace
    ) -> [String] {
        let changes: [String] = trace.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.compactMap { actionTrace in
                guard actionTrace.rejectedFeedbackRankDelta != 0 else {
                    return nil
                }
                return "\(actionTrace.actionID):\(actionTrace.rankBeforeRejectedFeedback)->\(actionTrace.rank)"
            }
        }
        return Self.uniquePreservingOrder(changes)
    }
    
    static func feedbackScoreDeltas(
        from trace: XcircuiteSymbolicPlannerTrace
    ) -> [String] {
        let deltas: [String] = trace.objectiveTraces.flatMap { objectiveTrace in
            objectiveTrace.candidateActions.compactMap { actionTrace in
                guard actionTrace.rejectedFeedbackScoreDelta != 0 else {
                    return nil
                }
                return "\(actionTrace.actionID):\(actionTrace.rejectedFeedbackScoreDelta)"
            }
        }
        return Self.uniquePreservingOrder(deltas)
    }
    
    static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
    
    static func encodedJSONData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
    
    static func writeRunJSONArtifact(
        _ data: Data,
        path: String,
        artifactID: String,
        root: URL,
        runID: String
    ) async throws -> ArtifactReference {
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        return try await store.persistArtifact(
            content: data,
            id: try ArtifactID(rawValue: artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: .other,
                format: .json
            ),
            runID: runID,
            mode: .replaceable
        )
    }
    
    static func projectSource(_ relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = projectRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
    
    static func reviewVerificationDesignSpec() -> DesignFlowDesignSpec {
        DesignFlowDesignSpec(
            name: "review-verification-divider",
            title: "Review verification divider",
            components: [
                DesignFlowDesignSpec.Component(
                    name: "V1",
                    deviceKindID: "vsource",
                    parameters: ["dc": 5.0]
                ),
                DesignFlowDesignSpec.Component(
                    name: "R1",
                    deviceKindID: "resistor",
                    parameters: ["r": 1_000]
                ),
                DesignFlowDesignSpec.Component(
                    name: "R2",
                    deviceKindID: "resistor",
                    parameters: ["r": 1_000]
                ),
                DesignFlowDesignSpec.Component(
                    name: "GND1",
                    deviceKindID: "ground"
                ),
            ],
            nets: [
                DesignFlowDesignSpec.Net(
                    name: "vin",
                    terminals: [
                        DesignFlowDesignSpec.Terminal(component: "V1", port: "pos"),
                        DesignFlowDesignSpec.Terminal(component: "R1", port: "pos"),
                    ]
                ),
                DesignFlowDesignSpec.Net(
                    name: "out",
                    terminals: [
                        DesignFlowDesignSpec.Terminal(component: "R1", port: "neg"),
                        DesignFlowDesignSpec.Terminal(component: "R2", port: "pos"),
                    ]
                ),
                DesignFlowDesignSpec.Net(
                    name: "0",
                    terminals: [
                        DesignFlowDesignSpec.Terminal(component: "V1", port: "neg"),
                        DesignFlowDesignSpec.Terminal(component: "R2", port: "neg"),
                        DesignFlowDesignSpec.Terminal(component: "GND1", port: "gnd"),
                    ]
                ),
            ],
            analyses: [
                DesignFlowDesignSpec.Analysis(kind: .op),
            ]
        )
    }
    
    static func removeTemporaryRoot(_ root: URL) {
        let path = root.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }
    
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}
