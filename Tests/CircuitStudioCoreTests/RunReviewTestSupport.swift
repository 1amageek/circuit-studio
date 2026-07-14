import Foundation
import Testing
import CircuiteFoundation
import DesignFlowKernel
import LayoutCore
import ToolQualification
import Xcircuite
import DesignFlowKernel
@testable import CircuitStudioApp
@testable import CircuitStudioCore

struct RunReviewPassingExecutor: FlowStageExecutor {
    let stageID: String
    let toolID = "stub-tool"
    var artifacts: [XcircuiteFileReference] = []
    var artifactPayloads: [String: Data] = [:]

    func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        var resolvedArtifacts = artifacts
        for index in resolvedArtifacts.indices {
            let path = resolvedArtifacts[index].path
            guard let payload = artifactPayloads[path] else {
                continue
            }
            let url = context.projectRoot.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try payload.write(to: url, options: .atomic)
            resolvedArtifacts[index].sha256 = XcircuiteHasher().sha256(data: payload)
            resolvedArtifacts[index].byteCount = Int64(payload.count)
        }

        let canonicalArtifacts = try resolvedArtifacts.map(
            RunReviewTestSupport.foundationArtifactReference(from:)
        )
        return FlowStageResult(
            stageID: stage.stageID,
            status: .succeeded,
            gates: [FlowGateResult(gateID: "drc", status: .passed)],
            artifacts: canonicalArtifacts
        )
    }
}

enum RunReviewTestSupportError: Error {
    case invalidArtifactReference(String)
}

enum RunReviewTestSupport {
    static func foundationArtifactReference(
        from value: XcircuiteFileReference
    ) throws -> ArtifactReference {
        if let canonical = FoundationArtifactTypeProjection.reference(value) {
            return canonical
        }
        guard let kind = FoundationArtifactTypeProjection.kind(value.kind),
              let format = FoundationArtifactTypeProjection.format(value.format) else {
            throw RunReviewTestSupportError.invalidArtifactReference(value.path)
        }
        return try foundationArtifactReference(
            artifactID: value.artifactID ?? "derived-\(value.path.hashValue)",
            path: value.path,
            kind: kind,
            format: format,
            byteCount: value.byteCount.map { max(0, $0) } ?? 0
        )
    }

    static func foundationArtifactReference(
        artifactID: String,
        path: String,
        kind: ArtifactKind = .report,
        format: ArtifactFormat = .json,
        byteCount: Int64 = 0
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
            byteCount: UInt64(byteCount)
        )
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
    ) throws -> ArtifactReference {
        try FileManager.default.createDirectory(
            at: root.appending(path: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: root.appending(path: path), options: .atomic)
        let reference = try XcircuiteWorkspaceStore().makeArtifactReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            role: .output,
            kind: .other,
            format: .json,
            inProjectAt: root,
            producedByRunID: runID,
            verifiedByRunID: nil
        )
        try XcircuiteWorkspaceStore().registerArtifact(reference, runID: runID, inProjectAt: root)
        return reference
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
