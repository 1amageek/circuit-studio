import Foundation
import DesignFlowKernel
import XcircuitePackage

public enum RoundTripActionLogServiceError: Error, LocalizedError, Equatable {
    case missingRunID
    case missingManifestPath
    case missingReviewer
    case missingCommandID
    case missingManifest(URL)
    case missingRunDirectory(URL)
    case manifestRunMismatch(expected: String, actual: String)
    case manifestPathMismatch(expected: String, actual: String)
    case nextActionNotFound(actionID: String)
    case suggestedCommandNotFound(commandID: String)
    case writeFailed(String)
    case readFailed(String)
    case decodeFailed(String)
    case encodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingRunID:
            return "Round-trip action log selection requires a run ID."
        case .missingManifestPath:
            return "Round-trip action log selection requires a manifest path."
        case .missingReviewer:
            return "Round-trip action log selection requires a reviewer."
        case .missingCommandID:
            return "Round-trip action log selection requires a command ID."
        case .missingManifest(let url):
            return "Round-trip manifest does not exist: \(url.path(percentEncoded: false))"
        case .missingRunDirectory(let url):
            return "Round-trip run directory does not exist: \(url.path(percentEncoded: false))"
        case .manifestRunMismatch(let expected, let actual):
            return "Round-trip manifest run ID '\(actual)' does not match expected run ID '\(expected)'."
        case .manifestPathMismatch(let expected, let actual):
            return "Round-trip manifest path '\(actual)' does not match expected path '\(expected)'."
        case .nextActionNotFound(let actionID):
            return "Round-trip failure envelope does not contain next action '\(actionID)'."
        case .suggestedCommandNotFound(let commandID):
            return "Round-trip failure envelope does not contain suggested command '\(commandID)'."
        case .writeFailed(let message):
            return "Failed to write round-trip action log: \(message)"
        case .readFailed(let message):
            return "Failed to read round-trip action log: \(message)"
        case .decodeFailed(let message):
            return "Failed to decode round-trip action log: \(message)"
        case .encodeFailed(let message):
            return "Failed to encode round-trip action log: \(message)"
        }
    }
}

public struct RoundTripActionLogService: Sendable {
    public init() {}

    public func loadSuggestedCommandSelections(
        manifestURL: URL
    ) throws -> [XcircuiteSuggestedCommandSelection] {
        let actionsURL = actionLogURL(forManifestAt: manifestURL)
        guard fileExists(actionsURL) else {
            return []
        }

        let text: String
        do {
            text = try String(contentsOf: actionsURL, encoding: .utf8)
        } catch {
            throw RoundTripActionLogServiceError.readFailed(
                "\(actionsURL.lastPathComponent): \(error.localizedDescription)"
            )
        }

        let decoder = JSONDecoder()
        var selections: [XcircuiteSuggestedCommandSelection] = []
        for line in text.split(separator: "\n") {
            do {
                let record = try decoder.decode(XcircuiteRunActionRecord.self, from: Data(line.utf8))
                if let selection = try XcircuiteSuggestedCommandSelection(record: record) {
                    selections.append(selection)
                }
            } catch {
                throw RoundTripActionLogServiceError.decodeFailed(
                    "\(actionsURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }
        return selections
    }

    @discardableResult
    public func recordSuggestedCommandSelection(
        from failure: FlowRunnerFailureEnvelope,
        commandID: String,
        reviewer: String
    ) throws -> XcircuiteRunActionRecord {
        guard let runID = failure.runID else {
            throw RoundTripActionLogServiceError.missingRunID
        }
        guard let manifestPath = failure.manifest else {
            throw RoundTripActionLogServiceError.missingManifestPath
        }
        guard !reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RoundTripActionLogServiceError.missingReviewer
        }
        guard !commandID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RoundTripActionLogServiceError.missingCommandID
        }

        let manifestURL = URL(filePath: manifestPath)
        let manifest = try loadManifest(manifestURL)
        guard manifest.runID == runID else {
            throw RoundTripActionLogServiceError.manifestRunMismatch(
                expected: runID,
                actual: manifest.runID
            )
        }
        if let projectRoot = failure.projectRoot {
            try validateManifestURL(manifestURL, projectRootPath: projectRoot, runID: runID)
        }

        let nextAction = try nextAction(containingCommandID: commandID, in: failure)
        guard let command = nextAction.suggestedCommands.first(where: { $0.commandID == commandID }) else {
            throw RoundTripActionLogServiceError.suggestedCommandNotFound(commandID: commandID)
        }

        let record = XcircuiteRunActionRecord(
            actionID: "round-trip-suggested-command-selection-\(UUID().uuidString)",
            runID: runID,
            stageID: nextAction.stageID,
            actor: XcircuiteRunActionActor(kind: .human, identifier: reviewer),
            actionKind: XcircuiteSuggestedCommandSelection.actionKind,
            status: .succeeded,
            metadata: [
                "sourceKind": .string(FlowRunnerFailureEnvelope.envelopeKind),
                "nextActionID": .string(nextAction.actionID),
                "nextActionKind": .string(nextAction.kind),
                "commandID": .string(command.commandID),
                "readiness": .string(command.readiness.rawValue),
                "executable": .string(command.executable),
                "arguments": .array(command.arguments.map { .string($0) }),
                "reason": .string(command.reason),
                "failureErrorKind": .string(failure.errorKind),
                "failureErrorType": .string(failure.errorType),
                "failureStage": failure.stage.map { .string($0) } ?? .null,
                "manifest": .string(manifestPath),
            ]
        )
        try append(record, manifestURL: manifestURL)
        return record
    }

    public func actionLogPath(manifestURL: URL) -> String {
        actionLogURL(forManifestAt: manifestURL).path(percentEncoded: false)
    }

    private func nextAction(
        containingCommandID commandID: String,
        in failure: FlowRunnerFailureEnvelope
    ) throws -> FlowRunNextAction {
        guard let nextAction = failure.nextActions.first(where: { action in
            action.suggestedCommands.contains { $0.commandID == commandID }
        }) else {
            throw RoundTripActionLogServiceError.suggestedCommandNotFound(commandID: commandID)
        }
        return nextAction
    }

    private func append(_ record: XcircuiteRunActionRecord, manifestURL: URL) throws {
        let runDirectory = manifestURL.deletingLastPathComponent()
        guard directoryExists(runDirectory) else {
            throw RoundTripActionLogServiceError.missingRunDirectory(runDirectory)
        }

        let actionsURL = actionLogURL(forManifestAt: manifestURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(record)
        } catch {
            throw RoundTripActionLogServiceError.encodeFailed(error.localizedDescription)
        }

        var line = data
        line.append(0x0A)
        do {
            if fileExists(actionsURL) {
                let handle = try FileHandle(forWritingTo: actionsURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: actionsURL, options: .atomic)
            }
        } catch {
            throw RoundTripActionLogServiceError.writeFailed(error.localizedDescription)
        }
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

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }

    private func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }
}
