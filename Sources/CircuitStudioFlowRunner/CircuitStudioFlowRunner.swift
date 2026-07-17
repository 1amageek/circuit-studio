import Foundation
import CircuitStudioApp

@main
struct CircuitStudioFlowRunner {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let options: FlowRunnerCommandOptions
        do {
            options = try FlowRunnerCommandOptions(arguments: arguments)
        } catch {
            printUsageFailure(error, emitJSON: arguments.contains("--json"))
            exit(1)
        }

        if options.showHelp {
            Swift.print(Self.helpText)
            return
        }

        do {
            let designFlowService = DesignFlowService()
            let result = try await designFlowService.execute(options.makeCommand())
            try print(result: result, options: options)
        } catch {
            printRuntimeFailure(error, options: options)
            exit(1)
        }
    }

    private static func print(result: DesignFlowCommandResult, options: FlowRunnerCommandOptions) throws {
        switch options.outputFormat {
        case .keyValue:
            let context = FlowRunnerOutputContext(
                fixtureName: options.fixtureName,
                usesImportedSignoff: options.usesImportedSignoff,
                approveSignoff: options.approveSignoff
            )
            for line in FlowRunnerKeyValueFormatter.lines(for: result, context: context) {
                Swift.print(line)
            }
        case .json:
            Swift.print(try FlowRunnerJSONFormatter.string(for: result))
        }
    }

    private static func printUsageFailure(_ error: Error, emitJSON: Bool) {
        let failure = FlowRunnerFailureEnvelopeBuilder.usage(error: error)
        if emitJSON {
            printJSONFailure(failure)
            return
        }
        fputs("flow_command=failed\n", stderr)
        fputs("error_kind=usage\n", stderr)
        fputs("error_type=\(failure.errorType)\n", stderr)
        fputs("error=\(failure.message)\n", stderr)
        fputs("help_hint=\(failure.helpHint ?? "")\n", stderr)
    }

    private static func printRuntimeFailure(_ error: Error, options: FlowRunnerCommandOptions) {
        let failure = FlowRunnerFailureEnvelopeBuilder.runtime(error: error, options: options)
        if options.outputFormat == .json {
            printJSONFailure(failure)
            return
        }
        fputs("flow_command=failed\n", stderr)
        fputs("error_kind=\(failure.errorKind)\n", stderr)
        fputs("error_type=\(failure.errorType)\n", stderr)
        fputs("error=\(failure.message)\n", stderr)
        if let runID = failure.runID {
            fputs("run_id=\(runID)\n", stderr)
        }
        if let projectRoot = failure.projectRoot {
            fputs("project_root=\(projectRoot)\n", stderr)
        }
        if let manifest = failure.manifest {
            fputs("manifest=\(manifest)\n", stderr)
            if let failedStage = failure.stage {
                fputs("stage=\(failedStage)\n", stderr)
            }
        }
        fputs("recommendation=\(failure.recommendation)\n", stderr)
    }

    private static func printJSONFailure(_ failure: FlowRunnerFailureEnvelope) {
        do {
            fputs(try FlowRunnerJSONFormatter.string(for: failure), stderr)
            fputs("\n", stderr)
        } catch {
            fputs("flow_command=failed\n", stderr)
            fputs("error_kind=\(failure.errorKind)\n", stderr)
            fputs("error_type=\(failure.errorType)\n", stderr)
            fputs("error=\(failure.message)\n", stderr)
            fputs("json_error=\(error.localizedDescription)\n", stderr)
        }
    }

    private static var helpText: String {
        """
        Usage:
          swift run circuit-studio-flow-runner [MODE] [--fixture \(DesignFlowFixtureLibrary.fixtureNames.joined(separator: "|"))] [--design-spec PATH] [--technology-package PATH] [--output PATH] [--run-id ID] [--approve-signoff] [--pex-manifest PATH] [--pex-config PATH] [--pex-executable PATH] [--pex-corner ID] [--timing-model-profile PATH | --timing-model-profile-catalog PATH --timing-model-profile-id ID | --timing-model-profile-catalog PATH --timing-model-corner ID] [--signoff-drc-log PATH --signoff-lvs-log PATH] [--max-abs-delta VALUE] [--max-rel-delta VALUE] [--relative-delta-floor VALUE] [--domain-limit SPEC] [--variable-limit SPEC] [--oscillation-limit SPEC] [--edit-script PATH --output-design-spec PATH] [--waiver-review ID --waiver-proposal ID] [--drc-repair-hints PATH --lvs-repair-hints PATH] [--history-qualification-profile PATH] [--min-history-runs COUNT] [--min-history-cycles COUNT] [--min-history-accepted COUNT] [--min-history-feedback-rank-changes COUNT] [--min-history-feedback-score-deltas COUNT] [--failure-envelope PATH --action-id ID --reviewer ID] [--json]

        The runner executes the current headless round-trip flow:
          schematic -> netlist -> pre-layout simulation -> auto layout -> DRC/LVS gate -> PEX injection -> post-layout simulation -> comparison -> manifest

        Modes:
          --list-fixtures           List fixture names through DesignFlowCommand
          --generate-netlist        Generate a fixture netlist through DesignFlowCommand
          --simulate                Run fixture schematic simulation through DesignFlowCommand
          --summarize-bottlenecks   Summarize existing flow manifests under --output through DesignFlowCommand
          --summarize-signoff-repair-cycles
                                  Summarize persisted signoff repair candidate-cycle history under --output
          --qualify-signoff-repair-cycles
                                  Qualify retained signoff repair candidate-cycle history against promotion thresholds
          --load-technology-package Load and validate a technology package manifest through DesignFlowCommand
          --run-pex-extraction     Run pexengine extract through DesignFlowCommand
          --inspect-timing-model-profiles
                                  Inspect timing model profile catalog entries without running characterization
          --build-timing-library   Characterize the standard timing library and write timing artifacts
          --apply-design-edit      Apply a design edit script through DesignFlowCommand
          --apply-layout-edit      Apply a layout edit script through DesignFlowCommand
          --run-layout-trust      Run ownership + net-aware topology evaluation for a layout document
          --run-verification       Run DRC/LVS/pre-PEX verification without a full round trip
          --approve-gate           Write a typed gate approval record for human-in-the-loop review
          --review-round-trip      Load a round-trip review summary from manifest artifacts
          --select-failure-action
                                  Record a selected semantic action from a flow-runner failure envelope into the round-trip action log
          --run-selected-suggested-action
                                  Dispatch a ready selected semantic action through the typed command API
          --apply-waiver-edit      Apply a selected waiver edit proposal through RunReviewService
          --apply-waiver-edit-and-verify
                                  Apply a selected waiver edit proposal, then run linked DRC/LVS/pre-PEX verification
          --run-post-waiver-edit-verification
                                  Run DRC/LVS/pre-PEX verification and link it to an applied waiver edit
          --formulate-signoff-repair-planning
                                  Compile DRC/LVS repair hint reports into planning artifacts and record the action
          --run-signoff-repair-candidate-cycle
                                  Compile signoff repair planning artifacts, generate a candidate plan, execute it, and verify it
          --run-goal-layout-agent
                                  Close a .subckt intent through layout goal commands (place/bind/finish/repair), gate on trust + replay determinism, and export evidence + GDS
          --scaffold-design-spec
                                  Write a minimal valid design spec JSON skeleton to --output-design-spec that --generate-netlist --design-spec consumes unchanged
          default                   Run the full fixture round trip through DesignFlowCommand

        Options:
          --fixture NAME   Fixture to run. Default: voltage-divider
          --design-spec PATH
                           Load a structured design spec JSON instead of a built-in fixture
          --subckt PATH    .subckt intent file for --run-goal-layout-agent
          --design-name NAME
                           Top cell name for --run-goal-layout-agent (default: the .subckt header name),
                           or the design name for --scaffold-design-spec (default: new_design)
          --edit-script PATH
                           JSON design edit script for --apply-design-edit
          --output-design-spec PATH
                           Edited design spec path for --apply-design-edit,
                           or the scaffold destination for --scaffold-design-spec
          --layout-document PATH
                           Layout document JSON path for --apply-layout-edit, --run-verification, --apply-waiver-edit-and-verify, or --run-post-waiver-edit-verification
          --output-layout-document PATH
                           Edited layout document JSON path for --apply-layout-edit
          --design-unit PATH
                           Optional DesignUnit JSON path for --run-verification, --apply-waiver-edit-and-verify, or --run-post-waiver-edit-verification
          --manifest PATH Round-trip manifest path for --review-round-trip
          --failure-envelope PATH
                           flow-runner-failure JSON envelope for --select-failure-action
          --action-id ID   Suggested semantic action ID selected from --failure-envelope
                           or selected from the round-trip action log for --run-selected-suggested-action
          --approval-stage ID
                           Flow stage ID for --approve-gate
          --reviewer NAME Reviewer identity for --approve-gate
          --approval-verdict VALUE
                           Approval verdict. Values: approved, waived, rejected. Default: approved
          --approval-note TEXT
                           Free-form note recorded in the approval artifact
          --waiver-review ID
                           Waiver review ID for --apply-waiver-edit, --apply-waiver-edit-and-verify, or --run-post-waiver-edit-verification
          --waiver-proposal ID
                           Waiver edit proposal ID for --apply-waiver-edit, --apply-waiver-edit-and-verify, or --run-post-waiver-edit-verification
          --actor-kind VALUE
                           Actor kind for review actions. Values: human, agent, cli, system. Default: human
          --drc-repair-hints PATH
                           Project-relative DRC repair hint report for --formulate-signoff-repair-planning
          --lvs-repair-hints PATH
                           Project-relative LVS repair hint report for --formulate-signoff-repair-planning
          --formulation-id ID
                           Optional repair formulation artifact ID for --formulate-signoff-repair-planning
          --intent-id ID   Optional repair intent ID for --formulate-signoff-repair-planning
          --intent TEXT    Optional repair intent text for --formulate-signoff-repair-planning
          --problem-id ID  Optional planning problem ID for --formulate-signoff-repair-planning
          --candidate-strategy TEXT
                           Candidate generation strategy for --run-signoff-repair-candidate-cycle
          --candidate-verification-mode TEXT
                           Candidate verification mode for --run-signoff-repair-candidate-cycle. Default: post-execution
          --history-qualification-profile PATH
                           JSON profile that defines retained-history qualification thresholds for --qualify-signoff-repair-cycles
          --min-history-runs COUNT
                           Minimum retained run count for --qualify-signoff-repair-cycles. Overrides profile value. Default: 1
          --min-history-cycles COUNT
                           Minimum retained candidate-cycle count for --qualify-signoff-repair-cycles. Overrides profile value. Default: 1
          --min-history-accepted COUNT
                           Minimum accepted candidate-cycle count for --qualify-signoff-repair-cycles. Overrides profile value. Default: 0
          --min-history-feedback-rank-changes COUNT
                           Minimum rejected-feedback rank-change count for --qualify-signoff-repair-cycles. Overrides profile value. Default: 0
          --min-history-feedback-score-deltas COUNT
                           Minimum rejected-feedback score-delta count for --qualify-signoff-repair-cycles. Overrides profile value. Default: 0
          --technology-package PATH
                           Inject one technology package manifest into netlist, simulation, layout, signoff, and PEX inputs.
                           Required for --run-layout-trust and --run-verification.
          --output PATH    Project/output directory. Default: ./round-trip-runs/<fixture-or-design-spec-name>
          --run-id ID      Flow run identifier. Default: fixture name plus timestamp
          --pex-manifest PATH
                           Load PEX IR through a saved PEXEngine manifest instead of using the built-in synthetic IR
          --pex-config PATH
                           PEX project config for --run-pex-extraction
          --pex-executable PATH
                           Explicit pexengine executable path for --run-pex-extraction
          --pex-corner ID  PEX corner to load from --pex-manifest. Default: tt_25c_1v0
          --timing-model-profile PATH
                           Timing model profile JSON for --build-timing-library
          --timing-model-profile-catalog PATH
                           Timing model profile catalog JSON for --build-timing-library. Relative profile paths resolve from the catalog directory
          --timing-model-profile-id ID
                           Timing model profile ID to select from the explicit or bundled timing model profile catalog. Default: bundled catalog default
          --timing-model-corner ID
                           Timing model corner ID to select from the explicit or bundled timing model profile catalog
          --signoff-drc-log PATH
                           Load an existing clean DRC log instead of running the mock DRC command
          --signoff-lvs-log PATH
                           Load an existing clean LVS log instead of running the mock LVS command
          --approve-signoff
                           Approve passing signoff reports for the PEX gate. Recorded as an
                           AUTOMATED approval (approval_kind=automated, approved_by=design-flow-command),
                           distinct from human approvals recorded through the review cockpit
          --json           Emit the full DesignFlowCommandResult or failure envelope as JSON for Agent/API callers
          --max-abs-delta VALUE
                           Fail the post-layout comparison gate when the maximum absolute delta exceeds VALUE
          --max-rel-delta VALUE
                           Fail the post-layout comparison gate when the maximum relative delta exceeds VALUE
          --relative-delta-floor VALUE
                           Floor the relative-delta denominator for global post-layout comparison gates
          --domain-limit SPEC
                           Add a domain-specific post-layout comparison gate. Format: DOMAIN:abs=VALUE,rel=VALUE,floor=VALUE
                           Domains: voltage,current,time,frequency,power,phase,magnitude,parameter,other
          --variable-limit SPEC
                           Add a variable-specific post-layout comparison gate. Format: VARIABLE:abs=VALUE,rel=VALUE,floor=VALUE
          --oscillation-limit SPEC
                           Add an oscillator metric gate. Format: VARIABLE:minTransitions=COUNT,minAmplitude=VALUE,freqRel=VALUE,periodRel=VALUE,duty=VALUE,threshold=VALUE
          --help           Show this help
        """
    }

}
