import Foundation
import CircuitStudioApp
import CircuitStudioCore

@main
struct CircuitStudioFlowRunner {
    static func main() async {
        do {
            let options = try RunnerOptions(arguments: Array(CommandLine.arguments.dropFirst()))
            if options.showHelp {
                Swift.print(Self.helpText)
                return
            }

            let designFlowService = DesignFlowService()
            let result = try await designFlowService.execute(command(from: options))
            print(result: result, options: options)
        } catch {
            fputs("flow_command=failed\n", stderr)
            fputs("error=\(error.localizedDescription)\n", stderr)
            fputs("\n\(Self.helpText)\n", stderr)
            exit(1)
        }
    }

    private static func command(from options: RunnerOptions) -> DesignFlowCommand {
        DesignFlowCommand(
            kind: options.commandKind,
            fixtureName: options.fixtureName,
            designSpecPath: options.designSpecURL?.path(percentEncoded: false),
            projectRootPath: projectRootPath(from: options),
            runID: options.runID,
            approveSignoff: options.approveSignoff,
            pexManifestPath: options.pexManifestURL?.path(percentEncoded: false),
            pexCornerID: options.pexCornerID,
            signoffDRCLogPath: options.signoffDRCLogURL?.path(percentEncoded: false),
            signoffLVSLogPath: options.signoffLVSLogURL?.path(percentEncoded: false),
            maxAbsoluteDelta: options.maxAbsoluteDelta,
            maxRelativeDelta: options.maxRelativeDelta,
            variableComparisonLimits: options.variableComparisonLimits,
            oscillationMetricLimits: options.oscillationMetricLimits,
            technologyPackagePath: options.technologyPackageURL?.path(percentEncoded: false),
            pexConfigPath: options.pexConfigURL?.path(percentEncoded: false),
            pexExecutablePath: options.pexExecutableURL?.path(percentEncoded: false),
            editScriptPath: options.editScriptURL?.path(percentEncoded: false),
            outputDesignSpecPath: options.outputDesignSpecURL?.path(percentEncoded: false),
            layoutDocumentPath: options.layoutDocumentURL?.path(percentEncoded: false),
            outputLayoutDocumentPath: options.outputLayoutDocumentURL?.path(percentEncoded: false),
            designUnitPath: options.designUnitURL?.path(percentEncoded: false),
            roundTripManifestPath: options.reviewManifestURL?.path(percentEncoded: false),
            approvalGateID: options.approvalGateID,
            approvalTargetPath: options.approvalTargetURL?.path(percentEncoded: false),
            approvalReviewer: options.approvalReviewer,
            approvalDecision: options.approvalDecision,
            approvalPolicy: options.approvalPolicy,
            approvalNote: options.approvalNote,
            waiverIDs: options.waiverIDs
        )
    }

    private static func projectRootPath(from options: RunnerOptions) -> String? {
        switch options.mode {
        case .listFixtures, .generateNetlist, .simulate, .loadTechnologyPackage, .runPEXExtraction:
            return nil
        case .applyDesignEdit, .applyLayoutEdit:
            return options.outputURL?.path(percentEncoded: false)
        case .runVerification, .approveGate:
            return options.outputURL?.path(percentEncoded: false)
        case .reviewRoundTrip:
            return options.outputURL?.path(percentEncoded: false)
        case .runRoundTrip:
            return (options.outputURL ?? defaultOutputURL(from: options))
                .path(percentEncoded: false)
        case .summarizeBottlenecks:
            return (options.outputURL ?? defaultOutputURL(from: options))
                .path(percentEncoded: false)
        }
    }

    private static func defaultOutputURL(from options: RunnerOptions) -> URL {
        let directoryName = options.designSpecURL?
            .deletingPathExtension()
            .lastPathComponent ?? options.fixtureName
        return URL(filePath: FileManager.default.currentDirectoryPath)
            .appending(path: "round-trip-runs")
            .appending(path: directoryName)
    }

