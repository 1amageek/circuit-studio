import DesignFlowKernel
import Foundation

public struct RoundTripSelectedSuggestedActionResolutionRequest: Sendable, Hashable, Codable {
    public let runID: String
    public let actionID: String?

    public init(runID: String, actionID: String? = nil) {
        self.runID = runID
        self.actionID = actionID
    }
}

public struct RoundTripResolvedSuggestedAction: Sendable, Hashable, Codable {
    public let selection: FlowRunSuggestedActionSelection
    public let command: DesignFlowCommand

    public init(
        selection: FlowRunSuggestedActionSelection,
        command: DesignFlowCommand
    ) {
        self.selection = selection
        self.command = command
    }
}

public enum RoundTripSelectedSuggestedActionResolutionError: Error, LocalizedError, Equatable {
    case noSelection(runID: String, actionID: String?)
    case actionRequiresInput(String)
    case unsupportedOperation(String)
    case mismatchedRunID(expected: String, actual: String)
    case invalidRunID(String)

    public var errorDescription: String? {
        switch self {
        case .noSelection(let runID, let actionID):
            if let actionID {
                return "No selected round-trip suggested action '\(actionID)' exists for run '\(runID)'."
            }
            return "No selected round-trip suggested action exists for run '\(runID)'."
        case .actionRequiresInput(let actionID):
            return "Selected round-trip suggested action '\(actionID)' requires additional input."
        case .unsupportedOperation(let operation):
            return "Selected round-trip suggested operation is not supported by circuit-studio: \(operation)"
        case .mismatchedRunID(let expected, let actual):
            return "Selected round-trip suggested action run ID '\(actual)' does not match expected run ID '\(expected)'."
        case .invalidRunID(let runID):
            return "Invalid run ID for selected round-trip suggested action: \(runID)"
        }
    }
}

public struct RoundTripSelectedSuggestedActionResolver: Sendable {
    private let actionLogService: RoundTripActionLogService

    public init(actionLogService: RoundTripActionLogService = RoundTripActionLogService()) {
        self.actionLogService = actionLogService
    }

    public func resolve(
        request: RoundTripSelectedSuggestedActionResolutionRequest,
        projectRoot: URL
    ) async throws -> RoundTripResolvedSuggestedAction {
        try validateRunID(request.runID)
        let manifestURL = try RoundTripRunDirectory.manifestURL(
            projectRoot: projectRoot,
            runID: request.runID
        )
        let selection = try await selectedAction(
            runID: request.runID,
            actionID: request.actionID,
            manifestURL: manifestURL
        )
        try validate(selection: selection, request: request)
        return RoundTripResolvedSuggestedAction(
            selection: selection,
            command: try command(
                for: selection.action.operation,
                runID: request.runID,
                projectRoot: projectRoot,
                manifestURL: manifestURL
            )
        )
    }

    private func selectedAction(
        runID: String,
        actionID: String?,
        manifestURL: URL
    ) async throws -> FlowRunSuggestedActionSelection {
        let selections = try await actionLogService.loadSuggestedActionSelections(manifestURL: manifestURL)
        let matching = selections.filter { selection in
            guard selection.status == .succeeded else {
                return false
            }
            guard let actionID else {
                return true
            }
            return selection.action.id == actionID
        }
        guard let selection = matching.last else {
            throw RoundTripSelectedSuggestedActionResolutionError.noSelection(
                runID: runID,
                actionID: actionID
            )
        }
        return selection
    }

    private func validate(
        selection: FlowRunSuggestedActionSelection,
        request: RoundTripSelectedSuggestedActionResolutionRequest
    ) throws {
        guard selection.action.readiness == .ready else {
            throw RoundTripSelectedSuggestedActionResolutionError.actionRequiresInput(
                selection.action.id
            )
        }
        guard selection.runID == request.runID else {
            throw RoundTripSelectedSuggestedActionResolutionError.mismatchedRunID(
                expected: request.runID,
                actual: selection.runID
            )
        }
        if let actionRunID = selection.action.runID,
           actionRunID != request.runID {
            throw RoundTripSelectedSuggestedActionResolutionError.mismatchedRunID(
                expected: request.runID,
                actual: actionRunID
            )
        }
    }

    private func command(
        for operation: FlowRunSuggestedOperation,
        runID: String,
        projectRoot: URL,
        manifestURL: URL
    ) throws -> DesignFlowCommand {
        switch operation {
        case .reviewRun, .inspectRun:
            return DesignFlowCommand(
                kind: .reviewRoundTrip,
                projectRootPath: projectRoot.path(percentEncoded: false),
                runID: runID,
                roundTripManifestPath: manifestURL.path(percentEncoded: false)
            )
        case .summarizeRunLoop:
            return DesignFlowCommand(
                kind: .summarizeBottlenecks,
                projectRootPath: projectRoot.path(percentEncoded: false),
                runID: runID
            )
        default:
            throw RoundTripSelectedSuggestedActionResolutionError.unsupportedOperation(
                String(describing: operation)
            )
        }
    }

    private func validateRunID(_ runID: String) throws {
        let allowedScalars = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
        )
        let isValid = !runID.isEmpty
            && runID != "."
            && runID != ".."
            && runID.unicodeScalars.allSatisfy { allowedScalars.contains($0) }
        guard isValid else {
            throw RoundTripSelectedSuggestedActionResolutionError.invalidRunID(runID)
        }
    }
}
