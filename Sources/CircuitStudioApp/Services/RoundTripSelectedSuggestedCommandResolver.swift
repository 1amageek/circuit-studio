import Foundation
import DesignFlowKernel

public struct RoundTripSelectedSuggestedCommandResolutionRequest: Sendable, Hashable, Codable {
    public let runID: String
    public let commandID: String?

    public init(runID: String, commandID: String? = nil) {
        self.runID = runID
        self.commandID = commandID
    }
}

public struct RoundTripResolvedSuggestedCommand: Sendable, Hashable, Codable {
    public let selection: XcircuiteSuggestedCommandSelection
    public let command: DesignFlowCommand

    public init(
        selection: XcircuiteSuggestedCommandSelection,
        command: DesignFlowCommand
    ) {
        self.selection = selection
        self.command = command
    }
}

public enum RoundTripSelectedSuggestedCommandResolutionError: Error, LocalizedError, Equatable {
    case noSelection(runID: String, commandID: String?)
    case unsupportedExecutable(String)
    case unsupportedReadiness(String)
    case missingRunnerPrefix(commandID: String)
    case unsupportedCommand(String)
    case unsupportedArguments(commandID: String, arguments: [String])
    case mismatchedRunID(expected: String, actual: String)
    case mismatchedProjectRoot(expected: String, actual: String)
    case missingRequiredOption(commandID: String, option: String)
    case invalidRunID(String)

    public var errorDescription: String? {
        switch self {
        case .noSelection(let runID, let commandID):
            if let commandID {
                return "No selected round-trip suggested command '\(commandID)' exists for run '\(runID)'."
            }
            return "No selected round-trip suggested command exists for run '\(runID)'."
        case .unsupportedExecutable(let executable):
            return "Selected round-trip suggested command executable is not supported: \(executable)"
        case .unsupportedReadiness(let readiness):
            return "Selected round-trip suggested command is not ready: \(readiness)"
        case .missingRunnerPrefix(let commandID):
            return "Selected round-trip suggested command '\(commandID)' does not target circuit-studio-flow-runner."
        case .unsupportedCommand(let command):
            return "Selected round-trip suggested command is not allowlisted: \(command)"
        case .unsupportedArguments(let commandID, let arguments):
            return "Selected round-trip suggested command '\(commandID)' has unsupported arguments: \(arguments.joined(separator: " "))"
        case .mismatchedRunID(let expected, let actual):
            return "Selected round-trip suggested command run ID '\(actual)' does not match expected run ID '\(expected)'."
        case .mismatchedProjectRoot(let expected, let actual):
            return "Selected round-trip suggested command project root '\(actual)' does not match expected project root '\(expected)'."
        case .missingRequiredOption(let commandID, let option):
            return "Selected round-trip suggested command '\(commandID)' is missing required option \(option)."
        case .invalidRunID(let runID):
            return "Invalid run ID for selected round-trip suggested command: \(runID)"
        }
    }
}

public struct RoundTripSelectedSuggestedCommandResolver: Sendable {
    private let actionLogService: RoundTripActionLogService

    public init(actionLogService: RoundTripActionLogService = RoundTripActionLogService()) {
        self.actionLogService = actionLogService
    }

    public func resolve(
        request: RoundTripSelectedSuggestedCommandResolutionRequest,
        projectRoot: URL
    ) throws -> RoundTripResolvedSuggestedCommand {
        try validateRunID(request.runID)
        let manifestURL = try RoundTripRunDirectory.manifestURL(
            projectRoot: projectRoot,
            runID: request.runID
        )
        let selection = try selectedCommand(
            runID: request.runID,
            commandID: request.commandID,
            manifestURL: manifestURL
        )
        try validate(selection: selection, request: request)
        let runnerArguments = try flowRunnerArguments(from: selection)
        let command = try commandFromRunnerArguments(
            runnerArguments,
            selection: selection,
            request: request,
            projectRoot: projectRoot,
            manifestURL: manifestURL
        )
        return RoundTripResolvedSuggestedCommand(selection: selection, command: command)
    }

    private func selectedCommand(
        runID: String,
        commandID: String?,
        manifestURL: URL
    ) throws -> XcircuiteSuggestedCommandSelection {
        let selections = try actionLogService.loadSuggestedCommandSelections(manifestURL: manifestURL)
        let matching = selections.filter { selection in
            guard selection.status == .succeeded else {
                return false
            }
            guard let commandID else {
                return true
            }
            return selection.commandID == commandID
        }
        guard let selection = matching.last else {
            throw RoundTripSelectedSuggestedCommandResolutionError.noSelection(
                runID: runID,
                commandID: commandID
            )
        }
        return selection
    }