    private static func print(result: DesignFlowCommandResult, options: RunnerOptions) {
        switch result.kind {
        case .listFixtures:
            for fixtureName in result.fixtureNames {
                Swift.print("fixture=\(fixtureName)")
            }
        case .generateFixtureNetlist:
            Swift.print("netlist=generated")
            printDesignOrFixture(result: result, options: options)
            Swift.print("netlist_begin")
            Swift.print(result.netlist ?? "")
            Swift.print("netlist_end")
        case .generateDesignNetlist:
            Swift.print("netlist=generated")
            printDesignOrFixture(result: result, options: options)
            Swift.print("netlist_begin")
            Swift.print(result.netlist ?? "")
            Swift.print("netlist_end")
        case .runFixtureSimulation:
            Swift.print("simulation=\(result.simulationStatus ?? "")")
            printDesignOrFixture(result: result, options: options)
            Swift.print("netlist_begin")
            Swift.print(result.netlist ?? "")
            Swift.print("netlist_end")
        case .runDesignSimulation:
            Swift.print("simulation=\(result.simulationStatus ?? "")")
            printDesignOrFixture(result: result, options: options)
            Swift.print("netlist_begin")
            Swift.print(result.netlist ?? "")
            Swift.print("netlist_end")
        case .runFixtureRoundTrip:
            Swift.print("round_trip=passed")
            printDesignOrFixture(result: result, options: options)
            Swift.print("run_id=\(result.runID ?? "")")
            Swift.print("project_root=\(result.projectRootPath ?? "")")
            Swift.print("manifest=\(result.manifestPath ?? "")")
            Swift.print("ready_for_pex=\(result.readyForPEX ?? false)")
            Swift.print("pex_corner=\(result.pexCornerID ?? "")")
            Swift.print("pex_elements=\(result.pexElementCount ?? 0)")
            Swift.print("external_signoff=\(signoffSource(result: result, options: options))")
            Swift.print("signoff_approved=\(signoffApproved(result: result, options: options))")
            Swift.print("comparison_limits=\(result.comparisonLimitsConfigured == true ? "configured" : "none")")
        case .runDesignRoundTrip:
            Swift.print("round_trip=passed")
            printDesignOrFixture(result: result, options: options)
            Swift.print("run_id=\(result.runID ?? "")")
            Swift.print("project_root=\(result.projectRootPath ?? "")")
            Swift.print("manifest=\(result.manifestPath ?? "")")
            Swift.print("ready_for_pex=\(result.readyForPEX ?? false)")
            Swift.print("pex_corner=\(result.pexCornerID ?? "")")
            Swift.print("pex_elements=\(result.pexElementCount ?? 0)")
            Swift.print("external_signoff=\(signoffSource(result: result, options: options))")
            Swift.print("signoff_approved=\(signoffApproved(result: result, options: options))")
            Swift.print("comparison_limits=\(result.comparisonLimitsConfigured == true ? "configured" : "none")")
        case .summarizeBottlenecks:
            let summary = result.bottleneckHistory
            Swift.print("bottlenecks=summarized")
            Swift.print("project_root=\(result.projectRootPath ?? "")")
            Swift.print("run_count=\(summary?.runCount ?? 0)")
            Swift.print("failed_run_count=\(summary?.failedRunCount ?? 0)")
            Swift.print("most_frequent_failed_stage=\(summary?.mostFrequentFailedStageName ?? "")")
            Swift.print("most_expensive_stage=\(summary?.mostExpensiveStageName ?? "")")
            for stageSummary in summary?.stageSummaries ?? [] {
                Swift.print(
                    "stage=\(stageSummary.stageName),observed=\(stageSummary.observedCount),failed=\(stageSummary.failedCount),avg_seconds=\(stageSummary.averageDurationSeconds)"
                )
            }
            for recommendation in summary?.recommendations ?? [] {
                Swift.print("recommendation=\(recommendation)")
            }
        case .loadTechnologyPackage:
            Swift.print("technology_package=loaded")
            Swift.print("technology_package_id=\(result.technologyPackageID ?? "")")
            Swift.print("technology_package_path=\(result.technologyPackagePath ?? "")")
            Swift.print("diagnostic_count=\(result.validationDiagnostics?.count ?? 0)")
        case .runPEXExtraction:
            Swift.print("pex_extraction=passed")
            Swift.print("pex_manifest=\(result.pexManifestPath ?? "")")
            Swift.print("pex_corner=\(result.pexCornerID ?? "")")
            Swift.print("pex_elements=\(result.pexElementCount ?? 0)")
        case .applyDesignEdit:
            Swift.print("design_edit=applied")
            Swift.print("design=\(result.designName ?? "")")
            Swift.print("design_spec=\(result.designSpecPath ?? "")")
            Swift.print("actions=\(result.actionLogPath ?? "")")
            Swift.print("design_diff=\(result.designDiffPath ?? "")")
        case .applyLayoutEdit:
            Swift.print("layout_edit=applied")
            Swift.print("layout_document=\(result.layoutDocumentPath ?? "")")
            Swift.print("actions=\(result.actionLogPath ?? "")")
            Swift.print("layout_diff=\(result.layoutDiffPath ?? "")")
        case .runVerification:
            Swift.print("verification=\(result.verificationReport?.status ?? "")")
            printDesignOrFixture(result: result, options: options)
            Swift.print("ready_for_pex=\(result.readyForPEX ?? false)")
            Swift.print("verification_report=\(result.verificationReportPath ?? "")")
            Swift.print("drc_passed=\(result.verificationReport?.drc.passed ?? false)")
            Swift.print("drc_violations=\(result.verificationReport?.drc.violationCount ?? 0)")
            Swift.print("lvs_passed=\(result.verificationReport?.lvs.passed ?? false)")
            Swift.print("external_signoff=\(signoffSource(result: result, options: options))")
            Swift.print("signoff_approved=\(result.verificationReport?.externalSignoff?.approved ?? false)")
        case .approveGate:
            Swift.print("gate_approval=\(result.approvalRecord?.decision.rawValue ?? "")")
            Swift.print("gate=\(result.approvalRecord?.gateID.rawValue ?? "")")
            Swift.print("reviewer=\(result.approvalRecord?.reviewer ?? "")")
            Swift.print("run_id=\(result.approvalRecord?.runID ?? "")")
            Swift.print("approval_record=\(result.approvalRecordPath ?? "")")
            Swift.print("target_sha256=\(result.approvalRecord?.targetArtifactSHA256 ?? "")")
            Swift.print("approval_warning_count=\(result.approvalRecord?.artifactResolutionWarnings.count ?? 0)")
            for warning in result.approvalRecord?.artifactResolutionWarnings ?? [] {
                Swift.print("approval_warning=\(warning)")
            }
        case .reviewRoundTrip:
            let review = result.roundTripReview
            Swift.print("round_trip_review=\(review?.status.rawValue ?? "")")
            Swift.print("run_id=\(review?.runID ?? result.runID ?? "")")
            Swift.print("manifest=\(review?.manifestPath ?? result.manifestPath ?? "")")
            Swift.print("ready_for_pex=\(review?.isReadyForPEX ?? false)")
            Swift.print("stage_count=\(review?.stages.count ?? 0)")
            Swift.print("artifact_count=\(review?.artifacts.count ?? 0)")
            Swift.print("diagnostic_count=\(review?.diagnostics.count ?? 0)")
            Swift.print("warning_count=\(review?.warnings.count ?? 0)")
            for warning in review?.warnings ?? [] {
                Swift.print("warning=\(warning)")
            }
            if let comparison = review?.postLayoutComparison {
                Swift.print("comparison_status=\(comparison.status)")
                Swift.print("comparison_gate=\(comparison.gateStatus)")
                for metric in comparison.oscillationMetrics {
                    Swift.print("oscillation_metric=\(metric.variableName)")
                    if let preFrequency = metric.preLayoutFrequency {
                        Swift.print("oscillation_pre_frequency=\(preFrequency)")
                    }
                    if let postFrequency = metric.postLayoutFrequency {
                        Swift.print("oscillation_post_frequency=\(postFrequency)")
                    }
                    if let frequencyRelativeDelta = metric.frequencyRelativeDelta {
                        Swift.print("oscillation_frequency_relative_delta=\(frequencyRelativeDelta)")
                    }
                    if let preAmplitude = metric.preLayoutAmplitude {
                        Swift.print("oscillation_pre_amplitude=\(preAmplitude)")
                    }
                    if let postAmplitude = metric.postLayoutAmplitude {
                        Swift.print("oscillation_post_amplitude=\(postAmplitude)")
                    }
                }
            }
            if let externalSignoff = review?.externalSignoff {
                Swift.print("signoff_passed=\(externalSignoff.passed)")
                Swift.print("signoff_approved=\(externalSignoff.approved)")
            }
            Swift.print("approval_count=\(review?.approvals.count ?? 0)")
            for approval in review?.approvals ?? [] {
                Swift.print("approval_gate=\(approval.gateID.rawValue)")
                Swift.print("approval_decision=\(approval.decision.rawValue)")
            }
            for recommendation in review?.recommendations ?? [] {
                Swift.print("recommendation=\(recommendation)")
            }
        }
    }

