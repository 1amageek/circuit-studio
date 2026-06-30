import Foundation
import DesignFlowKernel

public enum FlowRunnerFailureEnvelopeBuilder {
    public static func usage(error: Error) -> FlowRunnerFailureEnvelope {
        FlowRunnerFailureEnvelope(
            errorKind: "usage",
            errorType: errorType(error),
            message: error.localizedDescription,
            helpHint: "swift run circuit-studio-flow-runner --help",
            recommendation: "Fix the command inputs and rerun. Use --help only when you need the option reference.",
            nextActions: [
                FlowRunNextAction(
                    actionID: "show-flow-runner-help",
                    kind: "showFlowRunnerHelp",
                    severity: .error,
                    reason: "Inspect the command reference before rerunning.",
                    diagnosticCodes: ["usage"],
                    suggestedCommands: [
                        FlowRunSuggestedCommand(
                            commandID: "circuit-studio-flow-runner.help",
                            readiness: .ready,
                            executable: "swift",
                            arguments: ["run", "--quiet", "circuit-studio-flow-runner", "--help"],
                            reason: "Show flow runner usage and supported modes."
                        ),
                    ]
                ),
            ]
        )
    }

    public static func runtime(error: Error, options: FlowRunnerCommandOptions) -> FlowRunnerFailureEnvelope {
        let manifestURL = candidateManifestURL(from: options)
        let manifestInspection = manifestURL.map(inspectManifest(at:)) ?? ManifestInspection()
        let manifestPath = manifestURL?.path(percentEncoded: false)
        let projectRoot = options.projectRootPath
        return FlowRunnerFailureEnvelope(
            errorKind: runtimeErrorKind(error),
            errorType: errorType(error),
            message: error.localizedDescription,
            runID: options.runID,
            projectRoot: projectRoot,
            manifest: manifestPath,
            stage: manifestInspection.failedStage,
            manifestInspectionError: manifestInspection.error,
            recommendation: recommendation(for: error, manifestURL: manifestURL, manifestInspection: manifestInspection),
            nextActions: runtimeNextActions(
                error: error,
                projectRoot: projectRoot,
                manifestPath: manifestPath,
                failedStage: manifestInspection.failedStage,
                manifestInspectionError: manifestInspection.error
            )
        )
    }

    public static func runtimeErrorKind(_ error: Error) -> String {
        if error is DesignFlowCommandError {
            return "command_validation"
        }
        return "runtime"
    }

    public static func errorType(_ error: Error) -> String {
        String(describing: type(of: error))
    }

    public static func candidateManifestURL(from options: FlowRunnerCommandOptions) -> URL? {
        if let reviewManifestURL = options.reviewManifestURL {
            return reviewManifestURL
        }
        guard let runID = options.runID,
              let projectRoot = options.projectRootPath else {
            return nil
        }
        let manifestURL = URL(filePath: projectRoot)
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: runID)
            .appending(path: "round-trip-manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
            return nil
        }
        return manifestURL
    }

    public static func inspectManifest(at manifestURL: URL) -> ManifestInspection {
        do {
            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(HeadlessRoundTripService.Manifest.self, from: data)
            return ManifestInspection(
                failedStage: manifest.stages.first { $0.status == .failed }?.name
                    ?? manifest.bottleneckSummary?.failedStageName
            )
        } catch {
            return ManifestInspection(
                error: "Failed to inspect manifest '\(manifestURL.path(percentEncoded: false))': \(error.localizedDescription)"
            )
        }
    }

    public static func recommendation(
        for error: Error,
        manifestURL: URL?,
        manifestInspection: ManifestInspection
    ) -> String {
        let description = error.localizedDescription
        if description.contains("Post-layout comparison exceeded configured limits") {
            return "Inspect post-layout-comparison.json and adjust the design or comparison limits."
        }
        if error is DesignFlowCommandError {
            return "Fix the command inputs and rerun. Use --help only when you need the option reference."
        }
        if let inspectionError = manifestInspection.error {
            return "\(inspectionError) Repair or regenerate the manifest before relying on persisted stage evidence."
        }
        if manifestURL != nil {
            return "Inspect the manifest and stage artifacts for the structured failure evidence."
        }
        return "Rerun with an explicit --output and --run-id to preserve inspectable run artifacts."
    }

    private static func runtimeNextActions(
        error: Error,
        projectRoot: String?,
        manifestPath: String?,
        failedStage: String?,
        manifestInspectionError: String?
    ) -> [FlowRunNextAction] {
        if let manifestPath {
            let diagnosticCodes = manifestInspectionError == nil ? ["runtime"] : ["runtime", "manifest_unreadable"]
            var suggestedCommands = [
                FlowRunSuggestedCommand(
                    commandID: "circuit-studio-flow-runner.review-round-trip",
                    readiness: .ready,
                    executable: "swift",
                    arguments: [
                        "run",
                        "--quiet",
                        "circuit-studio-flow-runner",
                        "--review-round-trip",
                        "--manifest",
                        manifestPath,
                        "--json",
                    ],
                    reason: "Load the failed run review from its persisted manifest."
                ),
            ]
            if let projectRoot {
                suggestedCommands.append(FlowRunSuggestedCommand(
                    commandID: "circuit-studio-flow-runner.summarize-bottlenecks",
                    readiness: .ready,
                    executable: "swift",
                    arguments: [
                        "run",
                        "--quiet",
                        "circuit-studio-flow-runner",
                        "--summarize-bottlenecks",
                        "--output",
                        projectRoot,
                        "--json",
                    ],
                    reason: "Summarize failed and expensive stages across saved flow manifests."
                ))
            }
            return [
                FlowRunNextAction(
                    actionID: "review-flow-runner-failure",
                    kind: "reviewFlowRunnerFailure",
                    stageID: failedStage,
                    severity: .error,
                    reason: "Inspect the failed stage and persisted artifacts before planning a repair.",
                    diagnosticCodes: diagnosticCodes,
                    suggestedCommands: suggestedCommands
                ),
            ]
        }

        if error is DesignFlowCommandError {
            return [
                FlowRunNextAction(
                    actionID: "fix-flow-runner-command-inputs",
                    kind: "fixFlowRunnerCommandInputs",
                    severity: .error,
                    reason: "The command is missing required inputs or has inconsistent options.",
                    diagnosticCodes: ["command_validation"],
                    suggestedCommands: [
                        FlowRunSuggestedCommand(
                            commandID: "circuit-studio-flow-runner.help",
                            readiness: .ready,
                            executable: "swift",
                            arguments: ["run", "--quiet", "circuit-studio-flow-runner", "--help"],
                            reason: "Show flow runner usage and required options."
                        ),
                    ]
                ),
            ]
        }

        return [
            FlowRunNextAction(
                actionID: "rerun-with-preserved-artifacts",
                kind: "rerunWithPreservedArtifacts",
                severity: .warning,
                reason: "Rerun with explicit output and run ID so failure artifacts can be inspected.",
                diagnosticCodes: ["missing_manifest"],
                suggestedCommands: []
            ),
        ]
    }

    public struct ManifestInspection: Sendable, Hashable {
        public let failedStage: String?
        public let error: String?

        public init(failedStage: String? = nil, error: String? = nil) {
            self.failedStage = failedStage
            self.error = error
        }
    }
}