    private func validate(
        selection: XcircuiteSuggestedCommandSelection,
        request: RoundTripSelectedSuggestedCommandResolutionRequest
    ) throws {
        guard selection.executable == "swift" else {
            throw RoundTripSelectedSuggestedCommandResolutionError.unsupportedExecutable(
                selection.executable
            )
        }
        guard selection.readiness == "ready" else {
            throw RoundTripSelectedSuggestedCommandResolutionError.unsupportedReadiness(
                selection.readiness
            )
        }
        guard selection.runID == request.runID else {
            throw RoundTripSelectedSuggestedCommandResolutionError.mismatchedRunID(
                expected: request.runID,
                actual: selection.runID
            )
        }
    }

    private func flowRunnerArguments(
        from selection: XcircuiteSuggestedCommandSelection
    ) throws -> [String] {
        let arguments = selection.arguments
        guard arguments.first == "run" else {
            throw RoundTripSelectedSuggestedCommandResolutionError.missingRunnerPrefix(
                commandID: selection.commandID
            )
        }

        var executableIndex = 1
        if arguments.indices.contains(executableIndex),
           arguments[executableIndex] == "--quiet" {
            executableIndex += 1
        }
        guard arguments.indices.contains(executableIndex),
              arguments[executableIndex] == "circuit-studio-flow-runner" else {
            throw RoundTripSelectedSuggestedCommandResolutionError.missingRunnerPrefix(
                commandID: selection.commandID
            )
        }
        return Array(arguments.dropFirst(executableIndex + 1))
    }

    private func commandFromRunnerArguments(
        _ runnerArguments: [String],
        selection: XcircuiteSuggestedCommandSelection,
        request: RoundTripSelectedSuggestedCommandResolutionRequest,
        projectRoot: URL,
        manifestURL: URL
    ) throws -> DesignFlowCommand {
        let options = try FlowRunnerCommandOptions(arguments: runnerArguments)
        switch options.mode {
        case .reviewRoundTrip:
            return try reviewRoundTripCommand(
                options: options,
                selection: selection,
                manifestURL: manifestURL
            )
        case .summarizeBottlenecks,
             .summarizeSignoffRepairCandidateCycles,
             .qualifySignoffRepairCandidateCycles:
            return try projectRootCommand(
                options: options,
                selection: selection,
                projectRoot: projectRoot
            )
        default:
            throw RoundTripSelectedSuggestedCommandResolutionError.unsupportedCommand(
                String(describing: options.mode)
            )
        }
    }

    private func reviewRoundTripCommand(
        options: FlowRunnerCommandOptions,
        selection: XcircuiteSuggestedCommandSelection,
        manifestURL: URL
    ) throws -> DesignFlowCommand {
        guard let reviewManifestURL = options.reviewManifestURL else {
            throw RoundTripSelectedSuggestedCommandResolutionError.missingRequiredOption(
                commandID: selection.commandID,
                option: "--manifest"
            )
        }
        let expected = normalizedPath(manifestURL)
        let actual = normalizedPath(reviewManifestURL)
        guard expected == actual else {
            throw RoundTripSelectedSuggestedCommandResolutionError.unsupportedArguments(
                commandID: selection.commandID,
                arguments: selection.arguments
            )
        }
        return options.makeCommand()
    }

    private func projectRootCommand(
        options: FlowRunnerCommandOptions,
        selection: XcircuiteSuggestedCommandSelection,
        projectRoot: URL
    ) throws -> DesignFlowCommand {
        guard options.outputURL != nil else {
            throw RoundTripSelectedSuggestedCommandResolutionError.missingRequiredOption(
                commandID: selection.commandID,
                option: "--output"
            )
        }
        guard let projectRootPath = options.projectRootPath else {
            throw RoundTripSelectedSuggestedCommandResolutionError.missingRequiredOption(
                commandID: selection.commandID,
                option: "--output"
            )
        }
        let expected = normalizedPath(projectRoot)
        let actual = normalizedPath(URL(filePath: projectRootPath))
        guard expected == actual else {
            throw RoundTripSelectedSuggestedCommandResolutionError.mismatchedProjectRoot(
                expected: expected,
                actual: actual
            )
        }
        return options.makeCommand()
    }

    private func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
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
            throw RoundTripSelectedSuggestedCommandResolutionError.invalidRunID(runID)
        }
    }
}