    private static func printDesignOrFixture(result: DesignFlowCommandResult, options: RunnerOptions) {
        if let designName = result.designName {
            Swift.print("design=\(designName)")
        } else {
            Swift.print("fixture=\(result.fixtureName ?? options.fixtureName)")
        }
        if let technologyPackageID = result.technologyPackageID {
            Swift.print("technology_package_id=\(technologyPackageID)")
        }
    }

    private static func signoffSource(result: DesignFlowCommandResult, options: RunnerOptions) -> String {
        if options.usesImportedSignoff {
            return "imported-logs"
        }
        if result.technologyPackageID != nil {
            return "technology-package"
        }
        return "none"
    }

    private static func signoffApproved(result: DesignFlowCommandResult, options: RunnerOptions) -> Bool {
        signoffSource(result: result, options: options) != "none" && options.approveSignoff
    }

    private static var helpText: String {
        """
        Usage:
          swift run circuit-studio-flow-runner [MODE] [--fixture \(DesignFlowFixtureLibrary.fixtureNames.joined(separator: "|"))] [--design-spec PATH] [--technology-package PATH] [--output PATH] [--run-id ID] [--approve-signoff] [--pex-manifest PATH] [--pex-config PATH] [--pex-executable PATH] [--pex-corner ID] [--signoff-drc-log PATH --signoff-lvs-log PATH] [--max-abs-delta VALUE] [--max-rel-delta VALUE] [--variable-limit SPEC] [--oscillation-limit SPEC] [--edit-script PATH --output-design-spec PATH]

        The runner executes the current headless round-trip flow:
          schematic -> netlist -> pre-layout simulation -> auto layout -> DRC/LVS gate -> PEX injection -> post-layout simulation -> comparison -> manifest

        Modes:
          --list-fixtures           List fixture names through DesignFlowCommand
          --generate-netlist        Generate a fixture netlist through DesignFlowCommand
          --simulate                Run fixture schematic simulation through DesignFlowCommand
          --summarize-bottlenecks   Summarize existing flow manifests under --output through DesignFlowCommand
          --load-technology-package Load and validate a technology package manifest through DesignFlowCommand
          --run-pex-extraction     Run pexengine extract through DesignFlowCommand
          --apply-design-edit      Apply a design edit script through DesignFlowCommand
          --apply-layout-edit      Apply a layout edit script through DesignFlowCommand
          --run-verification       Run DRC/LVS/pre-PEX verification without a full round trip
          --approve-gate           Write a typed gate approval record for human-in-the-loop review
          --review-round-trip      Load a round-trip review summary from manifest artifacts
          default                   Run the full fixture round trip through DesignFlowCommand

        Options:
          --fixture NAME   Fixture to run. Default: voltage-divider
          --design-spec PATH
                           Load a structured design spec JSON instead of a built-in fixture
          --edit-script PATH
                           JSON design edit script for --apply-design-edit
          --output-design-spec PATH
                           Edited design spec path for --apply-design-edit
          --layout-document PATH
                           Layout document JSON path for --apply-layout-edit or --run-verification
          --output-layout-document PATH
                           Edited layout document JSON path for --apply-layout-edit
          --design-unit PATH
                           Optional DesignUnit JSON path for --run-verification
          --manifest PATH Round-trip manifest path for --review-round-trip
          --approval-gate ID
                           Gate ID for --approve-gate. Values: external-signoff, pre-pex-verification, post-layout-comparison, physical-verification
          --approval-target PATH
                           Explicit target artifact path for --approve-gate
          --reviewer NAME Reviewer identity for --approve-gate
          --approval-decision VALUE
                           Approval decision. Values: approved, rejected. Default: approved
          --approval-policy TEXT
                           Policy text or policy ID recorded in the approval artifact
          --approval-note TEXT
                           Free-form note recorded in the approval artifact
          --waiver ID      Waiver ID recorded in the approval artifact. Can be repeated
          --technology-package PATH
                           Inject one technology package manifest into netlist, simulation, layout, signoff, and PEX inputs when supported
          --output PATH    Project/output directory. Default: ./round-trip-runs/<fixture-or-design-spec-name>
          --run-id ID      Flow run identifier. Default: fixture name plus timestamp
          --pex-manifest PATH
                           Load PEX IR through a saved PEXEngine manifest instead of using the built-in synthetic IR
          --pex-config PATH
                           PEX project config for --run-pex-extraction
          --pex-executable PATH
                           Explicit pexengine executable path for --run-pex-extraction
          --pex-corner ID  PEX corner to load from --pex-manifest. Default: tt_25c_1v0
          --signoff-drc-log PATH
                           Load an existing clean DRC log instead of running the mock DRC command
          --signoff-lvs-log PATH
                           Load an existing clean LVS log instead of running the mock LVS command
          --approve-signoff
                           Explicitly approve passing signoff reports for the PEX gate
          --max-abs-delta VALUE
                           Fail the post-layout comparison gate when the maximum absolute delta exceeds VALUE
          --max-rel-delta VALUE
                           Fail the post-layout comparison gate when the maximum relative delta exceeds VALUE
          --variable-limit SPEC
                           Add a variable-specific post-layout comparison gate. Format: VARIABLE:abs=VALUE,rel=VALUE
          --oscillation-limit SPEC
                           Add an oscillator metric gate. Format: VARIABLE:minTransitions=COUNT,minAmplitude=VALUE,freqRel=VALUE,periodRel=VALUE,duty=VALUE,threshold=VALUE
          --help           Show this help
        """
    }

}

