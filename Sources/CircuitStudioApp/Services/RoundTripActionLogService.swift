import Foundation
import DesignFlowKernel
import Xcircuite

public enum RoundTripActionLogServiceError: Error, LocalizedError, Equatable {
    case missingRunID
    case missingManifestPath
    case missingReviewer
    case missingSuggestedActionID
    case missingManifest(URL)
    case missingProjectRoot
    case manifestRunMismatch(expected: String, actual: String)
    case manifestPathMismatch(expected: String, actual: String)
    case nextActionNotFound(actionID: String)
    case suggestedActionNotFound(actionID: String)
    case decodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingRunID:
            return "Round-trip action log selection requires a run ID."
        case .missingManifestPath:
            return "Round-trip action log selection requires a manifest path."
        case .missingReviewer:
            return "Round-trip action log selection requires a reviewer."
        case .missingSuggestedActionID:
            return "Round-trip action log selection requires a suggested action ID."
        case .missingManifest(let url):
            return "Round-trip manifest does not exist: \(url.path(percentEncoded: false))"
        case .missingProjectRoot:
            return "Round-trip action selection requires a project root."
        case .manifestRunMismatch(let expected, let actual):
            return "Round-trip manifest run ID '\(actual)' does not match expected run ID '\(expected)'."
        case .manifestPathMismatch(let expected, let actual):
            return "Round-trip manifest path '\(actual)' does not match expected path '\(expected)'."
        case .nextActionNotFound(let actionID):
            return "Round-trip failure envelope does not contain next action '\(actionID)'."
        case .suggestedActionNotFound(let actionID):
            return "Round-trip failure envelope does not contain suggested action '\(actionID)'."
        case .decodeFailed(let message):
            return "Failed to decode round-trip action log: \(message)"
        }
    }
}

public struct RoundTripActionLogService: Sendable {
    public init() {}

    public func loadSuggestedActionSelections(
        manifestURL: URL
    ) async throws -> [FlowRunSuggestedActionSelection] {
        let manifest = try loadManifest(manifestURL)
        let projectRoot = manifestURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        return try await store.loadSuggestedActionSelections(runID: manifest.runID)
    }

    @discardableResult
    public func recordSuggestedActionSelection(
        from failure: FlowRunnerFailureEnvelope,
        actionID: String,
        reviewer: String
    ) async throws -> FlowRunActionRecord {
        guard let runID = failure.runID else {
            throw RoundTripActionLogServiceError.missingRunID
        }
        guard let manifestPath = failure.manifest else {
            throw RoundTripActionLogServiceError.missingManifestPath
        }
        guard let projectRootPath = failure.projectRoot else {
            throw RoundTripActionLogServiceError.missingProjectRoot
        }
        guard !reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RoundTripActionLogServiceError.missingReviewer
        }
        guard !actionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RoundTripActionLogServiceError.missingSuggestedActionID
        }

        let manifestURL = URL(filePath: manifestPath)
        let manifest = try loadManifest(manifestURL)
        guard manifest.runID == runID else {
            throw RoundTripActionLogServiceError.manifestRunMismatch(
                expected: runID,
                actual: manifest.runID
            )
        }
        try validateManifestURL(manifestURL, projectRootPath: projectRootPath, runID: runID)

        let nextAction = try nextAction(containingSuggestedActionID: actionID, in: failure)
        guard let action = nextAction.suggestedActions.first(where: { $0.id == actionID }) else {
            throw RoundTripActionLogServiceError.suggestedActionNotFound(actionID: actionID)
        }

        let record = FlowRunActionRecord(
            actionID: "round-trip-suggested-action-selection-\(UUID().uuidString)",
            runID: runID,
            stageID: nextAction.stageID,
            actor: FlowRunActor(kind: .human, identifier: reviewer),
            actionKind: FlowRunSuggestedActionSelection.actionKind,
            status: .succeeded,
            context: FlowRunActionContext(
                suggestedAction: FlowRunActionContext.SuggestedAction(
                    nextActionID: nextAction.actionID,
                    nextActionKind: nextAction.kind,
                    action: action
                )
            )
        )
        let store = try XcircuiteWorkspaceStore(projectRoot: URL(filePath: projectRootPath))
        try await store.appendRunAction(record)
        return record
    }

    public func actionLogPath(manifestURL: URL) -> String {
        actionLogURL(forManifestAt: manifestURL).path(percentEncoded: false)
    }

    private func nextAction(
        containingSuggestedActionID actionID: String,
        in failure: FlowRunnerFailureEnvelope
    ) throws -> FlowRunNextAction {
        guard let nextAction = failure.nextActions.first(where: { action in
            action.suggestedActions.contains { $0.id == actionID }
        }) else {
            throw RoundTripActionLogServiceError.suggestedActionNotFound(actionID: actionID)
        }
        return nextAction
    }

    private func validateManifestURL(
        _ manifestURL: URL,
        projectRootPath: String,
        runID: String
    ) throws {
        let expectedURL = try RoundTripRunDirectory.manifestURL(
            projectRoot: URL(filePath: projectRootPath),
            runID: runID
        )
        let expected = normalizedPath(expectedURL)
        let actual = normalizedPath(manifestURL)
        guard expected == actual else {
            throw RoundTripActionLogServiceError.manifestPathMismatch(
                expected: expected,
                actual: actual
            )
        }
    }

    private func loadManifest(_ url: URL) throws -> HeadlessRoundTripService.Manifest {
        guard fileExists(url) else {
            throw RoundTripActionLogServiceError.missingManifest(url)
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(HeadlessRoundTripService.Manifest.self, from: data)
        } catch {
            throw RoundTripActionLogServiceError.decodeFailed(
                "\(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    private func actionLogURL(forManifestAt manifestURL: URL) -> URL {
        manifestURL.deletingLastPathComponent().appending(path: "actions.jsonl")
    }

    private func fileExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
    }

    private func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }
}