private enum RunnerMode: Equatable {
    case listFixtures
    case generateNetlist
    case simulate
    case runRoundTrip
    case summarizeBottlenecks
    case loadTechnologyPackage
    case runPEXExtraction
    case applyDesignEdit
    case applyLayoutEdit
    case runVerification
    case approveGate
    case reviewRoundTrip

    func commandKind(usesDesignSpec: Bool) -> DesignFlowCommand.Kind {
        switch self {
        case .listFixtures:
            return .listFixtures
        case .generateNetlist:
            return usesDesignSpec ? .generateDesignNetlist : .generateFixtureNetlist
        case .simulate:
            return usesDesignSpec ? .runDesignSimulation : .runFixtureSimulation
        case .runRoundTrip:
            return usesDesignSpec ? .runDesignRoundTrip : .runFixtureRoundTrip
        case .summarizeBottlenecks:
            return .summarizeBottlenecks
        case .loadTechnologyPackage:
            return .loadTechnologyPackage
        case .runPEXExtraction:
            return .runPEXExtraction
        case .applyDesignEdit:
            return .applyDesignEdit
        case .applyLayoutEdit:
            return .applyLayoutEdit
        case .runVerification:
            return .runVerification
        case .approveGate:
            return .approveGate
        case .reviewRoundTrip:
            return .reviewRoundTrip
        }
    }
}

private struct RunnerOptions {
    var mode = RunnerMode.runRoundTrip
    private var explicitMode: RunnerMode?
    var fixtureName = DesignFlowFixtureLibrary.defaultFixtureName
    var designSpecURL: URL?
    var outputURL: URL?
    var runID: String?
    var pexManifestURL: URL?
    var pexConfigURL: URL?
    var pexExecutableURL: URL?
    var editScriptURL: URL?
    var outputDesignSpecURL: URL?
    var layoutDocumentURL: URL?
    var outputLayoutDocumentURL: URL?
    var designUnitURL: URL?
    var reviewManifestURL: URL?
    var approvalGateID: FlowGateID?
    var approvalTargetURL: URL?
    var approvalReviewer: String?
    var approvalDecision: GateApprovalDecision?
    var approvalPolicy: String?
    var approvalNote: String?
    var waiverIDs: [String] = []
    var pexCornerID = "tt_25c_1v0"
    var signoffDRCLogURL: URL?
    var signoffLVSLogURL: URL?
    var maxAbsoluteDelta: Double?
    var maxRelativeDelta: Double?
    var variableComparisonLimits: [PostLayoutVariableComparisonLimit] = []
    var oscillationMetricLimits: [PostLayoutOscillationMetricLimit] = []
    var technologyPackageURL: URL?
    var approveSignoff = false
    var showHelp = false

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--list-fixtures":
                try selectMode(.listFixtures)
            case "--generate-netlist":
                try selectMode(.generateNetlist)
            case "--simulate":
                try selectMode(.simulate)
            case "--summarize-bottlenecks":
                try selectMode(.summarizeBottlenecks)
            case "--load-technology-package":
                try selectMode(.loadTechnologyPackage)
            case "--run-pex-extraction":
                try selectMode(.runPEXExtraction)
            case "--apply-design-edit":
                try selectMode(.applyDesignEdit)
            case "--apply-layout-edit":
                try selectMode(.applyLayoutEdit)
            case "--run-verification":
                try selectMode(.runVerification)
            case "--approve-gate":
                try selectMode(.approveGate)
            case "--review-round-trip":
                try selectMode(.reviewRoundTrip)
            case "--fixture":
                fixtureName = try Self.value(after: argument, in: arguments, index: &index)
            case "--design-spec":
                designSpecURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--technology-package":
                technologyPackageURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--output":
                outputURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--run-id":
                runID = try Self.value(after: argument, in: arguments, index: &index)
            case "--pex-manifest":
                pexManifestURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--pex-config":
                pexConfigURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--pex-executable":
                pexExecutableURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--edit-script":
                editScriptURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--output-design-spec":
                outputDesignSpecURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--layout-document":
                layoutDocumentURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--output-layout-document":
                outputLayoutDocumentURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--design-unit":
                designUnitURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--manifest":
                reviewManifestURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--approval-gate":
                approvalGateID = try Self.gateID(after: argument, in: arguments, index: &index)
            case "--approval-target":
                approvalTargetURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--reviewer":
                approvalReviewer = try Self.value(after: argument, in: arguments, index: &index)
            case "--approval-decision":
                approvalDecision = try Self.approvalDecision(after: argument, in: arguments, index: &index)
            case "--approval-policy":
                approvalPolicy = try Self.value(after: argument, in: arguments, index: &index)
            case "--approval-note":
                approvalNote = try Self.value(after: argument, in: arguments, index: &index)
            case "--waiver":
                waiverIDs.append(try Self.value(after: argument, in: arguments, index: &index))
            case "--pex-corner":
                pexCornerID = try Self.value(after: argument, in: arguments, index: &index)
            case "--signoff-drc-log":
                signoffDRCLogURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--signoff-lvs-log":
                signoffLVSLogURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--max-abs-delta":
                maxAbsoluteDelta = try Self.doubleValue(after: argument, in: arguments, index: &index)
            case "--max-rel-delta":
                maxRelativeDelta = try Self.doubleValue(after: argument, in: arguments, index: &index)
            case "--variable-limit":
                variableComparisonLimits.append(
                    try Self.variableLimit(after: argument, in: arguments, index: &index)
                )
            case "--oscillation-limit":
                oscillationMetricLimits.append(
                    try Self.oscillationLimit(after: argument, in: arguments, index: &index)
                )
            case "--approve-signoff":
                approveSignoff = true
            case "--help", "-h":
                showHelp = true
            default:
                throw RunnerError.invalidArgument(argument)
            }
            index += 1
        }
    }

    private mutating func selectMode(_ mode: RunnerMode) throws {
        if let explicitMode, explicitMode != mode {
            throw RunnerError.conflictingModes
        }
        explicitMode = mode
        self.mode = mode
    }

    private static func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw RunnerError.missingValue(option)
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    private static func doubleValue(after option: String, in arguments: [String], index: inout Int) throws -> Double {
        let rawValue = try value(after: option, in: arguments, index: &index)
        guard let value = Double(rawValue),
              value.isFinite,
              value >= 0 else {
            throw RunnerError.invalidNumericValue(option, rawValue)
        }
        return value
    }

    private static func gateID(after option: String, in arguments: [String], index: inout Int) throws -> FlowGateID {
        let rawValue = try value(after: option, in: arguments, index: &index)
        guard let gateID = FlowGateID(rawValue: rawValue) else {
            throw RunnerError.invalidGateID(rawValue)
        }
        return gateID
    }

    private static func approvalDecision(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> GateApprovalDecision {
        let rawValue = try value(after: option, in: arguments, index: &index)
        guard let decision = GateApprovalDecision(rawValue: rawValue) else {
            throw RunnerError.invalidApprovalDecision(rawValue)
        }
        return decision
    }

    private static func variableLimit(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> PostLayoutVariableComparisonLimit {
        let rawValue = try value(after: option, in: arguments, index: &index)
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RunnerError.invalidVariableLimit(rawValue)
        }

        var maxAbsoluteDelta: Double?
        var maxRelativeDelta: Double?
        for assignment in parts[1].split(separator: ",").map(String.init) {
            let assignmentParts = assignment.split(separator: "=", maxSplits: 1).map(String.init)
            guard assignmentParts.count == 2 else {
                throw RunnerError.invalidVariableLimit(rawValue)
            }
            let key = assignmentParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let valueText = assignmentParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(valueText), value.isFinite, value >= 0 else {
                throw RunnerError.invalidVariableLimit(rawValue)
            }
            switch key {
            case "abs":
                maxAbsoluteDelta = value
            case "rel":
                maxRelativeDelta = value
            default:
                throw RunnerError.invalidVariableLimit(rawValue)
            }
        }

        let limit = PostLayoutVariableComparisonLimit(
            variableName: parts[0],
            maxAbsoluteDelta: maxAbsoluteDelta,
            maxRelativeDelta: maxRelativeDelta
        )
        guard limit.validationDiagnostics().isEmpty else {
            throw RunnerError.invalidVariableLimit(rawValue)
        }
        return limit
    }

    private static func oscillationLimit(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> PostLayoutOscillationMetricLimit {
        let rawValue = try value(after: option, in: arguments, index: &index)
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RunnerError.invalidOscillationLimit(rawValue)
        }

        var threshold: Double?
        var minTransitionCount: Int?
        var minAmplitude: Double?
        var maxFrequencyRelativeDelta: Double?
        var maxPeriodRelativeDelta: Double?
        var maxDutyCycleDelta: Double?

        for assignment in parts[1].split(separator: ",").map(String.init) {
            let assignmentParts = assignment.split(separator: "=", maxSplits: 1).map(String.init)
            guard assignmentParts.count == 2 else {
                throw RunnerError.invalidOscillationLimit(rawValue)
            }
            let key = assignmentParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let valueText = assignmentParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            switch key {
            case "threshold":
                threshold = try finiteDouble(valueText, rawValue: rawValue)
            case "minTransitions":
                guard let value = Int(valueText), value >= 0 else {
                    throw RunnerError.invalidOscillationLimit(rawValue)
                }
                minTransitionCount = value
            case "minAmplitude":
                minAmplitude = try nonNegativeDouble(valueText, rawValue: rawValue)
            case "freqRel":
                maxFrequencyRelativeDelta = try nonNegativeDouble(valueText, rawValue: rawValue)
            case "periodRel":
                maxPeriodRelativeDelta = try nonNegativeDouble(valueText, rawValue: rawValue)
            case "duty":
                maxDutyCycleDelta = try nonNegativeDouble(valueText, rawValue: rawValue)
            default:
                throw RunnerError.invalidOscillationLimit(rawValue)
            }
        }

        let limit = PostLayoutOscillationMetricLimit(
            variableName: parts[0],
            threshold: threshold,
            minTransitionCount: minTransitionCount,
            minAmplitude: minAmplitude,
            maxFrequencyRelativeDelta: maxFrequencyRelativeDelta,
            maxPeriodRelativeDelta: maxPeriodRelativeDelta,
            maxDutyCycleDelta: maxDutyCycleDelta
        )
        guard limit.validationDiagnostics().isEmpty else {
            throw RunnerError.invalidOscillationLimit(rawValue)
        }
        return limit
    }

    private static func finiteDouble(_ text: String, rawValue: String) throws -> Double {
        guard let value = Double(text), value.isFinite else {
            throw RunnerError.invalidOscillationLimit(rawValue)
        }
        return value
    }

    private static func nonNegativeDouble(_ text: String, rawValue: String) throws -> Double {
        let value = try finiteDouble(text, rawValue: rawValue)
        guard value >= 0 else {
            throw RunnerError.invalidOscillationLimit(rawValue)
        }
        return value
    }

    var usesImportedSignoff: Bool {
        signoffDRCLogURL != nil || signoffLVSLogURL != nil
    }

    var usesComparisonLimits: Bool {
        maxAbsoluteDelta != nil
            || maxRelativeDelta != nil
            || !variableComparisonLimits.isEmpty
            || !oscillationMetricLimits.isEmpty
    }

    var commandKind: DesignFlowCommand.Kind {
        mode.commandKind(usesDesignSpec: designSpecURL != nil)
    }
}

private enum RunnerError: Error, LocalizedError {
    case invalidArgument(String)
    case missingValue(String)
    case invalidNumericValue(String, String)
    case invalidVariableLimit(String)
    case invalidOscillationLimit(String)
    case invalidGateID(String)
    case invalidApprovalDecision(String)
    case conflictingModes

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let argument):
            return "Invalid argument: \(argument)"
        case .missingValue(let option):
            return "Missing value for \(option)"
        case .invalidNumericValue(let option, let value):
            return "Invalid numeric value for \(option): \(value)"
        case .invalidVariableLimit(let value):
            return "Invalid variable comparison limit: \(value)"
        case .invalidOscillationLimit(let value):
            return "Invalid oscillation metric limit: \(value)"
        case .invalidGateID(let value):
            return "Invalid approval gate ID: \(value)"
        case .invalidApprovalDecision(let value):
            return "Invalid approval decision: \(value)"
        case .conflictingModes:
            return "Only one runner mode can be selected."
        }
    }
}
